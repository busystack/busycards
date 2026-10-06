import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class MicrosoftAccessToken {
  const MicrosoftAccessToken({
    required this.value,
    required this.expiresOn,
    required this.homeAccountId,
    required this.tenantId,
    required this.scopes,
  });

  final String value;
  final DateTime expiresOn;
  final String homeAccountId;
  final String tenantId;
  final List<String> scopes;
}

class MicrosoftKnownAccount {
  const MicrosoftKnownAccount({
    required this.homeAccountId,
    required this.username,
    required this.environment,
  });

  final String homeAccountId;
  final String username;
  final String environment;
}

class MicrosoftAuthBridge {
  MicrosoftAuthBridge({
    this.clientId = '',
    this.requestedScopes = scopes,
    String? executablePath,
    String? applicationExecutable,
    Future<Process> Function(String executable, List<String> arguments)? start,
    Uuid? uuid,
  }) : executablePath =
           executablePath ??
           _defaultExecutablePath(
             applicationExecutable ?? Platform.resolvedExecutable,
           ),
       _start = start ?? Process.start,
       _uuid = uuid ?? const Uuid() {
    const allowed = {
      'openid',
      'profile',
      'email',
      'Contacts.Read',
      'Contacts.ReadWrite',
      'offline_access',
    };
    if (requestedScopes.isEmpty ||
        requestedScopes.toSet().difference(allowed).isNotEmpty ||
        !requestedScopes.any(
          (scope) => scope == 'Contacts.Read' || scope == 'Contacts.ReadWrite',
        )) {
      throw const MicrosoftAuthException('invalid-scope');
    }
  }

  static const protocolVersion = 1;
  static const scopes = <String>[
    'openid',
    'profile',
    'email',
    'Contacts.ReadWrite',
    'offline_access',
  ];
  static const maximumRequestBytes = 64 * 1024;
  static const maximumResponseBytes = 1024 * 1024;

  final String clientId;
  final List<String> requestedScopes;
  final String executablePath;
  final Future<Process> Function(String executable, List<String> arguments)
  _start;
  final Uuid _uuid;
  final Set<Process> _activeProcesses = {};
  final Set<Future<Process>> _pendingStarts = {};
  bool _closed = false;
  Future<void>? _closing;

  Future<void> verifyProtocol() async {
    final result = await _invoke('version');
    if (result['version'] != protocolVersion) {
      throw const MicrosoftAuthException('protocol-mismatch');
    }
  }

  Future<MicrosoftAccessToken> authorize({String? claims}) async {
    return _tokenFrom(await _invoke('authorize', claims: claims));
  }

  Future<MicrosoftAccessToken> acquireToken(
    String homeAccountId, {
    String? claims,
  }) async {
    late final Map<String, Object?> result;
    try {
      result = await _invoke(
        'acquireToken',
        homeAccountId: homeAccountId,
        claims: claims,
      );
    } on MicrosoftAuthException catch (error) {
      // A claims challenge can require MFA or another interactive policy.
      // Preserve the selected account and claims; ordinary refresh failures
      // never start an unsolicited browser flow.
      if (claims == null || error.code != 'interaction-required') rethrow;
      result = await _invoke(
        'authorize',
        homeAccountId: homeAccountId,
        claims: claims,
      );
    }
    final token = _tokenFrom(result);
    if (token.homeAccountId != homeAccountId) {
      throw const MicrosoftAuthException('wrong-account');
    }
    return token;
  }

  Future<List<MicrosoftKnownAccount>> listAccounts() async {
    final result = await _invoke('listAccounts');
    return [
      for (final item in result['accounts']! as List)
        MicrosoftKnownAccount(
          homeAccountId: (item as Map)['homeAccountId']! as String,
          username: item['username']! as String,
          environment: item['environment']! as String,
        ),
    ];
  }

  Future<bool> removeAccount(String homeAccountId) async {
    final result = await _invoke('removeAccount', homeAccountId: homeAccountId);
    return result['removed']! as bool;
  }

  Future<String> unusableCacheRecoveryToken() async {
    final result = await _invoke('inspectCache');
    final token = result['recoveryToken'];
    if (token is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw const MicrosoftAuthException('protocol-mismatch');
    }
    return token;
  }

  Future<MicrosoftAccessToken> repairCache({
    required String homeAccountId,
    required String tenantId,
    required String recoveryToken,
  }) async {
    if (homeAccountId.isEmpty ||
        tenantId.isEmpty ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(recoveryToken)) {
      throw const MicrosoftAuthException('invalid-request');
    }
    final token = _tokenFrom(
      await _invoke(
        'repairCache',
        homeAccountId: homeAccountId,
        tenantId: tenantId,
        recoveryToken: recoveryToken,
      ),
    );
    if (token.homeAccountId != homeAccountId || token.tenantId != tenantId) {
      throw const MicrosoftAuthException('wrong-account');
    }
    return token;
  }

  Future<void> clearRegistrationCache() async {
    await _invoke('clearCache');
  }

  Future<Map<String, Object?>> _invoke(
    String method, {
    String? homeAccountId,
    String? claims,
    String? tenantId,
    String? recoveryToken,
  }) async {
    if (_closed) {
      throw const MicrosoftAuthException('helper-closed');
    }
    if (method != 'version' && clientId.trim().isEmpty) {
      throw const MicrosoftAuthException('client-id-missing');
    }
    final requestId = _uuid.v7();
    final requestBytes = utf8.encode(
      jsonEncode({
        'version': protocolVersion,
        'requestId': requestId,
        'method': method,
        'clientId': clientId,
        'homeAccountId': homeAccountId,
        'claims': claims,
        if (tenantId != null) 'tenantId': tenantId,
        if (recoveryToken != null) 'recoveryToken': recoveryToken,
        'scopes': requestedScopes,
      }),
    );
    if (requestBytes.length > maximumRequestBytes) {
      throw const MicrosoftAuthException('request-too-large');
    }
    late final Process process;
    try {
      final starting = _start(executablePath, const []);
      _pendingStarts.add(starting);
      try {
        process = await starting;
      } finally {
        _pendingStarts.remove(starting);
      }
    } on Object {
      throw const MicrosoftAuthException('helper-start-failed');
    }
    if (_closed) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
      throw const MicrosoftAuthException('helper-closed');
    }
    _activeProcesses.add(process);
    unawaited(
      process.exitCode.whenComplete(() => _activeProcesses.remove(process)),
    );
    final stderrFuture = _boundedBytes(
      process.stderr,
      maximumBytes: 64 * 1024,
      process: process,
      tooLargeCode: 'stderr-too-large',
    ).timeout(const Duration(seconds: 90), onTimeout: () => const <int>[]);
    final frame = BytesBuilder(copy: false)
      ..add(
        (ByteData(
          4,
        )..setUint32(0, requestBytes.length, Endian.big)).buffer.asUint8List(),
      )
      ..add(requestBytes);
    process.stdin.add(frame.takeBytes());
    await process.stdin.close();
    late final List<int> frameBytes;
    try {
      frameBytes =
          await _boundedBytes(
            process.stdout,
            maximumBytes: maximumResponseBytes + 4,
            process: process,
            tooLargeCode: 'response-too-large',
          ).timeout(
            const Duration(minutes: 5),
            onTimeout: () {
              process.kill(ProcessSignal.sigkill);
              throw const MicrosoftAuthException('helper-timeout');
            },
          );
    } on Object {
      process.kill(ProcessSignal.sigkill);
      rethrow;
    }
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw const MicrosoftAuthException('helper-exit-timeout');
      },
    );
    await stderrFuture;
    if (frameBytes.length < 4) {
      if (frameBytes.isEmpty && (exitCode == 126 || exitCode == 127)) {
        throw const MicrosoftAuthException('helper-runtime-failed');
      }
      throw const MicrosoftAuthException('invalid-response');
    }
    final declaredLength = ByteData.sublistView(
      Uint8List.fromList(frameBytes),
      0,
      4,
    ).getUint32(0, Endian.big);
    if (declaredLength > maximumResponseBytes ||
        frameBytes.length != declaredLength + 4) {
      throw const MicrosoftAuthException('invalid-response');
    }
    final bytes = frameBytes.sublist(4);
    Map<String, Object?> response;
    try {
      response = (jsonDecode(utf8.decode(bytes)) as Map)
          .cast<String, Object?>();
    } on Object {
      throw const MicrosoftAuthException('invalid-response');
    }
    if (response['version'] != protocolVersion ||
        response['requestId'] != requestId) {
      throw const MicrosoftAuthException('protocol-mismatch');
    }
    if (response['ok'] != true || exitCode != 0) {
      final error = response['error'];
      final code = error is Map ? error['code'] as String? : null;
      throw MicrosoftAuthException(
        code != null && RegExp(r'^[a-z0-9-]{1,64}$').hasMatch(code)
            ? code
            : 'helper-failed',
      );
    }
    return (response['result'] as Map).cast<String, Object?>();
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    final active = _activeProcesses.toList(growable: false);
    for (final process in active) {
      process.kill(ProcessSignal.sigkill);
    }
    await Future.wait([
      for (final process in active)
        process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () => -1,
        ),
    ]);
    _activeProcesses.removeAll(active);
    // A Process.start admitted before shutdown may resolve after the sweep.
    // Its closed-state path kills and awaits the actual child; await starts
    // here too so close cannot report completion with an unowned JVM.
    await Future.wait([
      for (final starting in _pendingStarts.toList(growable: false))
        starting.then((process) async {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () => -1,
          );
        }, onError: (Object _) {}),
    ]);
  }

  MicrosoftAccessToken _tokenFrom(Map<String, Object?> result) {
    try {
      final token = result['accessToken']! as String;
      final homeAccountId = result['homeAccountId']! as String;
      final tenantId = result['tenantId']! as String;
      final scopes = (result['scopes']! as List).cast<String>();
      final expiresOn = DateTime.parse(result['expiresOn']! as String).toUtc();
      if (token.isEmpty ||
          homeAccountId.isEmpty ||
          tenantId.isEmpty ||
          scopes.isEmpty) {
        throw const FormatException();
      }
      return MicrosoftAccessToken(
        value: token,
        expiresOn: expiresOn,
        homeAccountId: homeAccountId,
        tenantId: tenantId,
        scopes: scopes,
      );
    } on Object {
      throw const MicrosoftAuthException('invalid-response');
    }
  }
}

Future<List<int>> _boundedBytes(
  Stream<List<int>> stream, {
  required int maximumBytes,
  required Process process,
  required String tooLargeCode,
}) async {
  final result = <int>[];
  await for (final chunk in stream) {
    if (result.length + chunk.length > maximumBytes) {
      process.kill(ProcessSignal.sigkill);
      throw MicrosoftAuthException(tooLargeCode);
    }
    result.addAll(chunk);
  }
  return result;
}

class MicrosoftAuthException implements Exception {
  const MicrosoftAuthException(this.code);

  final String code;

  @override
  String toString() => 'MicrosoftAuthException($code)';
}

String _defaultExecutablePath(String applicationExecutable) {
  final executableDirectory = p.dirname(applicationExecutable);
  return p.join(executableDirectory, 'busycards-microsoft-auth');
}
