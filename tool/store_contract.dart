import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:busystack_contacts/google.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:busycards/src/storage/contacts_database.dart';

int checks = 0;
void require(bool condition, String message) {
  if (!condition) throw StateError(message);
  checks++;
}

Future<void> main(List<String> arguments) async {
  final size = arguments.isEmpty ? 50000 : int.parse(arguments.first);
  if (size < 1 || size > 200000)
    throw ArgumentError('Fixture size must be bounded');
  final root = await Directory('validation/profiles').create(recursive: true);
  final profile = await root.createTemp('store-contract-');
  final file = File(profile.path + '/contacts.sqlite3');
  final key = List.generate(32, (i) => i + 1);
  var store = await ContactsDatabase.open(file, key);
  final source = GoogleContactsProvider(
    accountId: 'fixture',
    authorizedClient: MockClient((_) async => http.Response('{}', 200)),
    grantedScopes: {'https://www.googleapis.com/auth/contacts'},
  ).personalSource;
  const account = ContactAccount(
    id: 'fixture',
    provider: ContactProviderKind.google,
    displayName: 'Synthetic directory',
    subject: 'fixture-only',
    grantedScopes: {'https://www.googleapis.com/auth/contacts'},
  );
  await store.write((tx) {
    tx.putAccount(account);
    tx.putSource(source);
  });
  var pages = 0;
  final initialRss = ProcessInfo.currentRss;
  var peakRss = initialRss;
  final provider = GoogleContactsProvider(
    accountId: 'fixture',
    grantedScopes: account.grantedScopes,
    authorizedClient: MockClient((request) async {
      require(
        request.url.host == 'people.googleapis.com',
        'Fixture must use the generated People production endpoint',
      );
      final parameters = request.url.queryParameters;
      require(
        parameters['pageSize'] == '100',
        'Page size is stable and bounded',
      );
      final offset = int.parse(parameters['pageToken'] ?? '0'),
          end = (offset + 100).clamp(0, size);
      pages++;
      final people = [
        for (var i = offset; i < end; i++)
          {
            'resourceName': 'people/fixture-' + i.toString(),
            'metadata': {
              'sources': [
                {
                  'type': 'CONTACT',
                  'id': i.toString(),
                  'etag': 'revision-' + i.toString(),
                },
              ],
            },
            'names': [
              {
                'displayName':
                    'Contact ' + i.toString().padLeft(6, '0') + ' Zoë 李',
                'givenName': 'Zoë',
                'familyName': '李',
              },
            ],
            'emailAddresses': [
              {
                'value': 'person' + i.toString() + '@example.test',
                'type': 'work',
              },
            ],
            'nicknames': [
              {'value': 'Preserved ' + i.toString()},
            ],
          },
      ];
      return http.Response(
        jsonEncode({
          'connections': people,
          if (end < size)
            'nextPageToken': end.toString()
          else
            'nextSyncToken': 'fixture-complete',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  var directory = ContactsDirectory(store: store);
  directory.bind(provider);
  final watch = Stopwatch()..start();
  final sample = Timer.periodic(const Duration(milliseconds: 10), (_) {
    if (ProcessInfo.currentRss > peakRss) peakRss = ProcessInfo.currentRss;
  });
  await directory.synchronize(source.key);
  watch.stop();
  sample.cancel();
  require(await store.read((tx) => tx.count()) == size, 'Full scan count');
  require(
    (await store.read((tx) => tx.syncState(source.key)))!.cursor ==
        'fixture-complete',
    'Cursor/data commit',
  );
  final browseWatch = Stopwatch()..start();
  final first = await directory.browse('', limit: 100);
  browseWatch.stop();
  require(first.length == size.clamp(0, 100), 'Bounded browsing');
  final queries = ['person42', 'Zoë', '李', 'person000', 'missing'];
  final searchTimes = <int>[];
  for (var i = 0; i < 50; i++) {
    final timing = Stopwatch()..start();
    await directory.browse(queries[i % queries.length], limit: 100);
    timing.stop();
    searchTimes.add(timing.elapsedMicroseconds);
  }
  searchTimes.sort();
  final base = await store.read((tx) => tx.contacts(limit: 1).single);
  // Real adapter rollback: even a staged cursor and contact must roll back as one.
  var rolledBack = false;
  try {
    await store.write<void>((tx) {
      tx.deleteContact(base.identity);
      tx.putSyncState(
        ContactSyncState(sourceKey: source.key, cursor: 'must-not-commit'),
      );
      throw StateError('fixture rollback');
    });
  } catch (_) {
    rolledBack = true;
  }
  require(
    rolledBack && await store.read((tx) => tx.contact(base.identity)) != null,
    'Rollback preserves source',
  );
  require(
    (await store.read((tx) => tx.syncState(source.key)))!.cursor ==
        'fixture-complete',
    'Rollback preserves cursor',
  );
  var notified = 0;
  final subscription = store.changes.listen((_) => notified++);
  try {
    await store.write<void>((tx) {
      tx.deleteContact(base.identity);
      throw StateError('rollback');
    });
  } catch (_) {}
  await Future<void>.delayed(Duration.zero);
  require(notified == 0, 'Rollback must not notify');
  await subscription.cancel();
  await store.write((tx) {
    tx.putDraft(
      ContactDraft(
        id: 'saved-draft',
        sourceKey: source.key,
        identity: base.identity,
        patch: const ContactPatch(notes: FieldEdit.set('Unsaved fixture note')),
      ),
    );
    tx.putMutation(
      ContactMutation(
        id: 'interrupted',
        accountId: 'fixture',
        sourceKey: source.key,
        kind: ContactMutationKind.update,
        state: ContactMutationState.executing,
        createdAt: DateTime.now(),
        identity: base.identity,
        base: base,
        patch: const ContactPatch(notes: FieldEdit.clear()),
      ),
    );
  });
  ContactsReadTransaction? escaped;
  await store.read((tx) {
    escaped = tx;
  });
  var fenced = false;
  try {
    escaped!.accounts();
  } catch (_) {
    fenced = true;
  }
  require(fenced, 'Transaction cannot escape its synchronous callback');
  var readOnly = false;
  try {
    await store.read(
      (tx) => (tx as ContactsWriteTransaction).deleteContact(base.identity),
    );
  } catch (_) {
    readOnly = true;
  }
  require(readOnly, 'Read transaction cannot mutate');
  await directory.close();
  await store.close();
  final header = await file.open();
  final bytes = await header.read(16);
  await header.close();
  require(
    utf8.decode(bytes, allowMalformed: true) != 'SQLite format 3\u0000',
    'Store must be encrypted',
  );
  var wrongKeyRejected = false;
  try {
    final wrong = await ContactsDatabase.open(file, List.filled(32, 9));
    await wrong.close();
  } catch (_) {
    wrongKeyRejected = true;
  }
  require(wrongKeyRejected, 'Wrong profile key cannot open contacts');
  store = await ContactsDatabase.open(file, key);
  directory = ContactsDirectory(store: store);
  await directory.restore();
  require(
    await store.read((tx) => tx.count()) == size,
    'Restart retains contacts',
  );
  require(
    (await store.read((tx) => tx.mutations())).single.state ==
        ContactMutationState.unknown,
    'Interrupted dispatch is uncertain, never invented success',
  );
  require(
    (await store.read((tx) => tx.drafts())).single.patch.notes.value ==
        'Unsaved fixture note',
    'Restart retains draft',
  );
  require(
    (await store.read((tx) => tx.contact(base.identity)))!
            .toJson()
            .toString() ==
        base.toJson().toString(),
    'Full source survives restart',
  );
  final secondFile = File(profile.path + '/independent/contacts.sqlite3');
  final second = await ContactsDatabase.open(secondFile, List.filled(32, 8));
  await second.write((tx) {
    tx.putAccount(account);
    tx.putSource(source);
    tx.putContact(base);
  });
  await store.write((tx) => tx.removeAccount('fixture'));
  require(
    await store.read((tx) => tx.count()) == 0,
    'Account cascade removes only own contacts',
  );
  require(
    await store.read((tx) => tx.drafts()).then((v) => v.isEmpty),
    'Own drafts cascade',
  );
  require(
    await second.read((tx) => tx.count()) == 1,
    'Independent instance is unaffected',
  );
  await second.close();
  await directory.close();
  await store.close();
  final output = {
    'datasetSize': size,
    'fixturePages': pages,
    'syncFixtureMilliseconds': watch.elapsedMilliseconds,
    'boundedBrowseMicroseconds': browseWatch.elapsedMicroseconds,
    'searchP50Microseconds': searchTimes[25],
    'searchP95Microseconds': searchTimes[47],
    'initialRssBytes': initialRss,
    'peakRssBytes': peakRss,
    'rssGrowthBytes': peakRss - initialRss,
    'encryptedBytes': await file.length(),
    'checksPassed': checks,
    'profile': profile.path,
    'provider': 'generated People API over deterministic HTTP fixture',
    'liveProvider': false,
    'uiFrameTimingMeasured': false,
  };
  await File('validation/store-contract.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(output) + '\n');
  stdout.writeln(jsonEncode(output));
}
