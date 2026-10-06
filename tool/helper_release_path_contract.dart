import 'dart:io';

import 'package:busycards/src/auth/microsoft/microsoft_auth_bridge.dart';
import 'package:path/path.dart' as p;

/// Exercises the production default layout against an actual release bundle.
/// Only the registration-free version command executes; no credentials or
/// provider identities are read or acquired.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Supply the extracted/compiled Linux release bundle');
  }
  final bundle = Directory(arguments.single).absolute;
  final application = File(p.join(bundle.path, 'busycards'));
  final helper = File(p.join(bundle.path, 'busycards-microsoft-auth'));
  if (!application.existsSync() || !helper.existsSync()) {
    throw StateError('Incomplete BusyCards application/helper bundle');
  }
  final bridge = MicrosoftAuthBridge(applicationExecutable: application.path);
  try {
    if (bridge.executablePath != helper.path) {
      throw StateError(
        'Production default does not select the packaged launcher',
      );
    }
    await bridge.verifyProtocol();
    stdout.writeln(
      'PASS production default helper layout and actual bundled version handshake',
    );
  } finally {
    await bridge.close();
  }
}
