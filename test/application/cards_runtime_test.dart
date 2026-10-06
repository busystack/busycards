import 'dart:convert';
import 'dart:io';

import 'package:busycards/src/application/cards_runtime.dart';
import 'package:busycards/src/storage/contacts_database.dart';
import 'package:busycards/src/storage/database_key_store.dart';
import 'package:busycards/src/storage/secret_value_store.dart';
import 'package:busystack_contacts/busystack_contacts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/carddav_http_fixture.dart';

class FixtureSecrets implements SecretValueStore {
  final values = <String, String>{};
  String? rejectKey;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (key == rejectKey) throw StateError('Synthetic persistence failure');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  late Directory profile;
  late ContactsDatabase store;
  late CardsRuntime runtime;
  late FixtureSecrets secrets;
  late DavFixture fixture;
  final key = List.generate(32, (index) => index + 1);
  setUp(() async {
    profile = await Directory.systemTemp.createTemp(
      'busycards-runtime-fixture-',
    );
    secrets = FixtureSecrets();
    fixture = DavFixture();
    store = await ContactsDatabase.open(
      File(profile.path + '/contacts.sqlite3'),
      key,
    );
    runtime = CardsRuntime(
      store: store,
      secrets: secrets,
      profile: profile,
      httpClientFactory: () => fixture.httpClient,
    );
    await runtime.start(schedule: false);
  });
  tearDown(() async {
    await runtime.close();
    await profile.delete(recursive: true);
  });
  Future<ContactAccount> connect() => runtime.connectCardDav(
    label: 'Fixture cloud',
    server: server,
    username: 'actual-user',
    password: 'synthetic-app-password',
    nextcloud: true,
  );
  test('production setup discovers real concepts and cached search survives disabling and restart', () async {
    final account = await connect();
    await Future.wait([
      runtime.synchronizeAccount(account.id),
      runtime.synchronizeAccount(account.id),
    ]).timeout(const Duration(seconds: 5));
    expect(runtime.isSyncing(account.id), isFalse);
    expect((await runtime.directory.browse('Zoë')).length, 2);
    expect(await runtime.directory.browse('missing'), isEmpty);
    await runtime.disable(account.id);
    expect(
      (await store.read((tx) => tx.account(account.id)))!.enabled,
      isFalse,
    );
    final contacts = await store.read((tx) => tx.contacts());
    final source = await store.read(
      (tx) => tx.source(
        jsonEncode([
          contacts.first.identity.accountId,
          contacts.first.identity.provider.name,
          contacts.first.identity.sourceId,
        ]),
      ),
    );
    await expectLater(
      runtime.directory.update(
        contacts.first,
        const ContactPatch(notes: FieldEdit.clear()),
      ),
      throwsA(isA<ContactsException>()),
    );
    expect(source, isNotNull);
    await runtime.close();
    store = await ContactsDatabase.open(
      File(profile.path + '/contacts.sqlite3'),
      key,
    );
    runtime = CardsRuntime(
      store: store,
      secrets: secrets,
      profile: profile,
      httpClientFactory: () => fixture.httpClient,
    );
    await runtime.start(schedule: false);
    expect(await runtime.directory.browse('李'), hasLength(2));
  });
  test('confirmed edits, explicit clears and saved drafts retain full native source after restart', () async {
    final account = await connect();
    await runtime.synchronizeAccount(account.id);
    final base = await store.read(
      (tx) => tx.contacts().firstWhere(
        (r) => r.identity.sourceId.endsWith('/book/'),
      ),
    );
    final change = await runtime.directory.update(
      base,
      const ContactPatch(notes: FieldEdit.clear()),
    );
    expect(change.state, ContactMutationState.confirmed);
    expect(
      (change.result as CardDavContactRecord).vcard.text('X-FUTURE'),
      'keep',
    );
    await runtime.directory.saveDraft(
      ContactDraft(
        id: 'draft',
        sourceKey: change.sourceKey,
        identity: base.identity,
        patch: const ContactPatch(
          name: FieldEdit.set(ContactName(given: 'Unsaved')),
        ),
      ),
    );
    await runtime.close();
    store = await ContactsDatabase.open(
      File(profile.path + '/contacts.sqlite3'),
      key,
    );
    runtime = CardsRuntime(
      store: store,
      secrets: secrets,
      profile: profile,
      httpClientFactory: () => fixture.httpClient,
    );
    await runtime.start(schedule: false);
    expect(
      (await store.read((tx) => tx.contact(base.identity)))!.projection.notes,
      '',
    );
    expect(
      (await store.read((tx) => tx.drafts())).single.patch.name.value!.given,
      'Unsaved',
    );
  });
  test(
    'removal deletes only the chosen account and its protected connection',
    () async {
      final first = await connect(), second = await connect();
      await runtime.synchronizeAccount(first.id);
      await runtime.synchronizeAccount(second.id);
      await runtime.remove(first.id);
      expect(await store.read((tx) => tx.account(first.id)), isNull);
      expect(await store.read((tx) => tx.account(second.id)), isNotNull);
      expect(secrets.values.containsKey('connection/' + first.id), isFalse);
      expect(secrets.values.containsKey('connection/' + second.id), isTrue);
      expect(await runtime.directory.browse('Zoë'), hasLength(2));
    },
  );
  test('import preview and conversion consent are enforced through the app use case', () async {
    final account = await connect();
    await runtime.synchronizeAccount(account.id);
    final destination = (await store.read(
      (tx) => tx.sources(accountId: account.id),
    )).firstWhere((s) => s.capabilities.create);
    final items = await runtime.previewImport(
      utf8.encode(rawCard + 'BEGIN:VCARD\nVERSION:4.0\nEND:VCARD\n'),
    );
    expect(items.first.card, isNotNull);
    expect(items.last.error, isNotNull);
    final results = await runtime.importCards([items.first.card!], destination);
    expect(results.first.succeeded, isTrue);
    final export = await runtime.exportCards([results.first.mutation!.result!]);
    expect(utf8.decode(export), contains('X-FUTURE;X-PARAM=opaque:keep'));
  });
  test('conditional conflict and partial bulk failures remain actionable without overwrite', () async {
    final account = await connect();
    await runtime.synchronizeAccount(account.id);
    final contacts = await store.read((tx) => tx.contacts());
    fixture.conflict = true;
    final mutation = await runtime.directory.update(
      contacts.first,
      const ContactPatch(notes: FieldEdit.set('Local')),
    );
    expect(mutation.state, ContactMutationState.conflict);
    expect(mutation.base!.projection.notes, 'Original');
    final results = await runtime.deleteMany(contacts);
    expect(results.every((result) => result.succeeded), isFalse);
  });
  test('uncommitted enrollment journal rolls back rather than inventing remote or credential success', () async {
    await runtime.close();
    store = await ContactsDatabase.open(
      File(profile.path + '/contacts.sqlite3'),
      key,
    );
    const account = ContactAccount(
      id: 'interrupted',
      provider: ContactProviderKind.carddav,
      displayName: 'Interrupted',
      subject: 'fixture',
      grantedScopes: {},
    );
    await store.write((tx) => tx.putAccount(account));
    secrets.values['connection/interrupted'] = 'synthetic-protected-config';
    secrets.values['enrollments-v1'] = jsonEncode({
      'interrupted': {
        'oldConfig': null,
        'oldAccount': null,
        'newAccount': account.toJson(),
      },
    });
    runtime = CardsRuntime(
      store: store,
      secrets: secrets,
      profile: profile,
      httpClientFactory: () => fixture.httpClient,
    );
    await runtime.start(schedule: false);
    expect(await store.read((tx) => tx.accounts()), isEmpty);
    expect(secrets.values['connection/interrupted'], isNull);
  });
  test('database key and scoped credentials have independent profile/account ownership', () async {
    final newFile = File(profile.path + '/other.sqlite3');
    final protected = DatabaseKeyStore(secrets: secrets);
    final first = await protected.openForProfile(newFile);
    expect(first, hasLength(32));
    expect(await protected.openForProfile(newFile), first);
    final a = ScopedSecretValueStore(secrets, 'google/a/'),
        b = ScopedSecretValueStore(secrets, 'google/b/');
    await a.write('same-subject', 'A');
    await b.write('same-subject', 'B');
    await a.delete('same-subject');
    expect(await b.read('same-subject'), 'B');
  });
}
