import 'dart:async';
import 'dart:convert';

import 'package:busycards/src/auth/google/google_oauth_service.dart';
import 'package:busycards/src/storage/secret_value_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jose/jose.dart';

const _configuredGoogle = GoogleOAuthConfiguration(
  clientId: 'client',
  clientSecret: 'desktop-client-credential',
);

void main() {
  test('coalesced cached credential reads complete and release the in-flight entry', () async {
    final secrets = _MemorySecrets();
    secrets.values[_key('subject')] = jsonEncode({
      ...AccessCredentials(
        AccessToken(
          'Bearer',
          'cached',
          DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
        'refresh',
        GoogleOAuthService.scopes,
      ).toJson(),
      'client_id': _configuredGoogle.clientId,
      'registration_id': _configuredGoogle.registrationId,
    });
    final service = GoogleOAuthService(
      configuration: _configuredGoogle,
      secrets: secrets,
    );
    addTearDown(service.close);
    final results = await Future.wait([
      service.validCredentials('subject'),
      service.validCredentials('subject'),
    ]).timeout(const Duration(seconds: 5));
    expect(
      results.map((value) => value.accessToken.data),
      everyElement('cached'),
    );
    expect(
      (await service
              .validCredentials('subject')
              .timeout(const Duration(seconds: 5)))
          .accessToken
          .data,
      'cached',
    );
  });
  for (final cleanup in ['subject', 'registration', 'profile', 'close']) {
    test(
      'R1 late refresh cannot survive $cleanup cleanup across services',
      () async {
        final secrets = _MemorySecrets();
        for (final subject in ['subject', 'companion']) {
          secrets.values[_key(subject)] = jsonEncode({
            ...AccessCredentials(
              AccessToken('Bearer', 'expired', DateTime.utc(2000)),
              'refresh',
              GoogleOAuthService.scopes,
            ).toJson(),
            'client_id': _configuredGoogle.clientId,
            'registration_id': _configuredGoogle.registrationId,
          });
        }
        secrets.values['google-oauth-credential-index-v2'] = jsonEncode([
          _key('subject'),
          _key('companion'),
        ]);
        final entered = Completer<void>();
        final response = Completer<http.Response>();
        final service = GoogleOAuthService(
          configuration: _configuredGoogle,
          secrets: secrets,
          httpClient: MockClient((_) {
            entered.complete();
            return response.future;
          }),
        );
        final cleaner = GoogleOAuthService(
          configuration: _configuredGoogle,
          secrets: secrets,
        );
        addTearDown(service.close);
        addTearDown(cleaner.close);
        final result = service
            .validCredentials('subject')
            .then<Object>((v) => v, onError: (Object e) => e);
        await entered.future;
        switch (cleanup) {
          case 'subject':
            await cleaner.removeCredentials('subject');
          case 'registration':
            await cleaner.deleteRegistrationCredentials();
          case 'profile':
            await cleaner.deleteAllCredentials();
          case 'close':
            await service.close();
        }
        final afterCleanup = Map<String, String>.of(secrets.values);
        response.complete(
          http.Response(
            jsonEncode({
              'access_token': 'late-token',
              'token_type': 'Bearer',
              'expires_in': 3600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        expect(await result, isA<GoogleOAuthException>());
        expect(
          secrets.values,
          afterCleanup,
          reason: 'late refresh must not restore a token or index',
        );
        if (cleanup == 'subject') {
          expect(secrets.values[_key('companion')], isNotNull);
        }
      },
    );
  }

  test(
    'R1 cached read completed after deletion cannot return old token',
    () async {
      final secrets = _DelayedCredentialRead();
      secrets.values[_key('subject')] = jsonEncode({
        ...AccessCredentials(
          AccessToken(
            'Bearer',
            'cached',
            DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
          'refresh',
          GoogleOAuthService.scopes,
        ).toJson(),
        'client_id': _configuredGoogle.clientId,
        'registration_id': _configuredGoogle.registrationId,
      });
      secrets.values['google-oauth-credential-index-v2'] = jsonEncode([
        _key('subject'),
      ]);
      final service = GoogleOAuthService(
        configuration: _configuredGoogle,
        secrets: secrets,
      );
      final cleaner = GoogleOAuthService(
        configuration: _configuredGoogle,
        secrets: secrets,
      );
      addTearDown(service.close);
      addTearDown(cleaner.close);
      final result = service
          .validCredentials('subject')
          .then<Object>((v) => v, onError: (Object e) => e);
      await secrets.entered.future;
      await cleaner.removeCredentials('subject');
      secrets.release.complete();
      expect(await result, isA<GoogleOAuthException>());
      expect(secrets.values, isEmpty);
    },
  );

  test('setup retains only allowlisted token-endpoint failure codes', () {
    final rejected = ServerRequestFailedException(
      'synthetic-secret must not reach the UI',
      responseContent: {
        'error': 'invalid_client',
        'error_description': 'synthetic-secret',
      },
    );
    expect(
      GoogleOAuthService.configurationFailureCode(rejected),
      'provider-invalid-client',
    );
    expect(
      GoogleOAuthService.configurationFailureCode(
        ServerRequestFailedException(
          'private response',
          responseContent: {'error': 'synthetic-secret'},
        ),
      ),
      isNull,
    );
  });

  for (final scenario in [
    'wrong-account',
    'retain-refresh',
    'renew-consent',
    'different-client',
    'invalid-issuer',
    'invalid-audience',
    'expired-id-token',
    'nonce-mismatch',
    'invalid-signature',
    'deleted-during-authorization',
  ]) {
    test('authorization credential isolation: $scenario', () async {
      final secrets = _MemorySecrets();
      for (final subject in ['subject-a', 'subject-b']) {
        secrets.values[_key(subject)] = jsonEncode({
          ...AccessCredentials(
            AccessToken('Bearer', 'old-$subject', DateTime.utc(2000)),
            scenario == 'renew-consent' ? null : 'refresh-$subject',
            GoogleOAuthService.scopes,
          ).toJson(),
          'registration_id': _configuredGoogle.registrationId,
          'client_id': scenario == 'different-client'
              ? 'another-client'
              : 'client',
        });
      }
      secrets.values['google-oauth-credential-index-v2'] = jsonEncode([
        _key('subject-a'),
        _key('subject-b'),
      ]);
      final before = Map<String, String>.of(secrets.values);
      final key = JsonWebKey.generate('RS256');
      final keys = JsonWebKeyStore()..addKey(key);
      Uri? authorization;
      final prompts = <String>[];
      var refreshed = false;
      var deletedDuringAuthorization = false;
      final service = GoogleOAuthService(
        configuration: _configuredGoogle,
        secrets: secrets,
        idTokenKeyStore: keys,
        httpClient: MockClient((request) async {
          final form = Uri.splitQueryString(request.body);
          if (form['grant_type'] == 'refresh_token') {
            expect(form['refresh_token'], 'refresh-subject-b');
            refreshed = true;
            return http.Response(
              jsonEncode({
                'access_token': 'refreshed',
                'token_type': 'Bearer',
                'expires_in': 3600,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (scenario == 'deleted-during-authorization' &&
              !deletedDuringAuthorization) {
            deletedDuringAuthorization = true;
            final cleaner = GoogleOAuthService(
              configuration: _configuredGoogle,
              secrets: secrets,
            );
            await cleaner.removeCredentials('subject-b');
            await cleaner.close();
          }
          final token =
              (JsonWebSignatureBuilder()
                    ..jsonContent = {
                      'iss': scenario == 'invalid-issuer'
                          ? 'https://untrusted.invalid'
                          : 'https://accounts.google.com',
                      'sub': 'subject-b',
                      'aud': scenario == 'invalid-audience'
                          ? 'another-client'
                          : 'client',
                      'nonce': scenario == 'nonce-mismatch'
                          ? 'wrong-nonce'
                          : authorization!.queryParameters['nonce'],
                      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                      'exp':
                          DateTime.now()
                              .add(
                                Duration(
                                  hours: scenario == 'expired-id-token'
                                      ? -1
                                      : 1,
                                ),
                              )
                              .millisecondsSinceEpoch ~/
                          1000,
                    }
                    ..addRecipient(
                      scenario == 'invalid-signature'
                          ? JsonWebKey.generate('RS256')
                          : key,
                      algorithm: 'RS256',
                    ))
                  .build()
                  .toCompactSerialization();
          return http.Response(
            jsonEncode({
              'access_token': 'authorized',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'id_token': token,
              'scope': GoogleOAuthService.scopes.join(' '),
              if (prompts.length == 2) 'refresh_token': 'renewed-refresh',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        browserLauncher: (uri) async {
          authorization = uri;
          prompts.add(uri.queryParameters['prompt']!);
          final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
          unawaited(
            http.get(
              redirect.replace(
                queryParameters: {
                  'code': 'code',
                  'state': uri.queryParameters['state']!,
                },
              ),
            ),
          );
          return true;
        },
      );
      addTearDown(service.close);
      if (scenario == 'deleted-during-authorization') {
        await expectLater(
          service.authorize(successPage: 'Done', failurePage: 'Failed'),
          throwsA(isA<GoogleOAuthException>()),
        );
        expect(secrets.values[_key('subject-b')], isNull);
        expect(secrets.values[_key('subject-a')], before[_key('subject-a')]);
        final fresh = await service.authorize(
          successPage: 'Done',
          failurePage: 'Failed',
          forceConsent: true,
          expectedSubject: 'subject-b',
        );
        expect(fresh.credentials.refreshToken, 'renewed-refresh');
        expect(secrets.values[_key('subject-b')], isNotNull);
      } else if (const {
        'invalid-issuer',
        'invalid-audience',
        'expired-id-token',
        'nonce-mismatch',
        'invalid-signature',
      }.contains(scenario)) {
        await expectLater(
          service.authorize(successPage: 'Done', failurePage: 'Failed'),
          throwsA(anything),
        );
        expect(
          secrets.values,
          before,
          reason: 'invalid identity evidence must never persist tokens',
        );
      } else if (scenario == 'wrong-account') {
        await expectLater(
          service.authorize(
            successPage: 'Done',
            failurePage: 'Failed',
            expectedSubject: 'subject-a',
            forceConsent: true,
          ),
          throwsA(
            isA<GoogleOAuthException>().having(
              (e) => e.code,
              'code',
              'wrong-account',
            ),
          ),
        );
        expect(secrets.values, before);
      } else {
        final identity = await service.authorize(
          successPage: 'Done',
          failurePage: 'Failed',
        );
        expect(secrets.values[_key('subject-a')], before[_key('subject-a')]);
        if (scenario == 'retain-refresh') {
          expect(identity.credentials.refreshToken, 'refresh-subject-b');
          expect(prompts, ['select_account']);
          final stored = (jsonDecode(secrets.values[_key('subject-b')]!) as Map)
              .cast<String, dynamic>();
          final expired = AccessCredentials(
            AccessToken('Bearer', 'expired', DateTime.utc(2000)),
            identity.credentials.refreshToken,
            identity.credentials.scopes,
            idToken: identity.credentials.idToken,
          );
          secrets.values[_key('subject-b')] = jsonEncode({
            ...stored,
            ...expired.toJson(),
          });
          expect(
            (await service.validCredentials('subject-b')).accessToken.data,
            'refreshed',
          );
          expect(refreshed, isTrue);
        } else {
          expect(prompts, ['select_account', 'select_account consent']);
          expect(identity.credentials.refreshToken, 'renewed-refresh');
        }
      }
    });
  }

  test(
    'unexpired tokens and deletion are isolated by registration and subject',
    () async {
      final secrets = _MemorySecrets();
      const first = GoogleOAuthConfiguration(
        clientId: 'first',
        clientSecret: 'issued-secret',
      );
      const second = GoogleOAuthConfiguration(
        clientId: 'second',
        clientSecret: 'other-secret',
      );
      String key(GoogleOAuthConfiguration config) =>
          'google-oauth-v2-${config.registrationId}-same-subject';
      final credentials = AccessCredentials(
        AccessToken(
          'Bearer',
          'first-token',
          DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
        'first-refresh',
        GoogleOAuthService.scopes,
      );
      secrets.values[key(first)] = jsonEncode({
        ...credentials.toJson(),
        'client_id': first.clientId,
        'registration_id': first.registrationId,
      });
      secrets.values['google-oauth-credential-index-v2'] = jsonEncode([
        key(first),
      ]);
      var refreshes = 0;
      final firstService = GoogleOAuthService(
        configuration: first,
        secrets: secrets,
      );
      final secondService = GoogleOAuthService(
        configuration: second,
        secrets: secrets,
        httpClient: MockClient((_) async {
          refreshes++;
          throw StateError('no refresh expected');
        }),
      );
      addTearDown(firstService.close);
      addTearDown(secondService.close);
      expect(
        (await firstService.validCredentials('same-subject')).accessToken.data,
        'first-token',
      );
      expect(await secondService.readCredentials('same-subject'), isNull);
      await expectLater(
        secondService.validCredentials('same-subject'),
        throwsA(
          isA<GoogleOAuthException>().having(
            (v) => v.code,
            'code',
            'credentials-missing',
          ),
        ),
      );
      // A stale credential copied to the new namespace must fail before the
      // unexpired access-token shortcut, as well as before refresh.
      secrets.values[key(second)] = secrets.values[key(first)]!;
      await expectLater(
        secondService.validCredentials('same-subject'),
        throwsA(
          isA<GoogleOAuthException>().having(
            (v) => v.code,
            'code',
            'credential-registration-mismatch',
          ),
        ),
      );
      expect(refreshes, 0);
      secrets.values['google-oauth-credential-index-v2'] = jsonEncode([
        key(first),
        key(second),
      ]);
      await secondService.removeCredentials('same-subject');
      expect(secrets.values[key(first)], isNotNull);
      expect(secrets.values[key(second)], isNull);
    },
  );

  test('refresh and authorization serialize their shared credential index', () async {
    final secrets = _PausedIndexSecrets();
    secrets.values[_key('subject-a')] = jsonEncode({
      ...AccessCredentials(
        AccessToken('Bearer', 'expired', DateTime.utc(2000)),
        'refresh-a',
        GoogleOAuthService.scopes,
      ).toJson(),
      'client_id': 'client',
      'registration_id': _configuredGoogle.registrationId,
    });
    secrets.values['google-oauth-credential-index-v2'] = jsonEncode([
      _key('subject-a'),
    ]);
    final key = JsonWebKey.generate('RS256');
    final keys = JsonWebKeyStore()..addKey(key);
    Uri? authorization;
    final authorized = Completer<void>();
    final service = GoogleOAuthService(
      configuration: _configuredGoogle,
      secrets: secrets,
      idTokenKeyStore: keys,
      httpClient: MockClient((request) async {
        final form = Uri.splitQueryString(request.body);
        if (form['grant_type'] == 'refresh_token') {
          return http.Response(
            jsonEncode({
              'access_token': 'refreshed',
              'token_type': 'Bearer',
              'expires_in': 3600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        final token =
            (JsonWebSignatureBuilder()
                  ..jsonContent = {
                    'iss': 'https://accounts.google.com',
                    'sub': 'subject-b',
                    'aud': 'client',
                    'nonce': authorization!.queryParameters['nonce'],
                    'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    'exp':
                        DateTime.now()
                            .add(const Duration(hours: 1))
                            .millisecondsSinceEpoch ~/
                        1000,
                  }
                  ..addRecipient(key, algorithm: 'RS256'))
                .build()
                .toCompactSerialization();
        authorized.complete();
        return http.Response(
          jsonEncode({
            'access_token': 'authorized',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'id_token': token,
            'refresh_token': 'refresh-b',
            'scope': GoogleOAuthService.scopes.join(' '),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      browserLauncher: (uri) async {
        authorization = uri;
        unawaited(
          http.get(
            Uri.parse(uri.queryParameters['redirect_uri']!).replace(
              queryParameters: {
                'code': 'code',
                'state': uri.queryParameters['state']!,
              },
            ),
          ),
        );
        return true;
      },
    );
    addTearDown(service.close);
    final refreshed = service.validCredentials('subject-a');
    await secrets.indexRead.future;
    final newAccount = service.authorize(
      successPage: 'Done',
      failurePage: 'Failed',
    );
    await authorized.future;
    // Let the second callback reach persistence while the first index snapshot
    // is held. Without serialization it writes B, then A overwrites that index.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    secrets.releaseIndex.complete();
    await Future.wait([refreshed, newAccount]);
    expect(jsonDecode(secrets.values['google-oauth-credential-index-v2']!), [
      _key('subject-a'),
      _key('subject-b'),
    ]);
    await service.deleteAllCredentials();
    expect(secrets.values, isEmpty);
  });

  for (final failIndex in [false, true]) {
    test(
      'Google verified refresh rollback retains token and index when ${failIndex ? 'index' : 'token'} write fails',
      () async {
        final secrets = _FailNextWriteSecrets();
        final tokenKey = _key('subject');
        secrets.values[tokenKey] = jsonEncode({
          ...AccessCredentials(
            AccessToken('Bearer', 'old-token', DateTime.utc(2000)),
            'old-refresh',
            GoogleOAuthService.scopes,
          ).toJson(),
          'client_id': _configuredGoogle.clientId,
          'registration_id': _configuredGoogle.registrationId,
        });
        secrets.values['google-oauth-credential-index-v2'] = jsonEncode([
          tokenKey,
        ]);
        final before = Map<String, String>.of(secrets.values);
        secrets.failKey = failIndex
            ? 'google-oauth-credential-index-v2'
            : tokenKey;
        final service = GoogleOAuthService(
          configuration: _configuredGoogle,
          secrets: secrets,
          httpClient: MockClient((request) async {
            expect(request.url.host, 'oauth2.googleapis.com');
            return http.Response(
              jsonEncode({
                'access_token': 'new-token',
                'token_type': 'Bearer',
                'expires_in': 3600,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(service.close);
        await expectLater(
          service.validCredentials('subject'),
          throwsA(isA<GoogleOAuthException>()),
        );
        expect(secrets.values, before);
      },
    );
  }

  test('Google revocation uses only the bound registration token and trusted endpoint', () async {
    final secrets = _MemorySecrets();
    final tokenKey = _key('subject');
    final otherKey = _key('subject', 'other-client');
    secrets.values[tokenKey] = jsonEncode({
      ...AccessCredentials(
        AccessToken('Bearer', 'synthetic-token', DateTime.utc(2030)),
        'synthetic-refresh',
        GoogleOAuthService.scopes,
      ).toJson(),
      'client_id': _configuredGoogle.clientId,
      'registration_id': _configuredGoogle.registrationId,
    });
    secrets.values[otherKey] = 'other-registration';
    secrets.values['google-oauth-credential-index-v2'] = jsonEncode([
      tokenKey,
      otherKey,
    ]);
    final service = GoogleOAuthService(
      configuration: _configuredGoogle,
      secrets: secrets,
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'https://oauth2.googleapis.com/revoke');
        expect(
          Uri.splitQueryString(request.body)['token'],
          'synthetic-refresh',
        );
        return http.Response('', 200);
      }),
    );
    addTearDown(service.close);
    await service.revoke('subject');
    expect(secrets.values[tokenKey], isNull);
    expect(secrets.values[otherKey], 'other-registration');
  });

  test('explicit reset deletes every indexed Google credential', () async {
    final secrets = _MemorySecrets()
      ..values['google-oauth-credential-index-v2'] = jsonEncode([
        _key('subject-a'),
        _key('subject-b'),
      ])
      ..values[_key('subject-a')] = 'credential-a'
      ..values[_key('subject-b')] = 'credential-b';
    final service = GoogleOAuthService(
      configuration: _configuredGoogle,
      secrets: secrets,
    );

    await service.removeCredentials('subject-a');
    expect(secrets.values[_key('subject-a')], isNull);
    expect(jsonDecode(secrets.values['google-oauth-credential-index-v2']!), [
      _key('subject-b'),
    ]);

    await service.deleteAllCredentials();
    expect(secrets.values, isEmpty);
  });

  test(
    'unconfigured Google authorization fails before opening a browser',
    () async {
      var launched = false;
      final service = GoogleOAuthService(
        configuration: const GoogleOAuthConfiguration(clientId: ''),
        browserLauncher: (_) async {
          launched = true;
          return true;
        },
      );

      await expectLater(
        service.authorize(successPage: 'Done', failurePage: 'Failed'),
        throwsA(isA<StateError>()),
      );
      expect(launched, isFalse);
    },
  );

  test('browser authorization uses loopback PKCE, state, and nonce', () async {
    Uri? authorization;
    final callbackResponse = Completer<http.Response>();
    final service = GoogleOAuthService(
      configuration: const GoogleOAuthConfiguration(
        clientId: 'desktop-client.apps.googleusercontent.com',
        clientSecret: 'desktop-client-credential',
      ),
      browserLauncher: (uri) async {
        authorization = uri;
        final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
        unawaited(
          Future<void>(() async {
            final client = http.Client();
            try {
              callbackResponse.complete(
                await client.get(
                  redirect.replace(
                    queryParameters: const {
                      'code': 'authorization-code',
                      'state': 'attacker-state',
                    },
                  ),
                ),
              );
            } finally {
              client.close();
            }
          }),
        );
        return true;
      },
    );

    await expectLater(
      service.authorize(successPage: 'Done', failurePage: 'Failed'),
      throwsA(
        isA<GoogleOAuthException>().having(
          (error) => error.code,
          'code',
          'state-mismatch',
        ),
      ),
    );

    final uri = authorization!;
    final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
    expect(uri.scheme, 'https');
    expect(uri.host, 'accounts.google.com');
    expect(redirect.host, '127.0.0.1');
    expect(redirect.path, '/oauth2/callback');
    expect(redirect.port, greaterThan(0));
    expect(uri.queryParameters['response_type'], 'code');
    expect(uri.queryParameters['code_challenge_method'], 'S256');
    expect(uri.queryParameters['code_challenge'], isNotEmpty);
    expect(uri.queryParameters['state'], isNotEmpty);
    expect(uri.queryParameters['nonce'], isNotEmpty);
    expect(uri.queryParameters['prompt'], 'select_account');
    expect(uri.queryParameters, isNot(contains('client_secret')));
    final response = await callbackResponse.future;
    expect(response.statusCode, 400);
    expect(response.body, contains('Failed'));
    expect(response.body, isNot(contains('Done')));
  });

  test('token exchange sends the issued Desktop client credential', () async {
    Map<String, String>? tokenRequest;
    final service = GoogleOAuthService(
      configuration: const GoogleOAuthConfiguration(
        clientId: 'desktop-client.apps.googleusercontent.com',
        clientSecret: 'desktop-client-credential',
      ),
      httpClient: MockClient((request) async {
        expect(request.url, Uri.parse('https://oauth2.googleapis.com/token'));
        tokenRequest = Uri.splitQueryString(request.body);
        return http.Response(
          jsonEncode({
            'error': 'invalid_request',
            'error_description': 'fixture rejection',
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      }),
      browserLauncher: (uri) async {
        final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
        unawaited(
          http.get(
            redirect.replace(
              queryParameters: {
                'code': 'authorization-code',
                'state': uri.queryParameters['state']!,
              },
            ),
          ),
        );
        return true;
      },
    );

    await expectLater(
      service.authorize(successPage: 'Done', failurePage: 'Failed'),
      throwsA(isA<ServerRequestFailedException>()),
    );

    expect(tokenRequest, isNotNull);
    expect(
      tokenRequest!['client_id'],
      'desktop-client.apps.googleusercontent.com',
    );
    expect(tokenRequest!['client_secret'], 'desktop-client-credential');
    expect(tokenRequest!['code'], 'authorization-code');
    expect(tokenRequest!['code_verifier'], isNotEmpty);
    expect(tokenRequest!['grant_type'], 'authorization_code');
  });

  test(
    'credential refresh sends the issued Desktop client credential',
    () async {
      final secrets = _MemorySecrets();
      secrets.values[_key(
        'subject',
        'desktop-client.apps.googleusercontent.com',
      )] = jsonEncode(
        AccessCredentials(
          AccessToken('Bearer', 'expired', DateTime.utc(2000)),
          'refresh-token',
          GoogleOAuthService.scopes,
        ).toJson()..addAll({
          'client_id': 'desktop-client.apps.googleusercontent.com',
          'registration_id': const GoogleOAuthConfiguration(
            clientId: 'desktop-client.apps.googleusercontent.com',
            clientSecret: 'desktop-client-credential',
          ).registrationId,
        }),
      );
      Map<String, String>? refreshRequest;
      final service = GoogleOAuthService(
        configuration: const GoogleOAuthConfiguration(
          clientId: 'desktop-client.apps.googleusercontent.com',
          clientSecret: 'desktop-client-credential',
        ),
        secrets: secrets,
        httpClient: MockClient((request) async {
          refreshRequest = Uri.splitQueryString(request.body);
          return http.Response(
            jsonEncode({
              'access_token': 'refreshed-access-token',
              'token_type': 'Bearer',
              'expires_in': 3600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final refreshed = await service.validCredentials('subject');

      expect(refreshed.accessToken.data, 'refreshed-access-token');
      expect(
        refreshRequest!['client_id'],
        'desktop-client.apps.googleusercontent.com',
      );
      expect(refreshRequest!['client_secret'], 'desktop-client-credential');
      expect(refreshRequest!['refresh_token'], 'refresh-token');
      expect(refreshRequest!['grant_type'], 'refresh_token');
    },
  );

  test('expired or revoked refresh token requires authorization', () async {
    final secrets = _MemorySecrets();
    secrets.values[_key('subject')] = jsonEncode(
      AccessCredentials(
        AccessToken('Bearer', 'expired', DateTime.utc(2000)),
        'expired-refresh-token',
        GoogleOAuthService.scopes,
      ).toJson()..addAll({
        'client_id': 'client',
        'registration_id': _configuredGoogle.registrationId,
      }),
    );
    final service = GoogleOAuthService(
      configuration: _configuredGoogle,
      secrets: secrets,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': 'invalid_grant',
            'error_description': 'Token has been expired or revoked.',
          }),
          400,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await expectLater(
      service.validCredentials('subject'),
      throwsA(
        isA<GoogleOAuthException>().having(
          (error) => error.code,
          'code',
          'refresh-token-rejected',
        ),
      ),
    );
  });

  test('other refresh endpoint failures retain their classification', () async {
    final secrets = _MemorySecrets();
    secrets.values[_key('subject')] = jsonEncode(
      AccessCredentials(
        AccessToken('Bearer', 'expired', DateTime.utc(2000)),
        'refresh-token',
        GoogleOAuthService.scopes,
      ).toJson()..addAll({
        'client_id': 'client',
        'registration_id': _configuredGoogle.registrationId,
      }),
    );
    final service = GoogleOAuthService(
      configuration: _configuredGoogle,
      secrets: secrets,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'invalid_client'}),
          401,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await expectLater(
      service.validCredentials('subject'),
      throwsA(isA<ServerRequestFailedException>()),
    );
  });

  test(
    'consent is requested only for explicit refresh-token recovery',
    () async {
      Uri? authorization;
      final service = GoogleOAuthService(
        configuration: _configuredGoogle,
        browserLauncher: (uri) async {
          authorization = uri;
          final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
          unawaited(
            http.get(
              redirect.replace(
                queryParameters: const {
                  'error': 'access_denied',
                  'state': 'invalid-for-fixture',
                },
              ),
            ),
          );
          return true;
        },
      );

      await expectLater(
        service.authorize(
          successPage: 'Done',
          failurePage: 'Failed',
          forceConsent: true,
        ),
        throwsA(isA<GoogleOAuthException>()),
      );
      expect(
        authorization!.queryParameters['prompt'],
        'select_account consent',
      );
    },
  );

  test('browser launch failure closes the loopback listener', () async {
    final service = GoogleOAuthService(
      configuration: _configuredGoogle,
      browserLauncher: (_) async => false,
    );

    await expectLater(
      service.authorize(successPage: 'Done', failurePage: 'Failed'),
      throwsA(
        isA<GoogleOAuthException>().having(
          (error) => error.code,
          'code',
          'browser-launch-failed',
        ),
      ),
    );
  });

  test('close drains an active loopback authorization listener', () async {
    final launched = Completer<void>();
    final service = GoogleOAuthService(
      configuration: _configuredGoogle,
      browserLauncher: (_) async {
        launched.complete();
        return true;
      },
    );
    final authorization = service.authorize(
      successPage: 'Done',
      failurePage: 'Failed',
    );
    await launched.future;

    await service.close().timeout(const Duration(seconds: 1));

    await expectLater(
      authorization,
      throwsA(
        isA<GoogleOAuthException>().having(
          (error) => error.code,
          'code',
          'callback-server-closed',
        ),
      ),
    );
    await expectLater(
      service.authorize(successPage: 'Done', failurePage: 'Failed'),
      throwsA(
        isA<GoogleOAuthException>().having(
          (error) => error.code,
          'code',
          'oauth-service-closed',
        ),
      ),
    );
  });
}

class _MemorySecrets implements SecretValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _DelayedCredentialRead extends _MemorySecrets {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool delayed = false;
  @override
  Future<String?> read(String key) async {
    final captured = values[key];
    if (!delayed && key == _key('subject')) {
      delayed = true;
      entered.complete();
      await release.future;
    }
    return captured;
  }
}

class _PausedIndexSecrets extends _MemorySecrets {
  final indexRead = Completer<void>();
  final releaseIndex = Completer<void>();
  @override
  Future<String?> read(String key) async {
    final value = await super.read(key);
    if (key == 'google-oauth-credential-index-v2' && !indexRead.isCompleted) {
      indexRead.complete();
      await releaseIndex.future;
    }
    return value;
  }
}

String _key(String subject, [String clientId = 'client']) =>
    'google-oauth-v2-${GoogleOAuthConfiguration(clientId: clientId, clientSecret: 'desktop-client-credential').registrationId}-$subject';

class _FailNextWriteSecrets extends _MemorySecrets {
  String? failKey;
  @override
  Future<void> write(String key, String value) async {
    if (key == failKey) {
      failKey = null;
      values[key] = 'unverified';
      return;
    }
    return super.write(key, value);
  }
}
