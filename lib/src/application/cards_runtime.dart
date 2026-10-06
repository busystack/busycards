import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:busystack_contacts/google.dart';
import 'package:busystack_contacts/microsoft.dart';
import 'package:busystack_contacts/carddav.dart';
import 'package:busystack_dav/carddav.dart';
import 'package:busystack_dav/nextcloud.dart';
import 'package:busystack_graph/busystack_graph.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart' show AccessCredentials;
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/google/google_oauth_service.dart';
import '../auth/microsoft/microsoft_auth_bridge.dart';
import '../storage/secret_value_store.dart';

final class CardsRegistration {
  const CardsRegistration({
    this.googleClientId = '',
    this.googleClientSecret = '',
    this.microsoftClientId = '',
  });
  final String googleClientId, googleClientSecret, microsoftClientId;
  GoogleOAuthConfiguration get google => GoogleOAuthConfiguration(
    clientId: googleClientId,
    clientSecret: googleClientSecret,
  );
  Map<String, Object?> toJson() => {
    'googleId': googleClientId,
    'googleSecret': googleClientSecret,
    'microsoftId': microsoftClientId,
  };
  factory CardsRegistration.fromJson(Map<String, dynamic> j) =>
      CardsRegistration(
        googleClientId: j['googleId'] as String? ?? '',
        googleClientSecret: j['googleSecret'] as String? ?? '',
        microsoftClientId: j['microsoftId'] as String? ?? '',
      );
}

final class CardsItemResult {
  const CardsItemResult(this.label, {this.mutation, this.error});
  final String label;
  final ContactMutation? mutation;
  final String? error;
  bool get succeeded =>
      mutation?.state == ContactMutationState.confirmed && error == null;
}

/// App-owned authorization, credential protection, scheduling and UI use cases.
/// No widget has a provider HTTP path. The three shared packages remain pure Dart.
final class CardsRuntime {
  CardsRuntime({
    required this.store,
    required this.secrets,
    required this.profile,
    this.helperPath,
    this.httpClientFactory,
    Future<bool> Function(Uri)? browserLauncher,
  }) : directory = ContactsDirectory(store: store),
       _browser = browserLauncher ?? _openBrowser;
  final ContactsStore store;
  final SecretValueStore secrets;
  final Directory profile;
  final String? helperPath;

  /// App-owned transport injection. Default production clients retain normal
  /// TLS validation; fixtures can drive the actual application/provider paths.
  final http.Client Function()? httpClientFactory;
  final ContactsDirectory directory;
  final Future<bool> Function(Uri) _browser;
  final _google = <String, GoogleOAuthService>{};
  final _microsoft = <String, MicrosoftAuthBridge>{};
  final _carddav = <String, CardDavContactsProvider>{};
  final _busy = <String, Future<void>>{};
  final _epochs = <String, int>{};
  final _uuid = const Uuid();
  GoogleOAuthService? _googleSetup;
  MicrosoftAuthBridge? _microsoftSetup;
  DavCancellationToken? _nextcloudSetup;
  ContactsCancellationToken? _davSetup;
  Timer? _timer;
  Future<void>? _closeFuture;
  bool _closed = false;
  Future<void> _enrollmentTail = Future<void>.value();
  Stream<void> get changes => store.changes;
  static Future<bool> _openBrowser(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<CardsRegistration> registration() async {
    final json = await secrets.read('registrations-v1');
    return json == null
        ? const CardsRegistration()
        : CardsRegistration.fromJson((jsonDecode(json) as Map).cast());
  }

  Future<void> saveRegistration(CardsRegistration value) async {
    if (value.microsoftClientId.isNotEmpty &&
        !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}$')
            .hasMatch(value.microsoftClientId)) {
      throw const ContactsException(
        ContactsFailure.validation,
        'microsoft-public-client-id-invalid',
      );
    }
    if (value.googleClientId.isNotEmpty &&
        !value.googleClientId.endsWith('.apps.googleusercontent.com')) {
      throw const ContactsException(
        ContactsFailure.validation,
        'google-desktop-client-id-invalid',
      );
    }
    final encoded = jsonEncode(value.toJson());
    await secrets.write('registrations-v1', encoded);
    if (await secrets.read('registrations-v1') != encoded)
      throw const ContactsException(
        ContactsFailure.authentication,
        'registration-persistence-failed',
      );
  }

  Future<void> start({bool schedule = true}) async {
    await _recoverEnrollments();
    await directory.restore();
    for (final account in await store.read((tx) async => tx.accounts())) {
      if (!account.enabled) continue;
      try {
        await _bind(account);
      } catch (_) {
        await _accountError(account.id, 'reconnect-required');
      }
    }
    if (schedule) {
      _timer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => unawaited(synchronizeAll()),
      );
      unawaited(synchronizeAll());
    }
  }

  Future<void> synchronizeAll() async {
    for (final account in await store.read((tx) async => tx.accounts())) {
      if (account.enabled)
        unawaited(synchronizeAccount(account.id).catchError((Object _) {}));
    }
  }

  Future<void> synchronizeAccount(String id) => _busy.putIfAbsent(
    id,
    () => _sync(id).whenComplete(() {
      _busy.remove(id);
    }),
  );
  Future<void> _sync(String id) async {
    final epoch = _epochs[id] ?? 0;
    try {
      final sources = await directory.discover(id);
      await directory.resumeQueued(id);
      for (final source in sources) {
        if (_closed || (_epochs[id] ?? 0) != epoch) return;
        if (source.capabilities.read) await directory.synchronize(source.key);
      }
      if ((_epochs[id] ?? 0) == epoch) await _accountError(id, null);
    } catch (error) {
      if ((_epochs[id] ?? 0) == epoch)
        await _accountError(id, safeError(error));
      rethrow;
    }
  }

  bool isSyncing(String id) => _busy.containsKey(id);
  Future<void> _accountError(String id, String? error) => store.write((
    tx,
  ) async {
    final account = await tx.account(id);
    if (account != null) await tx.putAccount(account.copy(errorCode: error));
  });

  Future<ContactAccount> connectGoogle({
    required String label,
    bool readOnly = false,
    ContactAccount? reconnect,
  }) async {
    final registration = await this.registration();
    if (!registration.google.isConfigured)
      throw const ContactsException(
        ContactsFailure.authentication,
        'busycards-google-desktop-registration-missing',
      );
    final id = reconnect?.id ?? _uuid.v7(),
        epoch = _epochs[reconnect?.id ?? 'setup'] ?? 0;
    final oauth = GoogleOAuthService(
      configuration: registration.google,
      secrets: _googleSecrets(id),
      profileId: profile.path + '/' + id,
      browserLauncher: _browser,
      requestedScopes: [
        'openid',
        'email',
        'profile',
        readOnly
            ? 'https://www.googleapis.com/auth/contacts.readonly'
            : 'https://www.googleapis.com/auth/contacts',
      ],
    );
    _googleSetup = oauth;
    try {
      final previous = reconnect == null
          ? null
          : await oauth.readCredentials(reconnect.subject);
      final identity = await oauth.authorize(
        expectedSubject: reconnect?.subject,
        persistCredentials: false,
        successPage: '<html><body>BusyCards is connected. You can close this window.</body></html>',
        failurePage: '<html><body>BusyCards could not connect. Return to Settings.</body></html>',
      );
      if (_closed || (_epochs[reconnect?.id ?? 'setup'] ?? 0) != epoch)
        throw const ContactsException(
          ContactsFailure.cancelled,
          'authorization-cancelled',
        );
      final account = ContactAccount(
        id: id,
        provider: ContactProviderKind.google,
        displayName: label,
        subject: identity.subject,
        grantedScopes: identity.credentials.scopes.toSet(),
        generation: (reconnect?.generation ?? -1) + 1,
      );
      await _commit(
        account,
        {
          'type': 'google',
          'registration': registration.toJson(),
          'requestedReadOnly': readOnly,
        },
        authorization: () => oauth.commitIdentity(identity),
        rollbackData: {
          'googlePrevious': previous?.toJson(),
          'registration': registration.toJson(),
        },
      );
      return account;
    } finally {
      if (identical(_googleSetup, oauth)) _googleSetup = null;
      await oauth.close();
    }
  }

  Future<ContactAccount> connectMicrosoft({
    required String label,
    bool readOnly = false,
    ContactAccount? reconnect,
  }) async {
    final registration = await this.registration();
    if (registration.microsoftClientId.isEmpty)
      throw const ContactsException(
        ContactsFailure.authentication,
        'busycards-microsoft-public-client-registration-missing',
      );
    final id = reconnect?.id ?? _uuid.v7();
    final helper = _bridge(registration.microsoftClientId, readOnly, id);
    _microsoftSetup = helper;
    final epoch = _epochs[reconnect?.id ?? 'setup'] ?? 0;
    try {
      await helper.verifyProtocol();
      final token = await helper.authorize();
      if (reconnect != null && reconnect.subject != token.homeAccountId)
        throw const MicrosoftAuthException('wrong-account');
      final required = readOnly ? 'Contacts.Read' : 'Contacts.ReadWrite';
      if (!token.scopes.any(
        (s) =>
            s.toLowerCase() == required.toLowerCase() ||
            readOnly && s.toLowerCase() == 'contacts.readwrite',
      ))
        throw const MicrosoftAuthException('contacts-permission-not-granted');
      if (_closed || (_epochs[reconnect?.id ?? 'setup'] ?? 0) != epoch)
        throw const ContactsException(
          ContactsFailure.cancelled,
          'authorization-cancelled',
        );
      final account = ContactAccount(
        id: id,
        provider: ContactProviderKind.microsoft,
        displayName: label,
        subject: token.homeAccountId,
        grantedScopes: token.scopes.toSet(),
        generation: (reconnect?.generation ?? -1) + 1,
      );
      await _commit(account, {
        'type': 'microsoft',
        'registration': registration.toJson(),
        'requestedReadOnly': readOnly,
        'tenant': token.tenantId,
      });
      return account;
    } finally {
      if (identical(_microsoftSetup, helper)) _microsoftSetup = null;
      await helper.close();
    }
  }

  MicrosoftAuthBridge _bridge(String id, bool readOnly, String accountId) =>
      MicrosoftAuthBridge(
        clientId: id,
        executablePath: helperPath,
        requestedScopes: [
          'openid',
          'profile',
          'email',
          readOnly ? 'Contacts.Read' : 'Contacts.ReadWrite',
          'offline_access',
        ],
        start: (executable, arguments) async {
          final data = Directory(profile.path + '/microsoft/' + accountId);
          await data.create(recursive: true);
          return Process.start(
            executable,
            arguments,
            environment: {
              'XDG_DATA_HOME': data.path,
              'XDG_CONFIG_HOME': data.path + '/config',
              'XDG_CACHE_HOME': data.path + '/cache',
            },
          );
        },
      );
  Future<ContactAccount> connectCardDav({
    required String label,
    required Uri server,
    required String username,
    required String password,
    bool readOnly = false,
    bool nextcloud = false,
    ContactAccount? reconnect,
  }) async {
    if (server.scheme != 'https' ||
        server.host.isEmpty ||
        server.userInfo.isNotEmpty ||
        server.query.isNotEmpty ||
        server.fragment.isNotEmpty)
      throw const ContactsException(
        ContactsFailure.validation,
        'https-carddav-url-required',
      );
    if (username.isEmpty || password.isEmpty || username.contains(':'))
      throw const ContactsException(
        ContactsFailure.validation,
        'dav-credentials-required',
      );
    if (reconnect != null &&
        reconnect.subject != username + '@' + server.origin) {
      throw const ContactsException(
        ContactsFailure.authentication,
        'wrong-dav-identity',
      );
    }
    final account = ContactAccount(
      id: reconnect?.id ?? _uuid.v7(),
      provider: ContactProviderKind.carddav,
      displayName: label,
      subject: username + '@' + server.origin,
      grantedScopes: {readOnly ? 'dav:read' : 'dav:advertised-write'},
      generation: (reconnect?.generation ?? -1) + 1,
    );
    final config = {
      'type': 'carddav',
      'server': server.toString(),
      'username': username,
      'password': password,
      'requestedReadOnly': readOnly,
      'nextcloud': nextcloud,
    };
    // Validate discovery before replacing an existing connection or persisting credentials.
    final provider = _dav(account, config);
    final token = ContactsCancellationToken();
    _davSetup = token;
    try {
      final sources = await provider.discover(token);
      if (sources.isEmpty)
        throw const ContactsException(
          ContactsFailure.permission,
          'no-readable-address-books',
        );
      token.throwIfCancelled();
    } finally {
      if (identical(_davSetup, token)) _davSetup = null;
      provider.close();
    }
    token.throwIfCancelled();
    await _commit(account, config);
    return account;
  }

  Future<ContactAccount> connectNextcloud({
    required String label,
    required Uri server,
    bool readOnly = false,
    ContactAccount? reconnect,
  }) async {
    final token = DavCancellationToken();
    _nextcloudSetup = token;
    final login = NextcloudLoginFlowV2(server: server, launchBrowser: _browser);
    try {
      final result = await login.authenticate(token);
      return await connectCardDav(
        label: label,
        server: result.server,
        username: result.loginName,
        password: result.appPassword,
        readOnly: readOnly,
        nextcloud: true,
        reconnect: reconnect,
      );
    } finally {
      if (identical(_nextcloudSetup, token)) _nextcloudSetup = null;
      login.close();
    }
  }

  Future<void> cancelAuthorization() async {
    _epochs['setup'] = (_epochs['setup'] ?? 0) + 1;
    _nextcloudSetup?.cancel();
    _davSetup?.cancel();
    await _googleSetup?.close();
    await _microsoftSetup?.close();
  }

  SecretValueStore _googleSecrets(String id) =>
      ScopedSecretValueStore(secrets, 'google/' + id + '/');
  Future<void> _commit(
    ContactAccount account,
    Map<String, Object?> config, {
    Future<void> Function()? authorization,
    Map<String, Object?> rollbackData = const {},
  }) {
    final result = _enrollmentTail.then(
      (_) => _commitSerialized(
        account,
        config,
        authorization: authorization,
        rollbackData: rollbackData,
      ),
    );
    _enrollmentTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _writeEnrollmentJournal(Map<String, dynamic> journal) async {
    final encoded = jsonEncode(journal);
    await secrets.write('enrollments-v1', encoded);
    if (await secrets.read('enrollments-v1') != encoded)
      throw StateError('Enrollment journal persistence failed');
  }

  Future<void> _recoverEnrollments() async {
    final encoded = await secrets.read('enrollments-v1');
    if (encoded == null) return;
    final journal = (jsonDecode(encoded) as Map).cast<String, dynamic>();
    for (final entry in journal.entries.toList()) {
      final snapshot = (entry.value as Map).cast<String, dynamic>();
      if (snapshot['committed'] != true)
        await _rollbackEnrollment(entry.key, snapshot);
      journal.remove(entry.key);
      await _writeEnrollmentJournal(journal);
    }
  }

  Future<void> _rollbackEnrollment(
    String id,
    Map<String, dynamic> snapshot,
  ) async {
    final oldConfig = snapshot['oldConfig'] as String?;
    final oldAccount = snapshot['oldAccount'] == null
        ? null
        : ContactAccount.fromJson((snapshot['oldAccount'] as Map).cast());
    final newAccount = ContactAccount.fromJson(
      (snapshot['newAccount'] as Map).cast(),
    );
    if (snapshot.containsKey('googlePrevious')) {
      final registration = CardsRegistration.fromJson(
        (snapshot['registration'] as Map).cast(),
      );
      final oauth = GoogleOAuthService(
        configuration: registration.google,
        secrets: _googleSecrets(id),
        profileId: profile.path + '/' + id,
      );
      try {
        if (snapshot['googlePrevious'] == null)
          await oauth.removeCredentials(newAccount.subject);
        else
          await oauth.commitIdentity(
            GoogleIdentity(
              subject: newAccount.subject,
              credentials: AccessCredentials.fromJson(
                (snapshot['googlePrevious'] as Map).cast(),
              ),
            ),
          );
      } finally {
        await oauth.close();
      }
    }
    if (oldConfig == null)
      await secrets.delete('connection/' + id);
    else
      await secrets.write('connection/' + id, oldConfig);
    if (await secrets.read('connection/' + id) != oldConfig)
      throw StateError('Enrollment rollback requires recovery');
    await store.write((tx) async {
      if (oldAccount == null)
        await tx.removeAccount(id);
      else
        await tx.putAccount(oldAccount);
    });
  }

  Future<void> _commitSerialized(
    ContactAccount account,
    Map<String, Object?> config, {
    Future<void> Function()? authorization,
    Map<String, Object?> rollbackData = const {},
  }) async {
    if (_closed)
      throw const ContactsException(
        ContactsFailure.cancelled,
        'runtime-closed',
      );
    final key = 'connection/' + account.id,
        old = await secrets.read('connection/' + account.id);
    final encoded = jsonEncode(config);
    final oldAccount = await store.read((tx) async => tx.account(account.id));
    final journalText = await secrets.read('enrollments-v1');
    final journal = journalText == null
        ? <String, dynamic>{}
        : (jsonDecode(journalText) as Map).cast<String, dynamic>();
    final snapshot = <String, dynamic>{
      'oldConfig': old,
      'oldAccount': oldAccount?.toJson(),
      'newAccount': account.toJson(),
      ...rollbackData,
    };
    journal[account.id] = snapshot;
    await _writeEnrollmentJournal(journal);
    try {
      if (oldAccount != null) await _drain(account.id);
      await authorization?.call();
      await secrets.write(key, encoded);
      if (await secrets.read(key) != encoded)
        throw StateError('Credential persistence failed');
      await store.write((tx) async => tx.putAccount(account));
      await _bind(account);
      journal[account.id] = {...snapshot, 'committed': true};
      await _writeEnrollmentJournal(journal);
    } catch (_) {
      await _drain(account.id);
      await _rollbackEnrollment(account.id, snapshot);
      if (oldAccount?.enabled == true) await _bind(oldAccount!);
      journal.remove(account.id);
      await _writeEnrollmentJournal(journal);
      rethrow;
    }
    journal.remove(account.id);
    await _writeEnrollmentJournal(journal);
    unawaited(synchronizeAccount(account.id).catchError((Object _) {}));
  }

  Future<void> _bind(ContactAccount account) async {
    final encoded = await secrets.read('connection/' + account.id);
    if (encoded == null)
      throw const ContactsException(
        ContactsFailure.authentication,
        'connection-credentials-missing',
      );
    final config = (jsonDecode(encoded) as Map).cast<String, dynamic>();
    final readOnly = config['requestedReadOnly'] == true;
    switch (account.provider) {
      case ContactProviderKind.google:
        final registration = CardsRegistration.fromJson(
          (config['registration'] as Map).cast(),
        );
        final oauth = GoogleOAuthService(
          configuration: registration.google,
          secrets: _googleSecrets(account.id),
          profileId: profile.path + '/' + account.id,
        );
        _google[account.id] = oauth;
        directory.bind(
          GoogleContactsProvider(
            accountId: account.id,
            grantedScopes: account.grantedScopes,
            authorizedClient: _GoogleAuthorizedClient(
              oauth,
              account.subject,
              httpClient: httpClientFactory?.call(),
            ),
          ),
        );
      case ContactProviderKind.microsoft:
        final registration = CardsRegistration.fromJson(
          (config['registration'] as Map).cast(),
        );
        final helper = _bridge(
          registration.microsoftClientId,
          readOnly,
          account.id,
        );
        _microsoft[account.id] = helper;
        final graph = GraphClient(
          httpClient: httpClientFactory?.call(),
          tokenProvider: ({String? claims}) async {
            final token = await helper.acquireToken(
              account.subject,
              claims: claims,
            );
            return GraphAuthorization(
              token.value,
              grantedScopes: token.scopes.toSet(),
            );
          },
        );
        directory.bind(
          MicrosoftContactsProvider(
            accountId: account.id,
            graph: graph,
            grantedScopes: account.grantedScopes,
            personalAccount:
                config['tenant'] == '9188040d-6c67-4c5b-b112-36a304b66dad',
          ),
        );
      case ContactProviderKind.carddav:
        final provider = _dav(account, config);
        _carddav[account.id] = provider;
        directory.bind(provider);
    }
  }

  CardDavContactsProvider _dav(
    ContactAccount account,
    Map<String, dynamic> config,
  ) {
    final server = Uri.parse(config['server'] as String),
        httpClient = httpClientFactory?.call() ?? NativeTerminatingHttpClient();
    final policy = config['nextcloud'] == true
        ? const DavProviderProfile.nextcloud()
        : const DavProviderProfile();
    final resources = DavResourceClient(
      accountId: account.id,
      authority: server,
      profile: policy,
      streaming: DavTransferClient(
        client: httpClient,
        authority: server,
        profile: policy,
      ),
      credentialProvider: () async => DavBasicCredential(
        username: config['username'] as String,
        password: config['password'] as String,
      ),
      transport: DavHttpTransport(
        client: httpClient,
        profile: policy,
        accountAuthority: server,
      ),
    );
    return CardDavContactsProvider(
      accountId: account.id,
      client: CardDavClient(resources),
      cachedRecord: (identity) =>
          store.read<ContactRecord?>((tx) async => tx.contact(identity)),
      readOnly: config['requestedReadOnly'] == true,
      disposeTransport: httpClient.close,
    );
  }

  CardDavContactsProvider? cardDavProvider(String accountId) =>
      _carddav[accountId];
  Future<List<ContactGroup>> googleGroups(String id) async {
    final account = await store.read((tx) async => tx.account(id));
    final oauth = _google[id];
    if (account == null || oauth == null) return [];
    // Reading actual provider concepts; mutations still go through the directory.
    final provider = GoogleContactsProvider(
      accountId: id,
      authorizedClient: _GoogleAuthorizedClient(
        oauth,
        account.subject,
        httpClient: httpClientFactory?.call(),
      ),
      grantedScopes: account.grantedScopes,
    );
    try {
      return await provider.groups(ContactsCancellationToken());
    } finally {
      provider.close();
    }
  }

  Future<void> disable(String id) async {
    await _drain(id);
  }

  Future<void> enable(String id) async {
    final account = await store.read((tx) async => tx.account(id));
    if (account == null) return;
    final enabled = account.copy(
      enabled: true,
      generation: account.generation + 1,
    );
    await store.write((tx) async => tx.putAccount(enabled));
    await _bind(enabled);
    await synchronizeAccount(id);
  }

  Future<void> remove(String id) async {
    final account = await store.read((tx) async => tx.account(id));
    final config = await secrets.read('connection/' + id);
    await _drain(id);
    // Remove only BusyCards-owned credentials; no provider-wide consent revocation.
    if (account?.provider == ContactProviderKind.google && config != null) {
      final registration = CardsRegistration.fromJson(
        (jsonDecode(config)['registration'] as Map).cast(),
      );
      final oauth = GoogleOAuthService(
        configuration: registration.google,
        secrets: _googleSecrets(id),
        profileId: profile.path + '/' + id,
      );
      try {
        await oauth.removeCredentials(account!.subject);
      } finally {
        await oauth.close();
      }
    }
    if (account?.provider == ContactProviderKind.microsoft && config != null) {
      final registration = CardsRegistration.fromJson(
        (jsonDecode(config)['registration'] as Map).cast(),
      );
      final helper = _bridge(registration.microsoftClientId, false, id);
      try {
        await helper.removeAccount(account!.subject);
      } finally {
        await helper.close();
      }
    }
    await secrets.delete('connection/' + id);
    if (await secrets.read('connection/' + id) != null)
      throw StateError('Credential removal failed; reconnect or retry');
    await store.write((tx) async => tx.removeAccount(id));
  }

  Future<void> _drain(String id) async {
    _epochs[id] = (_epochs[id] ?? 0) + 1;
    await directory.disconnect(id);
    await _google.remove(id)?.close();
    await _microsoft.remove(id)?.close();
    _carddav.remove(id);
  }

  Future<List<CardsItemResult>> deleteMany(List<ContactRecord> records) async {
    final results = <CardsItemResult>[];
    for (final record in records) {
      try {
        results.add(
          CardsItemResult(
            record.projection.displayName,
            mutation: await directory.delete(record),
          ),
        );
      } catch (error) {
        results.add(
          CardsItemResult(
            record.projection.displayName,
            error: safeError(error),
          ),
        );
      }
    }
    return results;
  }

  Future<List<VCardImportItem>> previewImport(Uint8List bytes) =>
      Isolate.run(() => importVcards(Stream.value(bytes)));
  Future<List<CardsItemResult>> importCards(
    List<VCardDocument> cards,
    ContactSource destination, {
    bool allowLoss = false,
  }) async {
    final results = <CardsItemResult>[];
    for (final card in cards) {
      final previewIdentity = ContactIdentity(
        accountId: destination.accountId,
        provider: destination.provider,
        sourceId: destination.id,
        remoteId: 'import',
      );
      final projection = projectVcard(previewIdentity, card);
      final warnings = importConversionWarnings(card, destination);
      if (warnings.isNotEmpty && !allowLoss) {
        results.add(
          CardsItemResult(
            projection.displayName,
            error: 'conversion-review-required',
          ),
        );
        continue;
      }
      try {
        final patch = destination.provider == ContactProviderKind.carddav
            ? const ContactPatch()
            : _convertedPatch(projection, destination);
        final mutation = await directory.create(
          destination.key,
          patch,
          fullVcard: destination.provider == ContactProviderKind.carddav
              ? card.serialize()
              : null,
        );
        results.add(
          CardsItemResult(projection.displayName, mutation: mutation),
        );
        if (mutation.result != null &&
            projection.photo?.embedded != null &&
            destination.capabilities.photoWrite &&
            destination.provider != ContactProviderKind.carddav) {
          final bytes = projection.photo!.embedded!;
          final mediaType =
              projection.photo!.mediaType ??
              (bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80
                  ? 'image/png'
                  : 'image/jpeg');
          final photo = await directory.setPhoto(
            mutation.result!,
            bytes,
            mediaType,
          );
          results.add(
            CardsItemResult(projection.displayName + ' photo', mutation: photo),
          );
        }
      } catch (error) {
        results.add(
          CardsItemResult(projection.displayName, error: safeError(error)),
        );
      }
    }
    return results;
  }

  ContactPatch _convertedPatch(ContactProjection p, ContactSource source) {
    if (source.provider == ContactProviderKind.google) {
      // Explicit conversion preview already reports repeated birthdays.
      return ContactPatch(
        name: FieldEdit.set(p.name),
        emails: FieldEdit.set(p.emails),
        phones: FieldEdit.set(p.phones),
        organization: FieldEdit.set(p.organization),
        addresses: FieldEdit.set(p.addresses),
        dates: FieldEdit.set(
          p.dates
              .where((d) => d.label != 'birthday')
              .followedBy(p.dates.where((d) => d.label == 'birthday').take(1))
              .toList(),
        ),
        urls: FieldEdit.set(p.urls),
        notes: FieldEdit.set(p.notes),
      );
    }
    String phoneType(ContactValue value) =>
        const {'home', 'work', 'mobile'}.contains(value.label.toLowerCase())
        ? value.label.toLowerCase()
        : value.types
                  .map(
                    (t) =>
                        t.toLowerCase() == 'cell' ? 'mobile' : t.toLowerCase(),
                  )
                  .where((t) => const {'home', 'work', 'mobile'}.contains(t))
                  .firstOrNull ??
              '';
    var mobileSeen = false;
    final phones = <ContactValue>[];
    for (final value in p.phones) {
      final type = phoneType(value);
      if (type.isEmpty || type == 'mobile' && mobileSeen) continue;
      if (type == 'mobile') mobileSeen = true;
      phones.add(ContactValue(value.value, label: type, types: [type]));
    }
    final addressTypes = <String>{}, addresses = <ContactAddress>[];
    for (final address in p.addresses) {
      final type = address.label.toLowerCase();
      if (!const {'home', 'work', 'other'}.contains(type) ||
          !addressTypes.add(type))
        continue;
      addresses.add(
        ContactAddress(
          street: address.street,
          city: address.city,
          region: address.region,
          postcode: address.postcode,
          country: address.country,
          label: type,
        ),
      );
    }
    return ContactPatch(
      name: FieldEdit.set(p.name),
      emails: FieldEdit.set(p.emails.take(3).toList()),
      phones: FieldEdit.set(phones),
      organization: FieldEdit.set(p.organization),
      addresses: FieldEdit.set(addresses),
      dates: FieldEdit.set(
        p.dates
            .where((v) => v.label == 'birthday' && v.year != null)
            .take(1)
            .toList(),
      ),
      urls: FieldEdit.set(p.urls.take(1).toList()),
      notes: FieldEdit.set(p.notes),
      labels: FieldEdit.set(p.labels),
    );
  }

  Future<Uint8List> exportCards(List<ContactRecord> records) => Isolate.run(() {
    final buffer = StringBuffer();
    for (final record in records) {
      buffer.write(exportContactVcard(record));
      if (buffer.length > 32 * 1024 * 1024)
        throw const ContactsException(
          ContactsFailure.validation,
          'export-limit-select-fewer-contacts',
        );
    }
    final bytes = utf8.encode(buffer.toString());
    if (bytes.length > 32 * 1024 * 1024)
      throw const ContactsException(
        ContactsFailure.validation,
        'export-limit-select-fewer-contacts',
      );
    return Uint8List.fromList(bytes);
  });
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final closing = Zone.root.run(_close);
    _closeFuture = closing;
    return closing;
  }

  Future<void> _close() async {
    _closed = true;
    _timer?.cancel();
    await cancelAuthorization();
    await directory.close();
    for (final oauth in _google.values) {
      await oauth.close();
    }
    for (final helper in _microsoft.values) {
      await helper.close();
    }
    await store.close();
  }

  static String safeError(Object error) => switch (error) {
    ContactsException() => error.code,
    GoogleOAuthException() => error.code,
    MicrosoftAuthException() => error.code,
    _ => 'operation-failed-retry-or-check-connection',
  };
}

final class _GoogleAuthorizedClient extends http.BaseClient {
  _GoogleAuthorizedClient(this.oauth, this.subject, {http.Client? httpClient})
    : _client = httpClient ?? http.Client();
  final GoogleOAuthService oauth;
  final String subject;
  final http.Client _client;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final credentials = await oauth.validCredentials(subject);
    request.headers['authorization'] = 'Bearer ' + credentials.accessToken.data;
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}
