import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import 'src/app/busycards_app.dart';
import 'src/application/cards_runtime.dart';
import 'src/platform/gtk_font_service.dart';
import 'src/platform/gtk_animation_settings_service.dart';
import 'src/storage/contacts_database.dart';
import 'src/storage/database_key_store.dart';
import 'src/storage/secret_value_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YaruWindowTitleBar.ensureInitialized();
  final initial = await Future.wait<Object?>([
    const GtkFontService().getGtkFont(),
    const GtkThemeService().getGtkThemeColors(),
    const GtkAnimationSettingsService().getAnimationsEnabled(),
  ]);
  runApp(
    ProviderScope(
      overrides: [
        initialGtkFontSettingsProvider.overrideWithValue(
          initial[0] as GtkFontSettings?,
        ),
        initialGtkThemeColorsProvider.overrideWithValue(
          initial[1] as GtkThemeColors?,
        ),
        initialGtkAnimationsEnabledProvider.overrideWithValue(
          initial[2] as bool?,
        ),
      ],
      child: LinuxBusyCardsApp(openRuntime: _openRuntime),
    ),
  );
}

Future<CardsRuntime> _openRuntime() async {
  final dataHome =
      Platform.environment['XDG_DATA_HOME'] ??
      (Platform.environment['HOME']! + '/.local/share');
  final profile = Directory(
    Platform.environment['BUSYCARDS_PROFILE'] ??
        dataHome + '/io.busystack.busycards/default',
  );
  if (!profile.isAbsolute)
    throw StateError('BusyCards profile must be an absolute path');
  await profile.create(recursive: true);
  final namespace =
      'io.busystack.busycards/' +
      sha256.convert(utf8.encode(profile.absolute.path)).toString();
  final secrets = SecretServiceValueStore(namespace: namespace);
  final file = File(profile.path + '/contacts.sqlcipher');
  final key = await DatabaseKeyStore(secrets: secrets).openForProfile(file);
  final database = await ContactsDatabase.open(file, key);
  final runtime = CardsRuntime(
    store: database,
    secrets: secrets,
    profile: profile,
  );
  await runtime.start();
  return runtime;
}
