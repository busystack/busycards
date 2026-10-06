import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'secret_value_store.dart';

class DatabaseKeyStore {
  DatabaseKeyStore({SecretValueStore? secrets, Random? random})
    : _secrets = secrets ?? SecretServiceValueStore(),
      _random = random ?? Random.secure();

  static const _keyName = 'contacts-database-key-v1';

  final SecretValueStore _secrets;
  final Random _random;

  /// Opens the key lifecycle for [database]. A key is provisioned only when
  /// neither encrypted profile artifacts nor a previously provisioned key
  /// exist. A persisted key without a database is reused so a process killed
  /// between key persistence and database creation can resume safely.
  Future<List<int>> openForProfile(File database) async {
    final artifacts = ContactsProfileArtifacts.forDatabase(database);
    final hasArtifacts = await artifacts.anyExists();
    final encoded = await _secrets.read(_keyName);
    if (encoded != null) {
      return _decode(encoded);
    }
    if (hasArtifacts) throw DatabaseKeyMissingException(artifacts);
    return provisionNewProfile(database);
  }

  /// Requires an already provisioned key. This operation never writes.
  Future<List<int>> requireExisting() async {
    final encoded = await _secrets.read(_keyName);
    if (encoded == null) throw const DatabaseKeyMissingException();
    return _decode(encoded);
  }

  /// Provisions a key for a confirmed new profile only.
  Future<List<int>> provisionNewProfile(File database) async {
    final artifacts = ContactsProfileArtifacts.forDatabase(database);
    if (await artifacts.anyExists()) {
      throw DatabaseProfileAlreadyExistsException(artifacts);
    }
    final existing = await _secrets.read(_keyName);
    if (existing != null) return _decode(existing);

    final key = List<int>.generate(32, (_) => _random.nextInt(256));
    final encoded = base64UrlEncode(key);
    await _secrets.write(_keyName, encoded);
    final verified = await _secrets.read(_keyName);
    if (verified != encoded) {
      // Delete first so a backend that performed a partial write cannot leave
      // an unverifiable secret associated with a future profile.
      await _secrets.delete(_keyName);
      throw const DatabaseKeyPersistenceException();
    }
    return key;
  }

  /// Cryptographically invalidates a profile. Callers must stop all database
  /// work before invoking this and delete profile artifacts only afterwards.
  Future<void> deleteForExplicitReset() => _secrets.delete(_keyName);

  Future<void> verifyDeletedForExplicitReset() async {
    if (await _secrets.read(_keyName) != null) {
      throw const DatabaseKeyPersistenceException();
    }
  }

  List<int> _decode(String encoded) {
    try {
      final key = base64Url.decode(encoded);
      if (key.length != 32) throw const FormatException();
      return key;
    } on FormatException {
      throw const DatabaseKeyMalformedException();
    }
  }
}

class ContactsProfileArtifacts {
  ContactsProfileArtifacts(this.paths);

  factory ContactsProfileArtifacts.forDatabase(File database) {
    final path = database.path;
    return ContactsProfileArtifacts([path, '$path-wal', '$path-shm']);
  }

  final List<String> paths;

  Future<List<String>> existing() async {
    final found = <String>[];
    for (final path in paths) {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        found.add(path);
      }
    }
    return found;
  }

  Future<bool> anyExists() async => (await existing()).isNotEmpty;
}

sealed class DatabaseKeyLifecycleException implements Exception {
  const DatabaseKeyLifecycleException(this.safeCode);

  final String safeCode;

  @override
  String toString() => 'DatabaseKeyLifecycleException($safeCode)';
}

class DatabaseKeyMissingException extends DatabaseKeyLifecycleException {
  const DatabaseKeyMissingException([this.artifacts])
    : super('database-key-missing');

  final ContactsProfileArtifacts? artifacts;
}

class DatabaseKeyMalformedException extends DatabaseKeyLifecycleException {
  const DatabaseKeyMalformedException() : super('database-key-malformed');
}

class DatabaseKeyPersistenceException extends DatabaseKeyLifecycleException {
  const DatabaseKeyPersistenceException()
    : super('database-key-persistence-failed');
}

class DatabaseProfileAlreadyExistsException
    extends DatabaseKeyLifecycleException {
  const DatabaseProfileAlreadyExistsException(this.artifacts)
    : super('database-profile-already-exists');

  final ContactsProfileArtifacts artifacts;
}
