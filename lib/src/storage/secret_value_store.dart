import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

enum SecretServiceFailureKind { locked, unavailable, storage }

class SecretServiceException implements Exception {
  const SecretServiceException(this.kind, {required this.operation});

  final SecretServiceFailureKind kind;
  final String operation;

  @override
  String toString() =>
      'SecretServiceException(${kind.name}, operation: $operation)';
}

abstract interface class SecretValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// One authorization subsystem/account can be removed without touching other
/// accounts in the same application profile or another BusyStack application.
final class ScopedSecretValueStore implements SecretValueStore {
  const ScopedSecretValueStore(this.parent, this.prefix);
  final SecretValueStore parent;
  final String prefix;
  @override
  Future<String?> read(String key) => parent.read(prefix + key);
  @override
  Future<void> write(String key, String value) =>
      parent.write(prefix + key, value);
  @override
  Future<void> delete(String key) => parent.delete(prefix + key);
}

class SecretServiceValueStore implements SecretValueStore {
  SecretServiceValueStore({
    FlutterSecureStorage? storage,
    this.namespace = 'io.busystack.busycards/default',
  }) : _storage = storage ?? const FlutterSecureStorage();

  static const _linuxOptions = LinuxOptions();
  final FlutterSecureStorage _storage;
  final String namespace;

  @override
  Future<String?> read(String key) => _guard(
    'read',
    () => _storage.read(key: namespace + '/' + key, lOptions: _linuxOptions),
  );

  @override
  Future<void> write(String key, String value) => _guard(
    'write',
    () => _storage.write(
      key: namespace + '/' + key,
      value: value,
      lOptions: _linuxOptions,
    ),
  );

  @override
  Future<void> delete(String key) => _guard(
    'delete',
    () => _storage.delete(key: namespace + '/' + key, lOptions: _linuxOptions),
  );

  Future<T> _guard<T>(String operation, Future<T> Function() action) async {
    try {
      return await action();
    } on MissingPluginException {
      throw SecretServiceException(
        SecretServiceFailureKind.unavailable,
        operation: operation,
      );
    } on PlatformException catch (error) {
      final kind = switch (error.code) {
        'KeyringLocked' => SecretServiceFailureKind.locked,
        'StorageError' => SecretServiceFailureKind.storage,
        _ => SecretServiceFailureKind.unavailable,
      };
      // Platform messages can contain D-Bus names, collection names, or
      // backend diagnostics. Convert to a typed redacted failure here.
      throw SecretServiceException(kind, operation: operation);
    }
  }
}
