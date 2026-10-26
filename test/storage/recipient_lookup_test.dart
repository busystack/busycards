import 'dart:io';

import 'package:busycards/src/storage/contacts_database.dart';
import 'package:busystack_contacts/busystack_contacts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('F11 recipient lookup pages through encrypted contacts and survives restart', () async {
    final profile = await Directory.systemTemp.createTemp('cards-recipients-');
    final file = File('${profile.path}/contacts.sqlite3');
    final key = List.generate(32, (index) => index + 1);
    var store = await ContactsDatabase.open(file, key);
    addTearDown(() async {
      await store.close();
      await profile.delete(recursive: true);
    });
    const source = ContactSource(
      accountId: 'selected',
      id: 'book',
      provider: ContactProviderKind.carddav,
      kind: ContactSourceKind.carddavAddressBook,
      name: 'Book',
      remotePath: 'https://fixture.invalid/book/',
      capabilities: ContactCapabilities(),
    );
    await store.write((tx) async {
      await tx.putAccount(
        const ContactAccount(
          id: 'selected',
          provider: ContactProviderKind.carddav,
          displayName: 'Selected',
          subject: 'fixture',
          grantedScopes: {},
        ),
      );
      await tx.putSource(source);
      for (var index = 0; index < 203; index++) {
        final identity = ContactIdentity(
          accountId: source.accountId,
          provider: source.provider,
          sourceId: source.id,
          remoteId: '$index',
        );
        final emails = index < 100
            ? <ContactValue>[]
            : [
                ContactValue(
                  index < 200
                      ? 'excluded@example.test'
                      : index < 202
                      ? 'eligible@example.test'
                      : 'next@example.test',
                ),
              ];
        final card = newVcard(
          ContactPatch(
            name: FieldEdit.set(
              ContactName(display: 'Match ${index.toString().padLeft(3, '0')}'),
            ),
            emails: FieldEdit.set(emails),
          ),
          uid: '$index',
        );
        await tx.putContact(
          CardDavContactRecord(
            identity: identity,
            vcard: card,
            revision: '"one"',
            projection: projectVcard(identity, card),
          ),
        );
      }
    });
    Future<void> lookup() async {
      final directory = ContactsDirectory(store: store);
      try {
        final recipients = await directory.suggestRecipients(
          'Match',
          accountIds: {'selected'},
          sourceKeys: {source.key},
          excludedAddresses: {'EXCLUDED@example.test'},
          limit: 2,
        );
        expect(recipients.map((value) => value.email), [
          'eligible@example.test',
          'next@example.test',
        ]);
        expect(recipients.first.identities.map((value) => value.remoteId), [
          '200',
          '201',
        ]);
        expect(
          await directory.browse('Match', sourceKey: source.key, offset: 200),
          hasLength(3),
        );
      } finally {
        await directory.close();
      }
    }

    await lookup();
    await store.close();
    store = await ContactsDatabase.open(file, key);
    await lookup();
  });
}
