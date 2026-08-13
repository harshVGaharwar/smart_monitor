import 'package:backend/src/role_queue.dart';
import 'package:sqlite3/sqlite3.dart';

/// What a call to [CasesRepository.importRows] did.
class ImportResult {
  /// Creates a result splitting [inserted] new rows from [updated] existing.
  const ImportResult({
    required this.inserted,
    required this.updated,
    this.rows = const [],
  });

  /// Rows that were not in the table before.
  final int inserted;

  /// Rows that matched an existing case and overwrote it.
  final int updated;

  /// The cases as they now stand, read back after the write.
  ///
  /// What is stored rather than what was posted: aliases resolved, blanks
  /// normalised, and the status the row ended up with — which is not always
  /// the one that came in, since a submit that states none keeps the status
  /// the case already had.
  final List<Map<String, dynamic>> rows;

  /// Everything the submit persisted, however it landed.
  int get total => inserted + updated;
}

/// Stores imported health-check cases.
///
/// SQLite because it needs no server to stand up alongside this one and the
/// file is trivial to back up or inspect; the schema is plain enough to move
/// to Postgres later if the deployment calls for it.
class CasesRepository {
  /// Opens (and migrates) the database at [path].
  ///
  /// Pass `:memory:` for a throwaway database, which is what the tests use.
  CasesRepository(String path) : _db = sqlite3.open(path) {
    _migrate();
  }

  final Database _db;

  /// Columns carried straight from the upload, in a fixed order so the insert
  /// statement and the row binding cannot drift apart.
  static const _columns = <String>[
    'client_id',
    'customer_name',
    'account_no',
    'line_no',
    'health_check_category',
    'sub_category',
    'support_system',
    'core_system',
    'segment',
    'facility',
    'sr_no',
    'maker',
    'checker',
    'ls_srm_date',
    'exception_category',
    'reason',
    'cpu',
    'team',
    // Written when a record is routed on, not by the import: who handed it over
    // and when. An upload file carries neither.
    'assigned_by',
    'assigned_date',
    // Carried from the upload when the file states one, blank when it does not.
    'priority',
  ];

  void _migrate() {
    // A case is identified by the client, the account and the line within it,
    // so that triple is the key outright — re-submitting a corrected file has
    // to update those rows rather than stack a second copy alongside the
    // first. No surrogate id: nothing refers to a case by one, and carrying it
    // would only invite two rows for the same real-world case.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS cases (
        ${_columns.map((c) => '$c TEXT NOT NULL DEFAULT ""').join(',\n        ')},
        status TEXT NOT NULL DEFAULT '$_defaultStatus',
        imported_at TEXT NOT NULL,
        PRIMARY KEY (client_id, account_no, line_no)
      )
    ''');

    // CREATE TABLE IF NOT EXISTS does nothing to a table that already exists,
    // so a database written before a column was added would still be missing
    // it — and every insert against it would fail. Adding what is absent
    // keeps an existing cases.db usable across a column change instead of
    // asking whoever is running this to delete the file.
    final existing = {
      for (final row in _db.select('PRAGMA table_info(cases)'))
        row['name'] as String,
    };
    for (final column in _columns) {
      if (existing.contains(column)) continue;
      _db.execute('ALTER TABLE cases ADD COLUMN $column TEXT NOT NULL '
          'DEFAULT ""');
    }
  }

  /// Writes [rows] to the table, overwriting any case already there under the
  /// same client / account / line.
  ///
  /// The whole submit is one transaction: a half-written import would leave
  /// the user unable to tell what still needs re-uploading.
  ImportResult importRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const ImportResult(inserted: 0, updated: 0);

    final placeholders = List.filled(_columns.length, '?').join(', ');
    final assignments = _columns
        .where((c) => !_naturalKey.contains(c))
        .map(
          // A blank cell must not erase a column the file does not carry. The
          // rule the status has always had (see below), applied to the columns
          // an upload has nothing to say about: a re-submitted file would
          // otherwise wipe who a record was routed to and when, which is the
          // server's own record of the handover rather than the file's.
          (c) =>
              _keptWhenBlank.contains(c)
                  ? "$c = CASE WHEN excluded.$c = '' THEN cases.$c "
                      'ELSE excluded.$c END'
                  : '$c = excluded.$c',
        )
        .join(', ');

    final existing = _db.prepare(
      'SELECT status FROM cases WHERE client_id = ? AND account_no = ? '
      'AND line_no = ? LIMIT 1',
    );
    // Read back rather than echo the input: the caller reports what is stored,
    // and the two differ whenever a row leaned on an alias or kept a status it
    // did not state.
    final stored = _db.prepare(
      'SELECT ${_columns.join(', ')}, status, imported_at FROM cases '
      'WHERE client_id = ? AND account_no = ? AND line_no = ? LIMIT 1',
    );
    final upsert = _db.prepare('''
      INSERT INTO cases (${_columns.join(', ')}, status, imported_at)
      VALUES ($placeholders, ?, ?)
      ON CONFLICT (client_id, account_no, line_no) DO UPDATE SET
        $assignments,
        status = excluded.status,
        imported_at = excluded.imported_at
    ''');

    var inserted = 0;
    var updated = 0;
    final saved = <Map<String, dynamic>>[];
    final now = DateTime.now().toUtc().toIso8601String();

    _db.execute('BEGIN');
    try {
      for (final row in rows) {
        final values = [for (final c in _columns) _valueFor(row, c)];
        final prior = existing.select([
          _text(row['client_id']),
          _text(row['account_no']),
          _text(row['line_no']),
        ]);
        final wasThere = prior.isNotEmpty;

        // A row that states no status must not overwrite one. An upload file
        // never carries a status, so writing blindly would send a case the
        // reviewer had already moved on straight back to the default.
        final incoming = _text(row['status']);
        final status = incoming.isNotEmpty
            ? incoming
            : (wasThere
                  ? _text(prior.first['status'], fallback: _defaultStatus)
                  : _defaultStatus);

        upsert.execute([...values, status, now]);
        if (wasThere) {
          updated++;
        } else {
          inserted++;
        }

        final written = stored.select([
          _text(row['client_id']),
          _text(row['account_no']),
          _text(row['line_no']),
        ]);
        for (final result in written) {
          saved.add({for (final key in result.keys) key: result[key]});
        }
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      existing.close();
      stored.close();
      upsert.close();
    }

    return ImportResult(inserted: inserted, updated: updated, rows: saved);
  }

  /// Every stored case, newest import first.
  List<Map<String, dynamic>> allCases() {
    final result = _db.select(
      'SELECT ${_columns.join(', ')}, status, imported_at '
      'FROM cases ORDER BY imported_at DESC, client_id, account_no, line_no',
    );
    return [
      for (final row in result) {for (final key in row.keys) key: row[key]},
    ];
  }

  /// One user's queue: the cases in [status] whose [ownerColumn] carries
  /// [employeeCode]. Ordered as [allCases].
  ///
  /// Both halves matter. The status alone is everything waiting on that side of
  /// the handover, which is the whole team's work rather than this person's.
  ///
  /// Compared case-insensitively: the code arrives from the sign-in service and
  /// the column was written from a spreadsheet, and `OFF807292` and `off807292`
  /// are the same officer.
  List<Map<String, dynamic>> casesForOwner({
    required String status,
    required String ownerColumn,
    required String employeeCode,
  }) {
    // SQLite cannot bind a column name, so this one is interpolated. It is safe
    // because it never comes from the request: the only values that reach here
    // are the two `queueForRole` names, and the assert holds anyone adding a
    // third to that rule.
    assert(
      ownerColumns.contains(ownerColumn),
      '$ownerColumn is not an owner column',
    );

    final result = _db.select(
      'SELECT ${_columns.join(', ')}, status, imported_at FROM cases '
      'WHERE status = ? COLLATE NOCASE AND $ownerColumn = ? COLLATE NOCASE '
      'ORDER BY imported_at DESC, client_id, account_no, line_no',
      [status, employeeCode],
    );
    return [
      for (final row in result) {for (final key in row.keys) key: row[key]},
    ];
  }

  /// Moves every case on [clientId] to [status], and reports how many rows
  /// that was.
  ///
  /// The whole client, because a client id is all a verification carries — the
  /// reviewer acted on a record, and the row it belongs to is the server's to
  /// find. The count is the answer: a client nobody stored moves nothing and
  /// says 0, which is not an error, just nothing to do.
  ///
  /// [from] narrows it to rows in that status. Each side of the handover only
  /// moves a record out of its own queue, so an approval cannot drag a
  /// finished case back into the maker's grid, and the count reports what
  /// actually moved rather than what was asked for.
  ///
  /// Both are matched case-insensitively, as everything read against a client
  /// id here is.
  int setStatusForClient({
    required String clientId,
    required String status,
    String? from,
  }) {
    _db.execute(
      'UPDATE cases SET status = ? WHERE client_id = ? COLLATE NOCASE'
      '${from == null ? '' : ' AND status = ? COLLATE NOCASE'}',
      [status, clientId, if (from != null) from],
    );
    return _db.updatedRows;
  }

  /// Hands every case on [clientId] to [cpu] and [team], and moves it to
  /// [status]; how many rows that was.
  ///
  /// The three together, because a reassignment is one act: a case that
  /// changed hands but kept its old status would sit in the wrong queue under
  /// the right team.
  ///
  /// [from] narrows it the same way [setStatusForClient] does — a reviewer
  /// routes a record out of their own queue and no other.
  /// [assignedBy] is who routed it. Stamped with the server's clock rather than
  /// the caller's, for the reason the comment thread is: a client clock minutes
  /// out would order the handover wrongly for everyone reading it after.
  int reassignForClient({
    required String clientId,
    required String cpu,
    required String team,
    required String status,
    required String assignedBy,
    String? from,
  }) {
    _db.execute(
      'UPDATE cases SET cpu = ?, team = ?, status = ?, '
      'assigned_by = ?, assigned_date = ? '
      'WHERE client_id = ? COLLATE NOCASE'
      '${from == null ? '' : ' AND status = ? COLLATE NOCASE'}',
      [
        cpu,
        team,
        status,
        assignedBy,
        DateTime.now().toUtc().toIso8601String(),
        clientId,
        if (from != null) from,
      ],
    );
    return _db.updatedRows;
  }

  /// How many cases are stored.
  int count() =>
      _db.select('SELECT COUNT(*) AS n FROM cases').first['n'] as int;

  /// Writes [rows] only when the table is empty, and reports how many landed.
  ///
  /// For seeding a fresh database with sample cases: an empty table means
  /// nobody has imported anything yet, so there is nothing to overwrite. Once
  /// a single real case exists this does nothing, so a seeded row can be
  /// deleted or replaced and will not reappear on the next restart.
  int seedIfEmpty(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty || count() > 0) return 0;
    return importRows(rows).total;
  }

  /// Releases the database handle.
  void close() => _db.close();

  static const _naturalKey = {'client_id', 'account_no', 'line_no'};

  /// Columns an import leaves alone when it states nothing for them.
  ///
  /// The first two are written by a reassignment, never by a file. The third
  /// comes from the file, but a later upload that drops the column is silence
  /// rather than an instruction to clear it.
  static const _keptWhenBlank = {'assigned_by', 'assigned_date', 'priority'};

  /// Older spellings still accepted on input, per column.
  ///
  /// The wire format names the facility's serial number `sr_no`, which is what
  /// the UAT service calls it; this app posted `facility_sr_no` before that
  /// was known. Both land in the same column, so a client that has not been
  /// rebuilt keeps working.
  static const _aliases = <String, List<String>>{
    'sr_no': ['facility_sr_no', 'facility_smo'],
  };

  /// The value for [column] in [row], falling back to the column's aliases.
  static String _valueFor(Map<String, dynamic> row, String column) {
    final direct = _text(row[column]);
    if (direct.isNotEmpty) return direct;
    for (final alias in _aliases[column] ?? const <String>[]) {
      final value = _text(row[alias]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Where a case sits before anyone has reviewed it.
  static const _defaultStatus = 'Pending with CPU';

  /// Everything is stored as text — the upload has no types to preserve, and
  /// an account number must never be rounded into a double.
  static String _text(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = '$value'.trim();
    return text.isEmpty ? fallback : text;
  }
}
