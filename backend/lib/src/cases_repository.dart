import 'package:sqlite3/sqlite3.dart';

/// What a call to [CasesRepository.importRows] did.
class ImportResult {
  /// Creates a result splitting [inserted] new rows from [updated] existing.
  const ImportResult({required this.inserted, required this.updated});

  /// Rows that were not in the table before.
  final int inserted;

  /// Rows that matched an existing case and overwrote it.
  final int updated;

  /// Everything the submit persisted, however it landed.
  int get total => inserted + updated;

  /// The JSON the client reads to report what the submit did.
  Map<String, dynamic> toJson() => {
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
    'facility_sr_no',
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
        status TEXT NOT NULL DEFAULT 'Pending',
        imported_at TEXT NOT NULL,
        PRIMARY KEY (client_id, account_no, line_no)
      )
    ''');
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
      'SELECT 1 FROM cases WHERE client_id = ? AND account_no = ? '
      'AND line_no = ? LIMIT 1',
    );
    final upsert = _db.prepare('''
      INSERT INTO cases (${_columns.join(', ')}, imported_at)
      VALUES ($placeholders, ?)
      ON CONFLICT (client_id, account_no, line_no) DO UPDATE SET
        $assignments,
        imported_at = excluded.imported_at
    ''');

    var inserted = 0;
    var updated = 0;
    final now = DateTime.now().toUtc().toIso8601String();

    _db.execute('BEGIN');
    try {
      for (final row in rows) {
        final values = [for (final c in _columns) _text(row[c])];
        final wasThere = existing.select([
          _text(row['client_id']),
          _text(row['account_no']),
          _text(row['line_no']),
        ]).isNotEmpty;

        upsert.execute([...values, now]);
        if (wasThere) {
          updated++;
        } else {
          inserted++;
        }
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      existing.close();
      upsert.close();
    }

    return ImportResult(inserted: inserted, updated: updated);
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

  /// Releases the database handle.
  void close() => _db.close();

  static const _naturalKey = {'client_id', 'account_no', 'line_no'};

  /// Everything is stored as text — the upload has no types to preserve, and
  /// an account number must never be rounded into a double.
  static String _text(Object? value) => value == null ? '' : '$value'.trim();
}
