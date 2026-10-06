import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:busystack_contacts/busystack_contacts.dart';
import 'package:sqlite3/sqlite3.dart';

/// BusyCards-owned SQLCipher store. Every cursor, record, draft and mutation
/// shares one durable transaction; no unencrypted contacts side database.
final class ContactsDatabase implements ContactsStore {
  ContactsDatabase._(this._database);
  static Future<ContactsDatabase> open(File file, List<int> key) async {
    if (key.length != 32)
      throw ArgumentError('A 256-bit profile key is required');
    await file.parent.create(recursive: true);
    if (Platform.isLinux) {
      final result = await Process.run('chmod', ['700', file.parent.path]);
      if (result.exitCode != 0)
        throw StateError('Profile permissions could not be set');
    }
    final database = sqlite3.open(file.path);
    try {
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      database.execute('PRAGMA key = "x\'' + hex + '\'"');
      if (database.select('PRAGMA cipher_version').isEmpty) {
        throw StateError('This build must use SQLCipher');
      }
      database.select('SELECT count(*) FROM sqlite_master'); // Verify the key.
      database.execute('PRAGMA foreign_keys=ON');
      database.execute('PRAGMA journal_mode=WAL');
      database.execute('PRAGMA synchronous=FULL');
      database.execute('PRAGMA temp_store=MEMORY');
      database.execute('PRAGMA secure_delete=ON');
      database.execute('PRAGMA busy_timeout=5000');
      final version =
          database.select('PRAGMA user_version').first.values.first as int;
      if (version > 1)
        throw StateError('Profile was written by a newer BusyCards');
      database.execute('BEGIN IMMEDIATE');
      try {
        database.execute(
          'CREATE TABLE IF NOT EXISTS accounts(id TEXT PRIMARY KEY, data TEXT NOT NULL)',
        );
        database.execute(
          'CREATE TABLE IF NOT EXISTS sources(id TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, data TEXT NOT NULL)',
        );
        database.execute(
          'CREATE TABLE IF NOT EXISTS contacts(id TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, source TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE, name TEXT NOT NULL, search TEXT NOT NULL, data TEXT NOT NULL, projection TEXT NOT NULL, seen TEXT)',
        );
        database.execute(
          'CREATE INDEX IF NOT EXISTS contacts_source_name ON contacts(source,name,id)',
        );
        database.execute(
          'CREATE INDEX IF NOT EXISTS contacts_account_name ON contacts(account,name,id)',
        );
        database.execute(
          'CREATE INDEX IF NOT EXISTS contacts_name_order ON contacts(name COLLATE NOCASE,id)',
        );
        database.execute(
          'CREATE INDEX IF NOT EXISTS contacts_source_order ON contacts(source,name COLLATE NOCASE,id)',
        );
        database.execute(
          'CREATE INDEX IF NOT EXISTS contacts_account_order ON contacts(account,name COLLATE NOCASE,id)',
        );
        database.execute(
          'CREATE VIRTUAL TABLE IF NOT EXISTS contact_search USING fts5(id UNINDEXED, search, tokenize="unicode61 remove_diacritics 2")',
        );
        database.execute(
          'CREATE TRIGGER IF NOT EXISTS contact_search_delete AFTER DELETE ON contacts BEGIN DELETE FROM contact_search WHERE rowid=old.rowid; END',
        );
        database.execute(
          'CREATE TABLE IF NOT EXISTS mutations(id TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, source TEXT NOT NULL, data TEXT NOT NULL)',
        );
        database.execute(
          'CREATE INDEX IF NOT EXISTS mutations_account ON mutations(account,source)',
        );
        database.execute(
          'CREATE TABLE IF NOT EXISTS sync_state(source TEXT PRIMARY KEY REFERENCES sources(id) ON DELETE CASCADE, data TEXT NOT NULL)',
        );
        database.execute(
          'CREATE TABLE IF NOT EXISTS drafts(id TEXT PRIMARY KEY, source TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE, data TEXT NOT NULL)',
        );
        database.execute('PRAGMA user_version=1');
        database.execute('COMMIT');
      } catch (_) {
        database.execute('ROLLBACK');
        rethrow;
      }
      if (Platform.isLinux) await Process.run('chmod', ['600', file.path]);
      return ContactsDatabase._(database);
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  final Database _database;
  final _changes = StreamController<void>.broadcast();
  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closed = false;
  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<T> read<T>(Future<T> Function(ContactsReadTransaction) action) =>
      _enqueue<T, ContactsReadTransaction>(action, false);
  @override
  Future<T> write<T>(Future<T> Function(ContactsWriteTransaction) action) =>
      _enqueue<T, ContactsWriteTransaction>(action, true);

  Future<T> _enqueue<T, Transaction extends ContactsReadTransaction>(
    Future<T> Function(Transaction) action,
    bool writable,
  ) {
    if (_closeFuture != null || _closed) {
      return Future<T>.error(StateError('Contacts database closed'));
    }
    final result = Completer<T>();
    // The serialization gate must stay independent of a caller's test/UI zone.
    // A paused zone must not strand an already-open SQL transaction or block
    // unrelated shutdown work behind it.
    final done = Zone.root.run(Completer<void>.new);
    final previous = _tail;
    _tail = done.future;
    unawaited(
      Zone.root.run(() async {
        await previous;
        final tx = _Transaction(_database, writable);
        _database.execute(writable ? 'BEGIN IMMEDIATE' : 'BEGIN');
        try {
          final value = await action(tx as Transaction);
          _database.execute('COMMIT');
          if (writable) _changes.add(null);
          result.complete(value);
        } catch (error, stackTrace) {
          _database.execute('ROLLBACK');
          result.completeError(error, stackTrace);
        } finally {
          tx.active = false;
          done.complete();
        }
      }),
    );
    return result.future;
  }

  @override
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final closing = Zone.root.run(_close);
    _closeFuture = closing;
    return closing;
  }

  Future<void> _close() async {
    await _tail;
    _closed = true;
    _database.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    _database.close();
    await _changes.close();
  }
}

final class _Transaction implements ContactsWriteTransaction {
  _Transaction(this.db, this.writable);
  final Database db;
  final bool writable;
  bool active = true;
  void _check({bool write = false}) {
    if (!active || write && !writable)
      throw StateError('Invalid transaction access');
  }

  List<T> _list<T>(
    String sql,
    T Function(Map<String, dynamic>) decode, [
    List<Object?> parameters = const [],
  ]) {
    _check();
    return db
        .select(sql, parameters)
        .map((row) => decode((jsonDecode(row['data'] as String) as Map).cast()))
        .toList();
  }

  T? _one<T>(
    String table,
    String column,
    String id,
    T Function(Map<String, dynamic>) decode,
  ) => _list('SELECT data FROM ' + table + ' WHERE ' + column + '=?', decode, [
    id,
  ]).firstOrNull;
  @override
  Future<List<ContactAccount>> accounts() async =>
      _list('SELECT data FROM accounts ORDER BY id', ContactAccount.fromJson);
  @override
  Future<ContactAccount?> account(String id) async =>
      _one('accounts', 'id', id, ContactAccount.fromJson);
  @override
  Future<List<ContactSource>> sources({String? accountId}) async => _list(
    'SELECT data FROM sources' +
        (accountId == null ? '' : ' WHERE account=?') +
        ' ORDER BY id',
    ContactSource.fromJson,
    accountId == null ? [] : [accountId],
  );
  @override
  Future<ContactSource?> source(String key) async =>
      _one('sources', 'id', key, ContactSource.fromJson);
  @override
  Future<ContactRecord?> contact(ContactIdentity identity) async =>
      _one('contacts', 'id', identity.key, contactRecordFromJson);
  (String, List<Object?>) _filter(
    String? account,
    String? source,
    String query,
  ) {
    final clauses = <String>[], parameters = <Object?>[];
    if (account != null) {
      clauses.add('account=?');
      parameters.add(account);
    }
    if (source != null) {
      clauses.add('source=?');
      parameters.add(source);
    }
    if (query.trim().isNotEmpty) {
      final terms = query
          .trim()
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .map((s) => '"' + s.replaceAll('"', '""') + '"*')
          .join(' AND ');
      clauses.add(
        'rowid IN (SELECT rowid FROM contact_search WHERE contact_search MATCH ?)',
      );
      parameters.add(terms);
    }
    return (
      clauses.isEmpty ? '' : ' WHERE ' + clauses.join(' AND '),
      parameters,
    );
  }

  String _orderedTable(String? account, String? source) =>
      'contacts INDEXED BY ' +
      (source != null
          ? 'contacts_source_order'
          : account != null
          ? 'contacts_account_order'
          : 'contacts_name_order');
  @override
  Future<List<ContactRecord>> contacts({
    String? accountId,
    String? sourceKey,
    String query = '',
    int limit = 100,
    int offset = 0,
  }) async {
    if (limit < 0 || limit > 1000 || offset < 0 || query.length > 1024)
      throw ArgumentError('Bounded search required');
    final filter = _filter(accountId, sourceKey, query);
    return _list(
      'SELECT data FROM ' +
          _orderedTable(accountId, sourceKey) +
          filter.$1 +
          ' ORDER BY name COLLATE NOCASE,id LIMIT ? OFFSET ?',
      contactRecordFromJson,
      [...filter.$2, limit, offset],
    );
  }

  @override
  Future<List<ContactProjection>> projections({
    String? accountId,
    String? sourceKey,
    String query = '',
    int limit = 100,
    int offset = 0,
  }) async {
    if (limit < 0 || limit > 1000 || offset < 0 || query.length > 1024)
      throw ArgumentError('Bounded search required');
    final filter = _filter(accountId, sourceKey, query);
    return _list(
      'SELECT projection AS data FROM ' +
          _orderedTable(accountId, sourceKey) +
          filter.$1 +
          ' ORDER BY name COLLATE NOCASE,id LIMIT ? OFFSET ?',
      ContactProjection.fromJson,
      [...filter.$2, limit, offset],
    );
  }

  @override
  Future<int> count({
    String? accountId,
    String? sourceKey,
    String query = '',
  }) async {
    if (query.length > 1024) throw ArgumentError('Bounded search required');
    _check();
    final filter = _filter(accountId, sourceKey, query);
    return db
            .select(
              'SELECT count(*) AS total FROM contacts' + filter.$1,
              filter.$2,
            )
            .first['total']
        as int;
  }

  @override
  Future<List<ContactMutation>> mutations({
    String? accountId,
    String? sourceKey,
  }) async {
    final clauses = <String>[], args = <Object?>[];
    if (accountId != null) {
      clauses.add('account=?');
      args.add(accountId);
    }
    if (sourceKey != null) {
      clauses.add('source=?');
      args.add(sourceKey);
    }
    return _list(
      'SELECT data FROM mutations' +
          (clauses.isEmpty ? '' : ' WHERE ' + clauses.join(' AND ')) +
          ' ORDER BY id',
      ContactMutation.fromJson,
      args,
    );
  }

  @override
  Future<ContactSyncState?> syncState(String sourceKey) async =>
      _one('sync_state', 'source', sourceKey, ContactSyncState.fromJson);
  @override
  Future<List<ContactDraft>> drafts() async =>
      _list('SELECT data FROM drafts ORDER BY id', ContactDraft.fromJson);
  void _put(String table, Map<String, Object?> columns, String keyColumn) {
    _check(write: true);
    final keys = columns.keys.toList();
    db.execute(
      'INSERT INTO ' +
          table +
          '(' +
          keys.join(',') +
          ') VALUES(' +
          List.filled(keys.length, '?').join(',') +
          ') ON CONFLICT(' +
          keyColumn +
          ') DO UPDATE SET ' +
          keys
              .where((key) => key != keyColumn)
              .map((key) => key + '=excluded.' + key)
              .join(','),
      columns.values.toList(),
    );
  }

  @override
  Future<void> putAccount(ContactAccount account) async => _put('accounts', {
    'id': account.id,
    'data': jsonEncode(account.toJson()),
  }, 'id');
  @override
  Future<void> putSource(ContactSource source) async => _put('sources', {
    'id': source.key,
    'account': source.accountId,
    'data': jsonEncode(source.toJson()),
  }, 'id');
  @override
  Future<void> putContact(ContactRecord contact, {String? seenScan}) async {
    final identity = contact.identity;
    final source = jsonEncode([
      identity.accountId,
      identity.provider.name,
      identity.sourceId,
    ]);
    _put('contacts', {
      'id': identity.key,
      'account': identity.accountId,
      'source': source,
      'name': contact.projection.displayName,
      'search': contact.projection.searchText,
      'data': jsonEncode(contact.toJson()),
      'projection': jsonEncode({
        ...contact.projection.toJson(),
        'notes': '',
        'addresses': <Object>[],
        'dates': <Object>[],
        'urls': <Object>[],
        'photo': contact.projection.photo == null
            ? null
            : {...contact.projection.photo!.toJson(), 'embedded': null},
      }),
      'seen': seenScan,
    }, 'id');
    db.execute(
      'DELETE FROM contact_search WHERE rowid=(SELECT rowid FROM contacts WHERE id=?)',
      [identity.key],
    );
    db.execute(
      'INSERT INTO contact_search(rowid,id,search) SELECT rowid,id,search FROM contacts WHERE id=?',
      [identity.key],
    );
  }

  @override
  Future<void> deleteContact(ContactIdentity identity) async {
    _check(write: true);
    db.execute('DELETE FROM contacts WHERE id=?', [identity.key]);
  }

  @override
  Future<void> pruneUnseen(
    String sourceKey,
    String scanId,
    Set<String> protectedIdentities,
  ) async {
    _check(write: true);
    // Parameters stay bounded even when many pending records are protected.
    final rows = db.select(
      'SELECT id FROM contacts WHERE source=? AND (seen IS NULL OR seen<>?)',
      [sourceKey, scanId],
    );
    for (final row in rows) {
      if (!protectedIdentities.contains(row['id']))
        db.execute('DELETE FROM contacts WHERE id=?', [row['id']]);
    }
  }

  @override
  Future<void> putMutation(ContactMutation mutation) async =>
      _put('mutations', {
        'id': mutation.id,
        'account': mutation.accountId,
        'source': mutation.sourceKey,
        'data': jsonEncode(mutation.toJson()),
      }, 'id');
  @override
  Future<void> deleteMutation(String id) async {
    _check(write: true);
    db.execute('DELETE FROM mutations WHERE id=?', [id]);
  }

  @override
  Future<void> putSyncState(ContactSyncState state) async => _put(
    'sync_state',
    {'source': state.sourceKey, 'data': jsonEncode(state.toJson())},
    'source',
  );
  @override
  Future<void> putDraft(ContactDraft draft) async => _put('drafts', {
    'id': draft.id,
    'source': draft.sourceKey,
    'data': jsonEncode(draft.toJson()),
  }, 'id');
  @override
  Future<void> deleteDraft(String id) async {
    _check(write: true);
    db.execute('DELETE FROM drafts WHERE id=?', [id]);
  }

  @override
  Future<void> removeAccount(String id) async {
    _check(write: true);
    db.execute('DELETE FROM accounts WHERE id=?', [id]);
  }

  @override
  Future<void> removeSource(String key) async {
    _check(write: true);
    db.execute('DELETE FROM mutations WHERE source=?', [key]);
    db.execute('DELETE FROM sources WHERE id=?', [key]);
  }
}
