import 'dart:io';

import 'package:busycards/src/app/busycards_app.dart';
import 'package:busycards/src/application/cards_runtime.dart';
import 'package:busycards/src/features/contacts/contact_editor.dart';
import 'package:busycards/src/features/contacts/contacts_workspace.dart';
import 'package:busycards/src/storage/contacts_database.dart';
import 'package:busystack_contacts/busystack_contacts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/cards_runtime_test.dart' show FixtureSecrets;
import '../support/carddav_http_fixture.dart';

void main() {
  late Directory profile;
  late ContactsDatabase store;
  late CardsRuntime runtime;
  late DavFixture fixture;
  const nativeEvents = [
    EventChannel('io.busystack.busycards/gtk_font_settings'),
    EventChannel('io.busystack.busycards/gtk_theme_colors'),
  ];
  setUp(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in nativeEvents) {
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(onListen: (_, sink) {}, onCancel: (_) {}),
      );
    }
    profile = await Directory.systemTemp.createTemp('busycards-ui-fixture-');
    store = await ContactsDatabase.open(
      File(profile.path + '/contacts.sqlite3'),
      List.generate(32, (i) => i + 1),
    );
    fixture = DavFixture();
    runtime = CardsRuntime(
      store: store,
      secrets: FixtureSecrets(),
      profile: profile,
      httpClientFactory: () => fixture.httpClient,
    );
    await runtime.start(schedule: false);
  });
  tearDown(() async {
    await runtime.close();
    await profile.delete(recursive: true);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in nativeEvents)
      messenger.setMockStreamHandler(channel, null);
  });
  Future<void> showApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(child: LinuxBusyCardsApp(openRuntime: () async => runtime)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> connect(WidgetTester tester) async {
    await tester.runAsync(() async {
      final account = await runtime.connectCardDav(
        label: 'Fixture cloud',
        server: server,
        username: 'actual-user',
        password: 'fixture',
        nextcloud: true,
      );
      await runtime.synchronizeAccount(account.id);
      final snapshot = await store.read(
        (tx) async =>
            (await tx.accounts(), await tx.sources(), await tx.count()),
      );
      expect(snapshot.$1, hasLength(1));
      expect(snapshot.$2, isNotEmpty);
      expect(snapshot.$3, greaterThan(0));
    });
  }

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        final visibleText = tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.data)
            .whereType<String>()
            .toList();
        throw TestFailure(
          'Timed out waiting for $finder; visible text: $visibleText',
        );
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> waitForAbsent(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (finder.evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure('Timed out waiting for $finder to disappear');
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> waitForCount(
    WidgetTester tester,
    Finder finder,
    int count, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (finder.evaluate().length != count) {
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure('Timed out waiting for $count matches of $finder');
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets(
    'ordinary empty shell opens and Settings exposes every production connection',
    (tester) async {
      await showApp(tester);
      expect(find.byType(ContactsWorkspace), findsOneWidget);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      for (final label in [
        'Add Google',
        'Add Microsoft',
        'Add CardDAV',
        'Add Nextcloud',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('BusyCards registrations'), findsOneWidget);
    },
  );
  testWidgets(
    'cached Unicode search and read-only details use the actual private store',
    (tester) async {
      await connect(tester);
      await showApp(tester);
      await waitFor(tester, find.text('Zoë 李'));
      final search = find.byType(TextField).first;
      await tester.enterText(search, 'Zoë');
      await tester.pump(const Duration(milliseconds: 150));
      await waitFor(tester, find.text('Zoë 李'));
      expect(find.text('Zoë 李'), findsWidgets);
      await tester.enterText(search, 'no-match');
      await tester.pump(const Duration(milliseconds: 150));
      await waitForAbsent(tester, find.text('Zoë 李'));
      expect(find.text('Zoë 李'), findsNothing);
      await tester.enterText(search, '');
      await tester.pump(const Duration(milliseconds: 150));
      await waitFor(tester, find.text('Zoë 李'));
      await tester.tap(find.text('Read only').first);
      await waitForCount(tester, find.text('Zoë 李'), 1);
      await tester.tap(find.text('Zoë 李').first);
      await waitFor(tester, find.text('Edit'));
      final edit = tester.widget<Widget>(
        find
            .ancestor(
              of: find.text('Edit'),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .first,
      );
      expect((edit as ButtonStyleButton).onPressed, isNull);
    },
  );
  testWidgets(
    'editor clears a field explicitly, autosaves drafts and retains unknown vCard data',
    (tester) async {
      fixture.card = fixture.card.replaceFirst(
        'NOTE:Original\r\n',
        'NOTE:Original\r\nNOTE;LANGUAGE=fr;X-PARAM=keep:Additional note\r\n',
      );
      await connect(tester);
      await showApp(tester);
      await waitFor(tester, find.text('Zoë 李'));
      await tester.tap(find.text('Personal').first);
      await waitFor(tester, find.text('Zoë 李'));
      await tester.tap(find.text('Zoë 李').first);
      await waitFor(tester, find.text('Edit'));
      await tester.tap(find.text('Edit'));
      await waitFor(tester, find.byType(ContactEditor));
      expect(find.byType(ContactEditor), findsOneWidget);
      await tester.ensureVisible(field('Notes'));
      await tester.enterText(field('Notes'), '');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.runAsync(() async {
        expect(
          (await store.read((tx) => tx.drafts())).single.patch.notes.kind,
          FieldEditKind.clear,
        );
      });
      await tester.tap(find.text('Save').last);
      // Production parsing uses a real isolate while store notifications drive
      // widget-zone reads. Alternate real time and widget pumps so neither
      // queue is artificially paused by the test binding.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      ContactRecord? edited;
      while (true) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
        final state = await tester.runAsync(
          () => store.read(
            (tx) async => (
              (await tx.contacts()).firstWhere(
                (record) => record.identity.sourceId.endsWith('/book/'),
              ),
              await tx.drafts(),
            ),
          ),
        );
        if (state!.$1.projection.notes.isEmpty && state.$2.isEmpty) {
          edited = state.$1;
          break;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Production save did not complete');
        }
      }
      await waitForAbsent(tester, find.byType(ContactEditor));
      expect(edited.projection.notes, '');
      final card = edited as CardDavContactRecord;
      expect(card.vcard.text('X-FUTURE'), 'keep');
      expect(card.vcard.values('NOTE'), hasLength(2));
      expect(card.vcard.values('NOTE').last.text, 'Additional note');
      expect(card.vcard.values('NOTE').last.parameter('X-PARAM'), ['keep']);
    },
  );
  testWidgets(
    'pending conflict presents base, local and remote values without replay',
    (tester) async {
      await connect(tester);
      await tester.runAsync(() async {
        final base = await store.read(
          (tx) async => (await tx.contacts()).firstWhere(
            (r) => r.identity.sourceId.endsWith('/book/'),
          ),
        );
        fixture.conflict = true;
        await runtime.directory.update(
          base,
          const ContactPatch(notes: FieldEdit.set('Local note')),
        );
      });
      await showApp(tester);
      await waitFor(tester, find.text('1 pending changes'));
      await tester.tap(find.text('1 pending changes'));
      await waitFor(tester, find.text('Review base, local and remote'));
      await tester.tap(find.text('Review base, local and remote'));
      await waitFor(tester, find.text('Your selected changes'));
      expect(find.text('Base'), findsOneWidget);
      expect(find.text('Your selected changes'), findsOneWidget);
      expect(find.text('Remote'), findsOneWidget);
      expect(fixture.puts, 1);
    },
  );
  testWidgets(
    'typing and modal focus prevent application create shortcuts behind an editor',
    (tester) async {
      await connect(tester);
      await showApp(tester);
      await waitFor(tester, find.text('Zoë 李'));
      await tester.tap(find.byTooltip('New contact'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal').last);
      await tester.pumpAndSettle();
      await tester.tap(field('Given name'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(ContactEditor), findsOneWidget);
      expect(find.text('Choose a destination'), findsNothing);
    },
  );
}
