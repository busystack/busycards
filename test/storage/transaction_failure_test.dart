import 'dart:async';
import 'dart:io';

import 'package:busycards/src/storage/contacts_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final failure in ['BEGIN IMMEDIATE', 'callback', 'COMMIT', 'ROLLBACK']) {
    test(
      'adapter settles operation and close after $failure failure',
      () async {
        final profile = await Directory.systemTemp.createTemp(
          'cards-transaction-',
        );
        final original = StateError('original');
        final cleanup = StateError('rollback');
        var inject = true;
        final store = await ContactsDatabase.open(
          File('${profile.path}/contacts.sqlite3'),
          List.generate(32, (i) => i + 1),
          beforeTransactionStatement: (sql) {
            if (inject && sql == failure) {
              inject = false;
              throw failure == 'ROLLBACK' ? cleanup : original;
            }
          },
        );
        final notifications = <void>[];
        final subscription = store.changes.listen(notifications.add);
        final operation = store.write((tx) async {
          await tx.accounts();
          if (failure == 'callback' || failure == 'ROLLBACK') throw original;
          return 42;
        });
        Object? observed;
        try {
          await operation.timeout(const Duration(seconds: 2));
          fail('Transaction must fail');
        } catch (error) {
          observed = error;
        }
        expect(observed, isNot(isA<TimeoutException>()));
        if (failure == 'ROLLBACK') {
          expect(
            observed,
            isA<ContactsTransactionFailure>()
                .having((e) => e.cause, 'original cause', same(original))
                .having(
                  (e) => e.cleanupErrors.single,
                  'cleanup',
                  same(cleanup),
                ),
          );
          await expectLater(
            store.read((tx) => tx.accounts()),
            throwsStateError,
          );
        } else if (failure == 'BEGIN IMMEDIATE') {
          expect(observed, same(original));
          await expectLater(
            store.read((tx) => tx.accounts()),
            throwsStateError,
          );
        } else {
          expect(observed, same(original));
          expect(await store.read((tx) => tx.accounts()), isEmpty);
        }
        expect(notifications, isEmpty);
        await store.close().timeout(const Duration(seconds: 2));
        await store.close();
        await subscription.cancel();
        await profile.delete(recursive: true);
      },
    );
  }
}
