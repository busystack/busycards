import 'dart:convert';
import 'dart:io';

import 'package:busycards/main.dart';
import 'package:busycards/src/application/cards_runtime.dart';
import 'package:busycards/src/platform/gtk_header_icon_service.dart';
import 'package:busycards/src/storage/contacts_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/cards_runtime_test.dart' show FixtureSecrets;

void main() {
  testWidgets(
    'Linux startup paints the native icon catalog and owns its subscription',
    (tester) async {
      late final Directory profile;
      late final CardsRuntime runtime;
      await tester.runAsync(() async {
        profile = await Directory.systemTemp.createTemp('cards-startup-');
        final store = await ContactsDatabase.open(
          File('${profile.path}/contacts.sqlcipher'),
          List.generate(32, (i) => i + 1),
        );
        runtime = CardsRuntime(
          store: store,
          secrets: FixtureSecrets(),
          profile: profile,
        );
        await runtime.start(schedule: false);
      });
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL1WQAAAABJRU5ErkJggg==',
      );
      var batches = 0, listens = 0, cancellations = 0;
      const methods = [
        MethodChannel('yaru_window'),
        MethodChannel('io.busystack.busycards/gtk_settings'),
        MethodChannel(gtkHeaderIconsChannelName),
      ];
      messenger.setMockMethodCallHandler(
        methods[0],
        (call) async => call.method == 'state' ? <String, Object?>{} : null,
      );
      messenger.setMockMethodCallHandler(methods[1], (_) async => null);
      messenger.setMockMethodCallHandler(methods[2], (call) async {
        expect(call.method, 'loadIcons');
        batches++;
        return {
          for (final request in call.arguments as List)
            request['key']: {
              'bytes': png,
              'resolvedName': (request['names'] as List).first,
              'scale': 1,
              'pixelWidth': 1,
              'pixelHeight': 1,
            },
        };
      });
      const events = [
        EventChannel('yaru_window/events'),
        EventChannel('io.busystack.busycards/gtk_font_settings'),
        EventChannel('io.busystack.busycards/gtk_theme_colors'),
        EventChannel('io.busystack.busycards/gtk_animation_settings'),
        EventChannel(gtkHeaderIconsChangedChannelName),
      ];
      for (final channel in events) {
        messenger.setMockStreamHandler(
          channel,
          MockStreamHandler.inline(
            onListen: (_, sink) {
              if (channel.name == gtkHeaderIconsChangedChannelName) listens++;
            },
            onCancel: (_) {
              if (channel.name == gtkHeaderIconsChangedChannelName)
                cancellations++;
            },
          ),
        );
      }
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(runtime.close);
        await profile.delete(recursive: true);
        for (final channel in methods)
          messenger.setMockMethodCallHandler(channel, null);
        for (final channel in events)
          messenger.setMockStreamHandler(channel, null);
      });
      await tester.runAsync(
        () => runLinuxBusyCards(openRuntime: () async => runtime),
      );
      await tester.pumpAndSettle();
      expect(
        batches,
        1,
        reason: 'The actual Linux entry point must preload native icons',
      );
      expect(listens, 1);
      expect(
        find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(
        cancellations,
        1,
        reason: 'Disposing the application owns native subscription cleanup',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
