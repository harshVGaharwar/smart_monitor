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

  /// The JSON the client reads to report what the submit did.
  Map<String, dynamic> toJson() => {
    'rows': rows,
    'inserted': inserted,
    'updated': updated,
    'total': total,
  };
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
        .map((c) => '$c = excluded.$c')
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
