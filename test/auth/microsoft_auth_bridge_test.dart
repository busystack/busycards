import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:busycards/src/auth/microsoft/microsoft_auth_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busystack_contacts/microsoft.dart';
import 'package:busystack_graph/busystack_graph.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('packaged default helper is the launcher alongside the application executable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'busycards-helper-layout-',
    );
    final app = File('${directory.path}/busycards');
    final helper = File('${directory.path}/busycards-microsoft-auth');
    await app.writeAsString('fixture native app');
    await helper.writeAsString('fixture root launcher');
    await Directory('${directory.path}/lib').create();
    await File('${directory.path}/lib/busycards-microsoft-auth')
        .writeAsString('wrong layout');
    String? launched;
    final bridge = MicrosoftAuthBridge(
      applicationExecutable: app.path,
      start: (executable, arguments) async {
        launched = executable;
        expect(File(executable).existsSync(), isTrue);
        return _ProtocolProcess(
          (request) => {
            'version': 1,
            'requestId': request['requestId'],
            'ok': true,
            'result': {'version': 1},
          },
        );
      },
    );
    try {
      await bridge.verifyProtocol();
      expect(launched, helper.path);
      expect(bridge.executablePath, helper.path);
      expect(
        MicrosoftAuthBridge().executablePath,
        '${File(Platform.resolvedExecutable).parent.path}/busycards-microsoft-auth',
      );
    } finally {
      await bridge.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'version handshake is framed, correlated, and scope constrained',
    () async {
      Map<String, Object?>? request;
      final process = _ProtocolProcess((value) {
        request = value;
        return {
          'version': 1,
          'requestId': value['requestId'],
          'ok': true,
          'result': {'version': 1},
          'error': null,
        };
      });
      final bridge = MicrosoftAuthBridge(
        clientId: '',
        executablePath: '/bundle/lib/busycards-microsoft-auth',
        start: (executable, arguments) async {
          expect(executable, '/bundle/lib/busycards-microsoft-auth');
          expect(arguments, isEmpty);
          return process;
        },
      );

      await bridge.verifyProtocol();

      expect(request!['version'], 1);
      expect(request!['method'], 'version');
      expect(request!['clientId'], '');
      expect(request!['scopes'], MicrosoftAuthBridge.scopes);
      expect(request!['requestId'], isNotEmpty);
    },
  );

  test('interactive, silent, claims, enumeration and removal carry the selected registration', () async {
    final requests = <Map<String, Object?>>[];
    for (final id in [
      '00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000002',
    ]) {
      final bridge = MicrosoftAuthBridge(
        clientId: id,
        start: (_, _) async => _ProtocolProcess((request) {
          requests.add(request);
          final method = request['method'];
          return {
            'version': 1,
            'requestId': request['requestId'],
            'ok': true,
            'error': null,
            'result': switch (method) {
              'listAccounts' => {'accounts': <Object>[]},
              'removeAccount' => {'removed': true},
              _ => {
                'accessToken': 'synthetic',
                'expiresOn': '2030-01-01T00:00:00Z',
                'homeAccountId': 'subject',
                'tenantId': 'tenant',
                'scopes': MicrosoftAuthBridge.scopes,
              },
            },
          };
        }),
      );
      await bridge.authorize(claims: '{"access_token":{}}');
      await bridge.acquireToken('subject', claims: '{"access_token":{}}');
      await bridge.listAccounts();
      await bridge.removeAccount('subject');
      expect(
        requests.skip(requests.length - 4).every((v) => v['clientId'] == id),
        isTrue,
      );
      expect(requests[requests.length - 3]['claims'], '{"access_token":{}}');
      await bridge.close();
    }
  });

  test(
    'silent acquisition rejects a token for another cache account',
    () async {
      final bridge = MicrosoftAuthBridge(
        clientId: '00000000-0000-4000-8000-000000000001',
        start: (_, _) async => _ProtocolProcess(
          (request) => {
            'version': 1,
            'requestId': request['requestId'],
            'ok': true,
            'error': null,
            'result': {
              'accessToken': 'synthetic-token',
              'expiresOn': '2030-01-01T00:00:00Z',
              'homeAccountId': 'another-subject',
              'tenantId': 'tenant',
              'scopes': MicrosoftAuthBridge.scopes,
            },
          },
        ),
      );
      addTearDown(bridge.close);
      await expectLater(
        bridge.acquireToken('expected-subject'),
        throwsA(
          isA<MicrosoftAuthException>().having(
            (error) => error.code,
            'code',
            'wrong-account',
          ),
        ),
      );
    },
  );

  test(
    'explicit repair carries cache intent and expected home/tenant identity',
    () async {
      final requests = <Map<String, Object?>>[];
      final bridge = MicrosoftAuthBridge(
        clientId: '00000000-0000-4000-8000-000000000001',
        start: (_, _) async => _ProtocolProcess((request) {
          requests.add(request);
          return {
            'version': 1,
            'requestId': request['requestId'],
            'ok': true,
            'result': request['method'] == 'inspectCache'
                ? {'recoveryToken': 'a' * 64}
                : {
                    'accessToken': 'synthetic',
                    'expiresOn': '2030-01-01T00:00:00Z',
                    'homeAccountId': 'subject',
                    'tenantId': 'tenant',
                    'scopes': MicrosoftAuthBridge.scopes,
                  },
          };
        }),
      );
      final intent = await bridge.unusableCacheRecoveryToken();
      await bridge.repairCache(
        homeAccountId: 'subject',
        tenantId: 'tenant',
        recoveryToken: intent,
      );
      expect(requests[1]['method'], 'repairCache');
      expect(requests[1]['homeAccountId'], 'subject');
      expect(requests[1]['tenantId'], 'tenant');
      expect(requests[1]['recoveryToken'], 'a' * 64);
      expect(requests[1]['clientId'], bridge.clientId);
      await expectLater(
        bridge.repairCache(
          homeAccountId: 'subject',
          tenantId: 'tenant',
          recoveryToken: 'bad',
        ),
        throwsA(isA<MicrosoftAuthException>()),
      );
      expect(requests, hasLength(2));
      await bridge.close();
    },
  );

  test('close cancels an admitted cache repair subprocess', () async {
    final entered = Completer<void>();
    final process = _HangingProcess();
    final bridge = MicrosoftAuthBridge(
      clientId: 'client',
      start: (_, _) async {
        entered.complete();
        return process;
      },
    );
    final result = expectLater(
      bridge.repairCache(
        homeAccountId: 'subject',
        tenantId: 'tenant',
        recoveryToken: 'a' * 64,
      ),
      throwsA(isA<MicrosoftAuthException>()),
    );
    await entered.future;
    await bridge.close();
    await result;
    expect(process.killed, isTrue);
  });

  test('mismatched helper correlation is rejected', () async {
    final bridge = MicrosoftAuthBridge(
      clientId: 'client',
      start: (_, _) async => _ProtocolProcess(
        (request) => {
          'version': 1,
          'requestId': 'different-request',
          'ok': true,
          'result': {'version': 1},
          'error': null,
        },
      ),
    );

    await expectLater(
      bridge.verifyProtocol(),
      throwsA(
        isA<MicrosoftAuthException>().having(
          (error) => error.code,
          'code',
          'protocol-mismatch',
        ),
      ),
    );
  });

  for (final code in [
    'invalid-client',
    'authentication-cancelled',
    'interaction-required',
    'access-denied',
    'consent-required',
    'browser-launch-failed',
    'secure-storage-failed',
    'identity-error',
    'cache-unusable',
    'cache-recovery-conflict',
    'cache-rollback-failed',
    'helper-failed',
  ]) {
    test('F6 framed Microsoft setup classification $code', () async {
      final bridge = MicrosoftAuthBridge(
        clientId: 'fixture',
        start: (_, _) async => _ProtocolProcess(
          (request) => {
            'version': 1,
            'requestId': request['requestId'],
            'ok': false,
            'error': {
              'code': code,
              'message': 'private@example.test synthetic-token',
            },
          },
          exitCode: 2,
        ),
      );
      await expectLater(
        bridge.authorize(),
        throwsA(
          isA<MicrosoftAuthException>()
              .having((error) => error.code, 'code', code)
              .having(
                (error) => error.toString(),
                'redaction',
                isNot(contains('private@example.test')),
              ),
        ),
      );
    });
  }

  test('sanitized helper error codes cross the process boundary', () async {
    final bridge = MicrosoftAuthBridge(
      clientId: 'client',
      start: (_, _) async => _ProtocolProcess(
        (request) => {
          'version': 1,
          'requestId': request['requestId'],
          'ok': false,
          'result': null,
          'error': {'code': 'interaction-required'},
        },
        exitCode: 2,
      ),
    );

    await expectLater(
      bridge.authorize(claims: '{"access_token":{"essential":true}}'),
      throwsA(
        isA<MicrosoftAuthException>().having(
          (error) => error.code,
          'code',
          'interaction-required',
        ),
      ),
    );
  });

  test('missing public client ID never starts the helper', () async {
    var started = false;
    final bridge = MicrosoftAuthBridge(
      clientId: ' ',
      start: (_, _) async {
        started = true;
        return _ProtocolProcess((_) => const {});
      },
    );

    await expectLater(
      bridge.authorize(),
      throwsA(
        isA<MicrosoftAuthException>().having(
          (error) => error.code,
          'code',
          'client-id-missing',
        ),
      ),
    );
    expect(started, isFalse);
  });

  test(
    'oversized claims are rejected before starting a child process',
    () async {
      var started = false;
      final bridge = MicrosoftAuthBridge(
        clientId: 'client',
        start: (_, _) async {
          started = true;
          return _ProtocolProcess((_) => const {});
        },
      );

      await expectLater(
        bridge.authorize(
          claims: List.filled(
            MicrosoftAuthBridge.maximumRequestBytes,
            'x',
          ).join(),
        ),
        throwsA(
          isA<MicrosoftAuthException>().having(
            (error) => error.code,
            'code',
            'request-too-large',
          ),
        ),
      );
      expect(started, isFalse);
    },
  );

  test(
    'trailing helper output and malformed token results are rejected',
    () async {
      final trailing = MicrosoftAuthBridge(
        clientId: 'client',
        start: (_, _) async => _ProtocolProcess(
          (request) => {
            'version': 1,
            'requestId': request['requestId'],
            'ok': true,
            'result': {'version': 1},
            'error': null,
          },
          trailing: const [0],
        ),
      );
      await expectLater(
        trailing.verifyProtocol(),
        throwsA(
          isA<MicrosoftAuthException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );

      final malformed = MicrosoftAuthBridge(
        clientId: 'client',
        start: (_, _) async => _ProtocolProcess(
          (request) => {
            'version': 1,
            'requestId': request['requestId'],
            'ok': true,
            'result': <String, Object?>{},
            'error': null,
          },
        ),
      );
      await expectLater(
        malformed.authorize(),
        throwsA(
          isA<MicrosoftAuthException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    },
  );

  test('close terminates and drains an active helper process', () async {
    final started = Completer<void>();
    final process = _HangingProcess();
    final bridge = MicrosoftAuthBridge(
      clientId: 'client',
      start: (_, _) async {
        started.complete();
        return process;
      },
    );
    final request = bridge.verifyProtocol();
    final requestResult = expectLater(
      request,
      throwsA(isA<MicrosoftAuthException>()),
    );
    await started.future;

    await bridge.close().timeout(const Duration(seconds: 1));

    await requestResult;
    expect(process.killed, isTrue);
    await expectLater(
      bridge.verifyProtocol(),
      throwsA(
        isA<MicrosoftAuthException>().having(
          (error) => error.code,
          'code',
          'helper-closed',
        ),
      ),
    );
  });

  test('R2 close owns a process start admitted before shutdown', () async {
    final entered = Completer<void>();
    final starting = Completer<Process>();
    final process = _HangingProcess();
    final bridge = MicrosoftAuthBridge(
      start: (_, _) {
        entered.complete();
        return starting.future;
      },
    );
    final request = expectLater(
      bridge.verifyProtocol(),
      throwsA(
        isA<MicrosoftAuthException>().having(
          (e) => e.code,
          'code',
          'helper-closed',
        ),
      ),
    );
    await entered.future;
    var finished = false;
    final closing = bridge.close().then((_) => finished = true);
    expect(finished, isFalse);
    starting.complete(process);
    await closing;
    await request;
    expect(process.killed, isTrue);
    expect(await process.exitCode, lessThan(0));
    await bridge.close();
  });

  test('R2 close terminates the bundled JVM while protocol input is pending', () async {
    final dist = Directory('native/microsoft_auth_helper/target/dist').absolute;
    final java = File('${dist.path}/microsoft-auth/runtime/bin/java');
    expect(
      java.existsSync(),
      isTrue,
      reason: 'Build the Java helper before Flutter tests.',
    );
    final started = Completer<Process>();
    final bridge = MicrosoftAuthBridge(
      start: (_, _) async {
        final process = await Process.start(java.path, [
          '-cp',
          '${dist.path}/microsoft-auth/jars/*',
          'io.busystack.busycards.auth.Main',
        ]);
        // The actual helper blocks on an incomplete frame, without credentials,
        // browser, network traffic, or access to a desktop keyring.
        process.stdin.add([0, 0, 0, 10]);
        await process.stdin.flush();
        started.complete(process);
        return _BlockedInputProcess(process);
      },
    );
    final request = expectLater(
      bridge.verifyProtocol(),
      throwsA(isA<MicrosoftAuthException>()),
    );
    final process = await started.future;
    await bridge.close().timeout(const Duration(seconds: 5));
    await request;
    expect(await process.exitCode, lessThan(0));
    expect(Directory('/proc/${process.pid}').existsSync(), isFalse);
  });
  test('contacts Graph 401 base64 claims traverse MSAL silent then account-bound browser acquisition and replay', () async {
    const claims = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}';
    final helperRequests = <Map<String, Object?>>[],
        graphRequests = <http.Request>[];
    final bridge = MicrosoftAuthBridge(
      clientId: 'client',
      start: (_, _) async => _ProtocolProcess((request) {
        helperRequests.add(request);
        if (request['method'] == 'acquireToken' && request['claims'] != null) {
          return {
            'version': 1,
            'requestId': request['requestId'],
            'ok': false,
            'error': {'code': 'interaction-required'},
          };
        }
        return {
          'version': 1,
          'requestId': request['requestId'],
          'ok': true,
          'result': {
            'accessToken': request['claims'] == null ? 'initial' : 'satisfying',
            'expiresOn': '2030-01-01T00:00:00Z',
            'homeAccountId': 'subject',
            'tenantId': 'tenant',
            'scopes': ['Contacts.ReadWrite'],
          },
        };
      }),
    );
    final graph = GraphClient(
      tokenProvider: ({String? claims}) async {
        final token = await bridge.acquireToken('subject', claims: claims);
        return GraphAuthorization(
          token.value,
          grantedScopes: token.scopes.toSet(),
        );
      },
      httpClient: MockClient((request) async {
        graphRequests.add(request);
        if (graphRequests.length == 1)
          return http.Response(
            '{}',
            401,
            headers: {
              'www-authenticate':
                  'Bearer error="insufficient_claims", authorization_uri="https://login.microsoftonline.com/common/oauth2/authorize", claims="${base64.encode(utf8.encode(claims))}"',
            },
          );
        expect(request.headers['authorization'], 'Bearer satisfying');
        return http.Response('{"value":[]}', 200);
      }),
    );
    final provider = MicrosoftContactsProvider(
      accountId: 'account',
      graph: graph,
      grantedScopes: {'Contacts.ReadWrite'},
      personalAccount: false,
    );
    expect(
      (await provider.discover(ContactsCancellationToken())).single.id,
      'default',
    );
    expect(helperRequests.map((request) => request['method']), [
      'acquireToken',
      'acquireToken',
      'authorize',
    ]);
    expect(helperRequests.map((request) => request['claims']), [
      null,
      claims,
      claims,
    ]);
    expect(
      helperRequests.every((request) => request['homeAccountId'] == 'subject'),
      isTrue,
    );
    expect(graphRequests, hasLength(2));
    provider.close();
    await bridge.close();
  });

  test(
    'ordinary silent interaction-required never starts a claims browser flow',
    () async {
      final requests = <Map<String, Object?>>[];
      final bridge = MicrosoftAuthBridge(
        clientId: 'client',
        start: (_, _) async => _ProtocolProcess((request) {
          requests.add(request);
          return {
            'version': 1,
            'requestId': request['requestId'],
            'ok': false,
            'error': {'code': 'interaction-required'},
          };
        }),
      );
      await expectLater(
        bridge.acquireToken('subject'),
        throwsA(
          isA<MicrosoftAuthException>().having(
            (error) => error.code,
            'code',
            'interaction-required',
          ),
        ),
      );
      expect(requests, hasLength(1));
      await bridge.close();
    },
  );

  test('claims interactive completion rejects a different account before Graph replay', () async {
    final bridge = MicrosoftAuthBridge(
      clientId: 'client',
      start: (_, _) async => _ProtocolProcess((request) {
        if (request['method'] == 'acquireToken')
          return {
            'version': 1,
            'requestId': request['requestId'],
            'ok': false,
            'error': {'code': 'interaction-required'},
          };
        expect(request['homeAccountId'], 'subject');
        return {
          'version': 1,
          'requestId': request['requestId'],
          'ok': true,
          'result': {
            'accessToken': 'wrong',
            'expiresOn': '2030-01-01T00:00:00Z',
            'homeAccountId': 'other',
            'tenantId': 'tenant',
            'scopes': ['Contacts.ReadWrite'],
          },
        };
      }),
    );
    await expectLater(
      bridge.acquireToken('subject', claims: '{"access_token":{}}'),
      throwsA(
        isA<MicrosoftAuthException>().having(
          (error) => error.code,
          'code',
          'wrong-account',
        ),
      ),
    );
    await bridge.close();
  });
}

class _BlockedInputProcess implements Process {
  _BlockedInputProcess(this.process) {
    final input = StreamController<List<int>>();
    input.stream.listen((_) {});
    stdin = IOSink(input.sink);
  }
  final Process process;
  @override
  late final IOSink stdin;
  @override
  Stream<List<int>> get stdout => process.stdout;
  @override
  Stream<List<int>> get stderr => process.stderr;
  @override
  Future<int> get exitCode => process.exitCode;
  @override
  int get pid => process.pid;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      process.kill(signal);
}

class _HangingProcess implements Process {
  _HangingProcess() {
    stdin = IOSink(_input.sink);
    stdout = _output.stream;
    stderr = const Stream.empty();
  }

  final StreamController<List<int>> _input = StreamController();
  final StreamController<List<int>> _output = StreamController();
  final Completer<int> _exit = Completer();
  bool killed = false;

  @override
  late final IOSink stdin;

  @override
  late final Stream<List<int>> stdout;

  @override
  late final Stream<List<int>> stderr;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 8;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(-signal.signalNumber);
    if (!_output.isClosed) _output.close();
    return true;
  }
}

class _ProtocolProcess implements Process {
  _ProtocolProcess(this._respond, {int exitCode = 0, this.trailing = const []})
    : _configuredExitCode = exitCode {
    stdin = IOSink(_input.sink);
    stdout = _output.stream;
    stderr = const Stream.empty();
    _input.stream.expand((chunk) => chunk).toList().then((bytes) {
      final declaredLength = ByteData.sublistView(
        Uint8List.fromList(bytes),
        0,
        4,
      ).getUint32(0, Endian.big);
      final request = (jsonDecode(
        utf8.decode(bytes.sublist(4, 4 + declaredLength)),
      ) as Map).cast<String, Object?>();
      final payload = utf8.encode(jsonEncode(_respond(request)));
      final header = ByteData(4)..setUint32(0, payload.length, Endian.big);
      _output.add(header.buffer.asUint8List());
      _output.add(payload);
      if (trailing.isNotEmpty) _output.add(trailing);
      _output.close();
      _exit.complete(_configuredExitCode);
    });
  }

  final Map<String, Object?> Function(Map<String, Object?> request) _respond;
  final int _configuredExitCode;
  final List<int> trailing;
  final StreamController<List<int>> _input = StreamController();
  final StreamController<List<int>> _output = StreamController();
  final Completer<int> _exit = Completer();

  @override
  late final IOSink stdin;

  @override
  late final Stream<List<int>> stdout;

  @override
  late final Stream<List<int>> stderr;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 7;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) _exit.complete(-signal.signalNumber);
    return true;
  }
}
