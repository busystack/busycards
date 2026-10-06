import 'dart:io';

import 'package:busycards/src/auth/microsoft/microsoft_auth_bridge.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1)
    throw ArgumentError('Supply the BusyCards helper path');
  final helper = File(arguments.single).absolute;
  final profiles = await Directory('validation/profiles')
      .create(recursive: true);
  final profile = await profiles.createTemp('helper-protocol-');
  final environment = <String, String>{
    ...Platform.environment,
    for (final key in ['DATA', 'CONFIG', 'CACHE', 'RUNTIME'])
      'XDG_' + key + '_HOME': profile.path + '/' + key.toLowerCase(),
    'DBUS_SESSION_BUS_ADDRESS': 'unix:path=' + profile.path + '/absent-bus',
  };
  environment['XDG_RUNTIME_DIR'] = profile.path + '/runtime';
  environment.remove('DISPLAY');
  environment.remove('WAYLAND_DISPLAY');
  environment.remove('GNOME_KEYRING_CONTROL');
  for (final part in ['data', 'config', 'cache', 'runtime']) {
    await Directory(profile.path + '/' + part).create(recursive: true);
  }
  var checks = 0;
  final bridge = MicrosoftAuthBridge(
    clientId: '00000000-0000-0000-0000-000000000001',
    executablePath: helper.path,
    start: (executable, arguments) => Process.start(
      executable,
      arguments,
      environment: environment,
      includeParentEnvironment: false,
    ),
  );
  await bridge.verifyProtocol();
  checks++;
  for (final scope in [
    'Mail.ReadWrite',
    'Calendars.ReadWrite',
    'Files.ReadWrite',
    'User.Read',
  ]) {
    try {
      MicrosoftAuthBridge(requestedScopes: [scope]);
      throw StateError('Scope was admitted');
    } on MicrosoftAuthException catch (error) {
      if (error.code != 'invalid-scope') rethrow;
      checks++;
    }
  }
  try {
    await bridge.listAccounts();
    throw StateError('Missing private keyring was accepted');
  } on MicrosoftAuthException catch (error) {
    if (error.code != 'secure-storage-failed') rethrow;
    checks++;
  }
  await bridge.close();
  try {
    await bridge.verifyProtocol();
    throw StateError('Closed helper started');
  } on MicrosoftAuthException catch (error) {
    if (error.code != 'helper-closed') rethrow;
    checks++;
  }
  stdout.writeln(
    'PASS ' + checks.toString() + ' actual BusyCards Dart/native protocol and scope checks; private keyring unavailable was rejected.',
  );
}
