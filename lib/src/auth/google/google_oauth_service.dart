import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/logging/redacting_logger.dart';
import '../../storage/secret_value_store.dart';

final _log = RedactingLogger(Logger('GoogleOAuthService'));

class _CredentialAuthority {
  const _CredentialAuthority(this.profile, this.registration, this.subjects);
  final int profile;
  final int registration;
  final Map<String, int> subjects;
}

class GoogleOAuthConfiguration {
  const GoogleOAuthConfiguration({
    required this.clientId,
    this.clientSecret = '',
  });

  final String clientId;
  final String clientSecret;

  bool get isConfigured =>
      clientId.trim().isNotEmpty && clientSecret.trim().isNotEmpty;

  String get registrationId => sha256
      .convert(utf8.encode('busycards/google:' + clientId + ':' + clientSecret))
      .toString();

  ClientId get oauthClient => ClientId(clientId, clientSecret);
}

class GoogleIdentity {
  const GoogleIdentity({required this.subject, required this.credentials});

  final String subject;
  final AccessCredentials credentials;
}

class GoogleOAuthService {
  GoogleOAuthService({
    required this.configuration,
    this.requestedScopes = scopes,
    this.profileId = 'default',
    http.Client? httpClient,
    SecretValueStore? secrets,
    Future<bool> Function(Uri uri)? browserLauncher,
    JsonWebKeyStore? idTokenKeyStore,
  }) : _client = httpClient ?? http.Client(),
       _secrets = secrets ?? SecretServiceValueStore(),
       _browserLauncher = browserLauncher ?? _launchBrowser,
       _idTokenKeyStore = idTokenKeyStore {
    final allowed = {
      ...scopes,
      'https://www.googleapis.com/auth/contacts.readonly',
    };
    if (requestedScopes.toSet().difference(allowed).isNotEmpty ||
        !requestedScopes.contains('openid') ||
        !requestedScopes.any(
          (scope) =>
              scope.startsWith('https://www.googleapis.com/auth/contacts'),
        )) {
      throw const GoogleOAuthException('invalid-scope');
    }
  }

  static const scopes = <String>[
    'openid',
    'email',
    'profile',
    'https://www.googleapis.com/auth/contacts',
  ];

  /// Preserve known token-endpoint classifications without exposing response
  /// descriptions, which may include credentials or account information.
  static String? configurationFailureCode(Object error) {
    if (error is! ServerRequestFailedException) return null;
    final code = _oauthErrorCode(error);
    const known = {
      'invalid_client',
      'unauthorized_client',
      'invalid_grant',
      'invalid_scope',
      'invalid_request',
      'access_denied',
      'temporarily_unavailable',
      'server_error',
    };
    return known.contains(code)
        ? 'provider-${code!.replaceAll('_', '-')}'
        : null;
  }

  static const _authorizationEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const _jwkEndpoint = 'https://www.googleapis.com/oauth2/v3/certs';
  static const _callbackPath = '/oauth2/callback';
  static const _subjectIndexKey = 'google-oauth-credential-index-v2';

  // Every account and service instance mutates the same Secret Service index.
  static Future<void> _credentialMutationTail = Future<void>.value();
  // All live services address the same profile keyring namespace. Authority
  // is shared with reset/cleanup services, including newly constructed ones.
  static final Map<String, int> _profileGenerations = {};
  int get _profileGeneration => _profileGenerations[profileId] ?? 0;
  String get _registrationKey => profileId + '/' + configuration.registrationId;
  String _subjectKey(String subject) =>
      profileId + '/' + _credentialKey(subject);
  static final Map<String, int> _registrationGenerations = {};
  static final Map<String, int> _subjectGenerations = {};

  _CredentialAuthority _authority() => _CredentialAuthority(
    _profileGeneration,
    _registrationGenerations[_registrationKey] ?? 0,
    Map.of(_subjectGenerations),
  );

  void _checkAuthority(_CredentialAuthority authority, [String? subject]) {
    if (_closed) throw const GoogleOAuthException('oauth-service-closed');
    if (authority.profile != _profileGeneration ||
        authority.registration !=
            (_registrationGenerations[_registrationKey] ?? 0) ||
        (subject != null &&
            (authority.subjects[_subjectKey(subject)] ?? 0) !=
                (_subjectGenerations[_subjectKey(subject)] ?? 0))) {
      throw const GoogleOAuthException('credential-operation-cancelled');
    }
  }

  Future<T> _mutateCredentials<T>(Future<T> Function() action) {
    final result = _credentialMutationTail.then((_) => action());
    _credentialMutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  final GoogleOAuthConfiguration configuration;
  final List<String> requestedScopes;
  final String profileId;
  final _refreshes = <String, Future<AccessCredentials>>{};
  final http.Client _client;
  final SecretValueStore _secrets;
  final Future<bool> Function(Uri uri) _browserLauncher;
  final JsonWebKeyStore? _idTokenKeyStore;
  final Set<HttpServer> _activeServers = {};
  bool _closed = false;

  Future<GoogleIdentity> authorize({
    required String successPage,
    required String failurePage,
    bool forceConsent = false,
    bool persistCredentials = true,
    String? expectedSubject,
  }) async {
    final authority = _authority();
    _checkAuthority(authority, expectedSubject);
    try {
      return await _authorize(
        authority: authority,
        successPage: successPage,
        failurePage: failurePage,
        forceConsent: forceConsent,
        persistCredentials: persistCredentials,
        expectedSubject: expectedSubject,
      );
    } on _GoogleConsentRequired catch (error) {
      _checkAuthority(authority, error.subject);
      if (forceConsent) rethrow;
      return _authorize(
        authority: authority,
        successPage: successPage,
        failurePage: failurePage,
        forceConsent: true,
        persistCredentials: persistCredentials,
        expectedSubject: error.subject,
      );
    }
  }

  Future<GoogleIdentity> _authorize({
    required _CredentialAuthority authority,
    required String successPage,
    required String failurePage,
    required bool forceConsent,
    required bool persistCredentials,
    String? expectedSubject,
  }) async {
    if (_closed) {
      throw const GoogleOAuthException('oauth-service-closed');
    }
    if (!configuration.isConfigured) {
      throw StateError('Google OAuth client configuration is incomplete');
    }
    _log.info('google-oauth-authorization-started');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed) {
      await server.close(force: true);
      throw const GoogleOAuthException('oauth-service-closed');
    }
    _activeServers.add(server);
    final redirect = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: _callbackPath,
    );
    final state = _randomToken(32);
    final nonce = _randomToken(32);
    final verifier = _codeVerifier();
    final challenge = base64UrlEncode(
      sha256.convert(ascii.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final authorization = Uri.parse(_authorizationEndpoint).replace(
      queryParameters: {
        'client_id': configuration.clientId,
        'redirect_uri': redirect.toString(),
        'response_type': 'code',
        'scope': requestedScopes.join(' '),
        'access_type': 'offline',
        'prompt': forceConsent ? 'select_account consent' : 'select_account',
        'state': state,
        'nonce': nonce,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      },
    );
    try {
      final browserLaunched = await _browserLauncher(authorization);
      if (!browserLaunched) {
        throw const GoogleOAuthException('browser-launch-failed');
      }
      _log.info('google-oauth-browser-launched');
      final request = await _waitForCallback(server)
          .timeout(const Duration(minutes: 5));
      _log.info('google-oauth-callback-received');
      try {
        final callback = request.uri;
        if (!_constantTimeEquals(callback.queryParameters['state'], state)) {
          throw const GoogleOAuthException('state-mismatch');
        }
        final providerError = callback.queryParameters['error'];
        if (providerError != null) {
          const knownErrors = {
            'access_denied',
            'invalid_client',
            'unauthorized_client',
            'invalid_scope',
            'org_internal',
            'admin_policy_enforced',
            'disallowed_useragent',
          };
          throw GoogleOAuthException(
            knownErrors.contains(providerError)
                ? 'provider-${providerError.replaceAll('_', '-')}'
                : 'provider-authorization-denied',
          );
        }
        final code = callback.queryParameters['code'];
        if (code == null || code.isEmpty) {
          throw const GoogleOAuthException('missing-code');
        }
        final credentials = await obtainAccessCredentialsViaCodeExchange(
          _client,
          configuration.oauthClient,
          code,
          redirectUrl: redirect.toString(),
          codeVerifier: verifier,
        );
        final idToken = credentials.idToken;
        if (idToken == null) {
          throw const GoogleOAuthException('missing-id-token');
        }
        final subject = await _validateIdToken(idToken, nonce);
        _checkAuthority(authority, subject);
        if (expectedSubject != null && subject != expectedSubject) {
          throw const GoogleOAuthException('wrong-account');
        }
        final contactsScope =
            requestedScopes.contains('https://www.googleapis.com/auth/contacts')
            ? 'https://www.googleapis.com/auth/contacts'
            : 'https://www.googleapis.com/auth/contacts.readonly';
        if (!credentials.scopes.contains(contactsScope) &&
            !(contactsScope.endsWith('.readonly') &&
                credentials.scopes.contains(
                  'https://www.googleapis.com/auth/contacts',
                ))) {
          throw const GoogleOAuthException('contacts-permission-not-granted');
        }
        final retained = await _retainRefreshToken(subject, credentials);
        _checkAuthority(authority, subject);
        if (retained.refreshToken == null || retained.refreshToken!.isEmpty) {
          throw _GoogleConsentRequired(subject);
        }
        if (persistCredentials)
          await _writeCredentials(subject, retained, authority);
        await _respondToCallback(request, successPage, successful: true);
        _log.info('google-oauth-authorization-completed');
        _checkAuthority(authority, subject);
        return GoogleIdentity(subject: subject, credentials: retained);
      } on Object catch (error, stackTrace) {
        await _respondToCallback(
          request,
          failurePage,
          successful: false,
        ).catchError((_) {});
        Error.throwWithStackTrace(error, stackTrace);
      }
    } on Object catch (error) {
      _log.warning(
        'google-oauth-authorization-failed '
        'classification=${_safeFailureClassification(error)}',
      );
      rethrow;
    } finally {
      _activeServers.remove(server);
      await server.close(force: true);
    }
  }

  Future<AccessCredentials?> readCredentials(String subject) async {
    final authority = _authority();
    _checkAuthority(authority, subject);
    final value = await _secrets.read(_credentialKey(subject));
    _checkAuthority(authority, subject);
    if (value == null) return null;
    try {
      final stored = (jsonDecode(value) as Map).cast<String, dynamic>();
      if (stored['client_id'] != configuration.clientId ||
          stored['registration_id'] != configuration.registrationId) {
        throw const GoogleOAuthException('credential-registration-mismatch');
      }
      return AccessCredentials.fromJson(stored);
    } on GoogleOAuthException {
      rethrow;
    } on Object {
      throw const GoogleOAuthException('credential-record-invalid');
    }
  }

  /// Enrollment can stage authorization until the app has validated its
  /// identity, permissions and account metadata. The same atomic writer is used
  /// for enrollment, refresh and rollback; credential storage stays app owned.
  Future<void> commitIdentity(GoogleIdentity identity) =>
      _writeCredentials(identity.subject, identity.credentials, _authority());

  Future<AccessCredentials> validCredentials(String subject) =>
      _refreshes.putIfAbsent(
        subject,
        () => _validCredentials(subject).whenComplete(() {
          _refreshes.remove(subject);
        }),
      );
  Future<AccessCredentials> _validCredentials(String subject) async {
    final authority = _authority();
    if (_closed) {
      throw const GoogleOAuthException('oauth-service-closed');
    }
    if (!configuration.isConfigured) {
      throw const GoogleOAuthException('registration-missing');
    }
    final stored = await readCredentials(subject);
    _checkAuthority(authority, subject);
    if (stored == null) {
      throw const GoogleOAuthException('credentials-missing');
    }
    if (!stored.accessToken.hasExpired) return stored;
    if (stored.refreshToken == null) {
      throw const GoogleOAuthException('refresh-token-missing');
    }
    late final AccessCredentials refreshed;
    try {
      refreshed = await refreshCredentials(
        configuration.oauthClient,
        stored,
        _client,
      );
    } on ServerRequestFailedException catch (error) {
      if (_oauthErrorCode(error) == 'invalid_grant') {
        throw const GoogleOAuthException('refresh-token-rejected');
      }
      rethrow;
    }
    await _writeCredentials(subject, refreshed, authority);
    _checkAuthority(authority, subject);
    return refreshed;
  }

  Future<void> close() async {
    if (_closed && _activeServers.isEmpty) return;
    _closed = true;
    // The OAuth transport owns refresh/code-exchange waits, independently of
    // every mail adapter. Signal it before awaiting listener/index cleanup.
    _client.close();
    final servers = _activeServers.toList(growable: false);
    _activeServers.clear();
    await Future.wait([
      for (final server in servers) server.close(force: true),
    ]);
    await _credentialMutationTail;
  }

  Future<void> removeCredentials(String subject) {
    final key = _subjectKey(subject);
    _subjectGenerations[key] = (_subjectGenerations[key] ?? 0) + 1;
    return _mutateCredentials(() async {
      await _secrets.delete(_credentialKey(subject));
      if (await _secrets.read(_credentialKey(subject)) != null) {
        throw const GoogleOAuthException('credential-delete-failed');
      }
      final subjects = await _credentialSubjects()
        ..remove(_credentialKey(subject));
      await _writeCredentialSubjects(subjects);
    });
  }

  Future<void> deleteRegistrationCredentials() {
    final id = _registrationKey;
    _registrationGenerations[id] = (_registrationGenerations[id] ?? 0) + 1;
    return _mutateCredentials(() async {
      final keys = await _credentialSubjects();
      for (final key
          in keys
              .where(
                (key) => key.startsWith(
                  'google-oauth-v2-${configuration.registrationId}-',
                ),
              )
              .toList()) {
        await _secrets.delete(key);
        if (await _secrets.read(key) != null) {
          throw const GoogleOAuthException('credential-delete-failed');
        }
        keys.remove(key);
      }
      await _writeCredentialSubjects(keys);
    });
  }

  /// Deletes every Google credential owned by this BusyCards profile.
  ///
  /// The index is itself stored in Secret Service, so explicit profile reset
  /// remains possible even when the encrypted mailbox key is missing.
  Future<void> deleteAllCredentials() {
    _profileGenerations[profileId] = _profileGeneration + 1;
    return _mutateCredentials(() async {
      final subjects = await _credentialSubjects();
      for (final subject in subjects) {
        await _secrets.delete(subject);
        if (await _secrets.read(subject) != null) {
          throw const GoogleOAuthException('credential-delete-failed');
        }
      }
      await _secrets.delete(_subjectIndexKey);
      if (await _secrets.read(_subjectIndexKey) != null) {
        throw const GoogleOAuthException('credential-index-delete-failed');
      }
      final legacy = await _secrets.read('google-oauth-subject-index-v1');
      if (legacy != null) {
        final legacySubjects = (jsonDecode(legacy) as List).cast<String>();
        for (final subject in legacySubjects) {
          final key = 'google-oauth-v1-$subject';
          await _secrets.delete(key);
          if (await _secrets.read(key) != null) {
            throw const GoogleOAuthException('credential-delete-failed');
          }
        }
        await _secrets.delete('google-oauth-subject-index-v1');
        if (await _secrets.read('google-oauth-subject-index-v1') != null) {
          throw const GoogleOAuthException('credential-index-delete-failed');
        }
      }
    });
  }

  Future<void> revoke(String subject) async {
    final key = _subjectKey(subject);
    _subjectGenerations[key] = (_subjectGenerations[key] ?? 0) + 1;
    final credentials = await readCredentials(subject);
    final token = credentials?.refreshToken ?? credentials?.accessToken.data;
    if (token == null || token.isEmpty) {
      await removeCredentials(subject);
      return;
    }
    final response = await _client.post(
      Uri.parse('https://oauth2.googleapis.com/revoke'),
      headers: {
        HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
      },
      body: {'token': token},
    );
    if (response.statusCode != HttpStatus.ok) {
      throw const GoogleOAuthException('revocation-failed');
    }
    await removeCredentials(subject);
  }

  Future<HttpRequest> _waitForCallback(HttpServer server) async {
    await for (final request in server) {
      if (request.method != 'GET' || request.uri.path != _callbackPath) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      return request;
    }
    throw const GoogleOAuthException('callback-server-closed');
  }

  Future<void> _respondToCallback(
    HttpRequest request,
    String message, {
    required bool successful,
  }) async {
    request.response
      ..statusCode = successful ? HttpStatus.ok : HttpStatus.badRequest
      ..headers.contentType = ContentType.html
      ..write(_callbackPage(message));
    await request.response.close();
  }

  Future<String> _validateIdToken(String serialized, String nonce) async {
    final unverified = JsonWebToken.unverified(serialized);
    final issuer = unverified.claims.issuer;
    if (issuer != Uri.parse('https://accounts.google.com') &&
        issuer != Uri.parse('accounts.google.com')) {
      throw const GoogleOAuthException('invalid-issuer');
    }
    final keys =
        _idTokenKeyStore ??
        (JsonWebKeyStore()..addKeySetUrl(Uri.parse(_jwkEndpoint)));
    final token = await JsonWebToken.decodeAndVerify(
      serialized,
      keys,
      allowedArguments: const ['RS256'],
    );
    final violations = token.claims.validate(
      issuer: issuer,
      clientId: configuration.clientId,
      expiryTolerance: const Duration(minutes: 2),
    );
    if (violations.isNotEmpty) {
      throw const GoogleOAuthException('invalid-id-token-claims');
    }
    if (!_constantTimeEquals(token.claims['nonce'] as String?, nonce)) {
      throw const GoogleOAuthException('nonce-mismatch');
    }
    final subject = token.claims.subject;
    if (subject == null || subject.isEmpty) {
      throw const GoogleOAuthException('missing-subject');
    }
    return subject;
  }

  Future<AccessCredentials> _retainRefreshToken(
    String subject,
    AccessCredentials credentials,
  ) async {
    if (credentials.refreshToken?.isNotEmpty == true) return credentials;
    final encoded = await _secrets.read(_credentialKey(subject));
    if (encoded == null) return credentials;
    final stored = (jsonDecode(encoded) as Map).cast<String, dynamic>();
    final previous = AccessCredentials.fromJson(stored);
    final sameClient =
        stored['client_id'] == configuration.clientId &&
        stored['registration_id'] == configuration.registrationId;
    if (!sameClient || previous.refreshToken?.isNotEmpty != true) {
      return credentials;
    }
    return AccessCredentials(
      credentials.accessToken,
      previous.refreshToken,
      credentials.scopes,
      idToken: credentials.idToken,
    );
  }

  Future<void> _writeCredentials(
    String subject,
    AccessCredentials credentials,
    _CredentialAuthority authority,
  ) => _mutateCredentials(() async {
    _checkAuthority(authority, subject);
    final key = _credentialKey(subject);
    final previous = await _secrets.read(key);
    final previousSubjects = await _credentialSubjects();
    _checkAuthority(authority, subject);
    final encoded = jsonEncode({
      ...credentials.toJson(),
      'client_id': configuration.clientId,
      'registration_id': configuration.registrationId,
    });
    Future<void> rollback() async {
      if (previous == null) {
        await _secrets.delete(key);
      } else {
        await _secrets.write(key, previous);
      }
      if (await _secrets.read(key) != previous) {
        throw const GoogleOAuthException('credential-rollback-failed');
      }
    }

    try {
      await _secrets.write(key, encoded);
      if (await _secrets.read(key) != encoded) {
        throw const GoogleOAuthException('credential-persistence-failed');
      }
      final subjects = {...previousSubjects, key};
      await _writeCredentialSubjects(subjects);
      _checkAuthority(authority, subject);
    } on Object catch (error, stackTrace) {
      // An unindexed credential could survive a database-key loss and evade
      // explicit reset. Roll it back rather than accepting that state.
      await rollback();
      await _writeCredentialSubjects(previousSubjects);
      Error.throwWithStackTrace(error, stackTrace);
    }
  });

  Future<Set<String>> _credentialSubjects() async {
    final encoded = await _secrets.read(_subjectIndexKey);
    if (encoded == null) return <String>{};
    try {
      final values = jsonDecode(encoded);
      if (values is! List ||
          values.any(
            (value) =>
                value is! String ||
                !RegExp(r'^google-oauth-v2-[0-9a-f]{64}-.{1,256}$')
                    .hasMatch(value),
          )) {
        throw const FormatException();
      }
      return values.cast<String>().toSet();
    } on Object {
      throw const GoogleOAuthException('credential-index-malformed');
    }
  }

  Future<void> _writeCredentialSubjects(Set<String> subjects) async {
    final previous = await _secrets.read(_subjectIndexKey);
    final encoded = subjects.isEmpty
        ? null
        : jsonEncode(subjects.toList()..sort());
    try {
      if (encoded == null) {
        await _secrets.delete(_subjectIndexKey);
      } else {
        await _secrets.write(_subjectIndexKey, encoded);
      }
      if (await _secrets.read(_subjectIndexKey) != encoded) {
        throw const GoogleOAuthException('credential-index-persistence-failed');
      }
    } on Object catch (error, stack) {
      if (previous == null) {
        await _secrets.delete(_subjectIndexKey);
      } else {
        await _secrets.write(_subjectIndexKey, previous);
      }
      if (await _secrets.read(_subjectIndexKey) != previous) {
        throw const GoogleOAuthException('credential-index-rollback-failed');
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  String _credentialKey(String subject) =>
      'google-oauth-v2-${configuration.registrationId}-$subject';
}

class _GoogleConsentRequired extends GoogleOAuthException {
  const _GoogleConsentRequired(this.subject) : super('refresh-token-missing');
  final String subject;
}

String _safeFailureClassification(Object error) {
  if (error is! GoogleOAuthException) return error.runtimeType.toString();
  final code = error.code;
  if (RegExp(r'^[a-z0-9-]{1,64}$').hasMatch(code)) return code;
  return 'google-oauth-error';
}

String? _oauthErrorCode(ServerRequestFailedException error) {
  final response = error.responseContent;
  if (response is! Map) return null;
  final code = response['error'];
  return code is String ? code : null;
}

class GoogleOAuthException implements Exception {
  const GoogleOAuthException(this.code);

  final String code;

  bool get requiresUserAuthorization => const {
    'credentials-missing',
    'refresh-token-missing',
    'refresh-token-rejected',
    'credential-registration-mismatch',
    'credential-record-invalid',
  }.contains(code);

  @override
  String toString() => 'GoogleOAuthException($code)';
}

Future<bool> _launchBrowser(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _callbackPage(String message) {
  final escaped = const HtmlEscape().convert(message);
  return '<!doctype html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width">'
      '<title>BusyCards</title></head><body><main><h1>BusyCards</h1>'
      '<p>$escaped</p></main></body></html>';
}

String _randomToken(int byteLength) {
  final random = Random.secure();
  return base64UrlEncode(
    List<int>.generate(byteLength, (_) => random.nextInt(256)),
  ).replaceAll('=', '');
}

String _codeVerifier() {
  final random = Random.secure();
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  return List.generate(
    96,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

bool _constantTimeEquals(String? left, String right) {
  if (left == null) return false;
  final leftBytes = Uint8List.fromList(utf8.encode(left));
  final rightBytes = Uint8List.fromList(utf8.encode(right));
  var difference = leftBytes.length ^ rightBytes.length;
  final length = max(leftBytes.length, rightBytes.length);
  for (var index = 0; index < length; index++) {
    final leftByte = index < leftBytes.length ? leftBytes[index] : 0;
    final rightByte = index < rightBytes.length ? rightBytes[index] : 0;
    difference |= leftByte ^ rightByte;
  }
  return difference == 0;
}
