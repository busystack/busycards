import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

final _sensitivePatterns = <RegExp>[
  RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
  RegExp(
    r'(^|[?&\s])(access_token|refresh_token|id_token|client_secret|code_verifier|code)=[^&\s]+',
    caseSensitive: false,
  ),
  RegExp(r'([?&])token=[^&\s]+', caseSensitive: false),
  RegExp(r'"client_secret"\s*:\s*"[^"]*"', caseSensitive: false),
  RegExp(r'Authorization:\s*[^,\n]+', caseSensitive: false),
  RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
];

String redactForLog(Object? value) {
  var text = value?.toString() ?? '';
  for (final pattern in _sensitivePatterns) {
    text = text.replaceAllMapped(pattern, (match) {
      final source = match.group(0) ?? '';
      if (source.contains('=')) {
        return '${source.substring(0, source.indexOf('='))}=[REDACTED]';
      }
      if (source.trimLeft().startsWith('"')) {
        return '"client_secret":"[REDACTED]"';
      }
      if (source.toLowerCase().startsWith('authorization:')) {
        return 'Authorization: [REDACTED]';
      }
      if (source.contains('@')) return '<email>';
      return 'Bearer [REDACTED]';
    });
  }
  return text;
}

void configureLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    final line =
        '[${record.level.name}] ${record.loggerName}: '
        '${redactForLog(record.message)}';
    if (kDebugMode) {
      debugPrint(line);
    } else {
      stderr.writeln(line);
    }
  });
}

class RedactingLogger {
  const RedactingLogger(this._logger);

  final Logger _logger;

  void fine(Object? message) => _logger.fine(redactForLog(message));
  void info(Object? message) => _logger.info(redactForLog(message));
  void warning(Object? message) => _logger.warning(redactForLog(message));
  void severe(Object? message) => _logger.severe(redactForLog(message));
}
