import 'package:sqlite3/sqlite3.dart';

/// The discussion thread on a case.
///
/// Kept apart from `CasesRepository`: a case is one row that gets overwritten
/// by every import, and a comment is an event that must survive them. They
/// share the database file, nothing else.
class CommentsRepository {
  /// Opens (and migrates) the database at [path].
  ///
  /// Pass `:memory:` for a throwaway database, which is what the tests use.
  CommentsRepository(String path) : _db = sqlite3.open(path) {
    _migrate();
  }

  final Database _db;

  void _migrate() {
    _db
      ..execute('''
        CREATE TABLE IF NOT EXISTS comments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          client_id TEXT NOT NULL,
          user_id TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT '',
          comments TEXT NOT NULL,
          support_document TEXT NOT NULL DEFAULT '',
          reason TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL
        )
      ''')
      // The thread is always read by client, and a case can collect a long
      // one.
      ..execute(
        'CREATE INDEX IF NOT EXISTS comments_client '
        'ON comments (client_id, id)',
      );

    // Both of these were added after the table shipped. SQLite has no
    // `ADD COLUMN IF NOT EXISTS` and re-adding one is an error rather than a
    // no-op, so a database from before them is asked first. Of the document
    // only the name is kept — nothing here serves the bytes back.
    final columns = {
      for (final row in _db.select("PRAGMA table_info('comments')"))
        row['name'] as String,
    };
    for (final column in ['support_document', 'reason']) {
      if (columns.contains(column)) continue;
      _db.execute(
        "ALTER TABLE comments ADD COLUMN $column TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  /// Writes one comment and reads it back as stored.
  ///
  /// The stamp is the server's, not the caller's: a client clock that is
  /// minutes out would order the thread wrongly for everyone else.
  Map<String, dynamic> add({
    required String clientId,
    required String userId,
    required String role,
    required String comments,
    String supportDocument = '',
    String reason = '',
  }) {
    _db.execute(
      'INSERT INTO comments (client_id, user_id, role, comments, '
      'support_document, reason, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        clientId,
        userId,
        role,
        comments,
        supportDocument,
        // Only a reassignment has one; it stays blank on every other note.
        reason,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    return _select('WHERE id = ?', [_db.lastInsertRowId]).single;
  }

  /// The whole thread on [clientId], oldest first.
  ///
  /// Not narrowed to whoever is asking: the point of the thread is that the
  /// other side of the handover reads it. Who asked is recorded by the route's
  /// request log, not by hiding rows from them.
  List<Map<String, dynamic>> forClient(String clientId) =>
      _select('WHERE client_id = ?', [clientId]);

  /// Every note on [clientId] that carried a file, oldest first.
  ///
  /// Documents have no table of their own: one only ever arrives attached to a
  /// note or a reassignment, and its name is already on that row. Reading them
  /// back out is therefore a filter on the thread rather than a second store to
  /// keep in step with it.
  List<Map<String, dynamic>> documentsForClient(String clientId) =>
      _select("WHERE client_id = ? AND support_document != ''", [clientId]);

  /// What each case's thread amounts to: how many notes, and the last one.
  ///
  /// One query for the whole grid rather than one per row — the dashboard reads
  /// a queue, and a per-case round trip would be a select per row on every
  /// refresh.
  ///
  /// Keyed by client id, which is how a case is addressed everywhere a comment
  /// is concerned. Cases nobody has written on are simply absent, and the
  /// caller reads that as a count of zero.
  Map<String, ({int count, String lastMessage, String lastAt})>
  summaryByClient() {
    // The last note is the one with the highest id: the thread is ordered by
    // it everywhere else, and two notes in the same second would tie on the
    // stamp alone.
    final result = _db.select('''
      SELECT c.client_id AS client_id,
             COUNT(*) AS n,
             (SELECT comments FROM comments
               WHERE client_id = c.client_id ORDER BY id DESC LIMIT 1) AS last,
             (SELECT created_at FROM comments
               WHERE client_id = c.client_id ORDER BY id DESC LIMIT 1) AS at
        FROM comments c
       GROUP BY c.client_id
    ''');
    return {
      for (final row in result)
        '${row['client_id']}': (
          count: row['n'] as int,
          lastMessage: '${row['last'] ?? ''}',
          lastAt: '${row['at'] ?? ''}',
        ),
    };
  }

  List<Map<String, dynamic>> _select(String where, List<Object?> values) {
    final result = _db.select(
      'SELECT id, client_id, user_id, role, comments, support_document, '
      'reason, created_at FROM comments $where ORDER BY id',
      values,
    );
    return [
      for (final row in result) {for (final key in row.keys) key: row[key]},
    ];
  }

  /// How many comments are stored, across every case.
  int count() =>
      _db.select('SELECT COUNT(*) AS n FROM comments').first['n'] as int;

  /// Releases the database handle.
  void close() => _db.close();
}
