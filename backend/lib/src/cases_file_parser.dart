import 'dart:typed_data';

import 'package:backend/src/csv_reader.dart';
import 'package:backend/src/xlsx_reader.dart';

/// Raised when a file cannot be read as a cases upload — wrong format, no
/// header row, or missing required columns.
class CasesFileException implements Exception {
  /// Creates an exception carrying the text shown on the upload card.
  const CasesFileException(this.message);

  /// Why the file was rejected, phrased for the person who uploaded it.
  final String message;

  @override
  String toString() => message;
}

/// Reads an uploaded cases file (.xlsx or .csv) into JSON rows.
///
/// Every data row is returned, clean or not, so the client's validation report
/// can show the whole file. Whether a row is importable is decided on the
/// client against the master data — the user corrects CPU / team / category
/// cells in the results table and the row has to move between "ready" and
/// "needs attention" without another round trip, so this side deliberately
/// does not judge the values it reads.
class CasesFileParser {
  CasesFileParser._();

  /// Column header -> the response key it fills. Required for every file.
  static const _required = <String, String>{
    'clientid': 'client_id',
    'customername': 'customer_name',
    'accountno': 'account_no',
    'lineno': 'line_no',
    'healthcheckcategory': 'health_check_category',
    'subcategory': 'sub_category',
    'supportsystem': 'support_system',
    'coresystem': 'core_system',
    'exceptioncategory': 'exception_category',
    'reason': 'reason',
    'cpu': 'cpu',
    'team': 'team',
    'maker': 'maker',
    'checker': 'checker',
  };

  /// Carried through when the file has them, blank when it does not.
  static const _optional = <String, String>{
    'segment': 'segment',
    'facility': 'facility',
    'facilitysrno': 'sr_no',
    'lssrmdate': 'ls_srm_date',
    'priority': 'priority',
  };

  /// Human-readable names for the required columns, used in the error message
  /// so it names the header the user actually has to add.
  static const _labels = <String, String>{
    'clientid': 'Client id',
    'customername': 'Customer name',
    'accountno': 'Account no',
    'lineno': 'Line no',
    'healthcheckcategory': 'Health Check Category',
    'subcategory': 'Sub category',
    'supportsystem': 'Support system',
    'coresystem': 'Core system',
    'exceptioncategory': 'Exception category',
    'reason': 'Reason',
    'cpu': 'CPU',
    'team': 'Actionable Team',
    'maker': 'Maker',
    'checker': 'Checker',
  };

  /// Accepted spellings for headers whose normalised form varies between
  /// exports, mapped onto the canonical key.
  static const _aliases = <String, String>{
    'healthcheck': 'healthcheckcategory',
    'healthcheckcat': 'healthcheckcategory',
    'actionableteam': 'team',
    'actionteam': 'team',
    'unit': 'cpu',
    'facilitysmo': 'facilitysrno',
    'facilityserialno': 'facilitysrno',
    'srno': 'facilitysrno',
    'lssrmdt': 'lssrmdate',
  };

  /// Reads [bytes] into JSON rows, picking the reader from [extension] —
  /// `xlsx` or `csv`, lowercased and without the dot.
  ///
  /// Throws [CasesFileException] when the file cannot be used at all: an
  /// unreadable workbook, no header, a missing required column, or no data.
  static List<Map<String, dynamic>> parse({
    required String extension,
    required Uint8List bytes,
  }) {
    // Readers can fail with an Error rather than an Exception on malformed
    // input, so everything unexpected is funnelled into CasesFileException.
    List<List<String>> rows;
    try {
      rows = _readRows(extension, bytes);
    } on CasesFileException {
      rethrow;
    } catch (e) {
      throw CasesFileException('The file could not be read: $e');
    }

    if (rows.isEmpty) throw const CasesFileException('The file is empty.');

    final headerIndex = _findHeader(rows);
    if (headerIndex < 0) {
      throw const CasesFileException('No header row found in the file.');
    }

    final header = rows[headerIndex];
    final columns = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      final key = _normalise(header[i]);
      if (key.isEmpty) continue;
      columns[_aliases[key] ?? key] = i;
    }

    final missing = _required.keys
        .where((k) => !columns.containsKey(k))
        .map((k) => _labels[k] ?? k)
        .toList();
    if (missing.isNotEmpty) {
      throw CasesFileException(
        'The file is missing required column(s): ${missing.join(', ')}.',
      );
    }

    final parsed = <Map<String, dynamic>>[];
    for (var i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((c) => c.trim().isEmpty)) continue;

      String cell(String key) {
        final idx = columns[key];
        if (idx == null || idx >= row.length) return '';
        final text = row[idx].trim();
        // Spreadsheet exports routinely carry these as stand-ins for empty.
        if (text == 'null' || text == 'nan') return '';
        return text;
      }

      // No id: the client numbers the rows it displays, and a case is
      // identified by client id / account no / line no everywhere else.
      parsed.add({
        for (final entry in _required.entries) entry.value: cell(entry.key),
        for (final entry in _optional.entries) entry.value: cell(entry.key),
      });
    }

    if (parsed.isEmpty) {
      throw const CasesFileException('The file has no data rows.');
    }
    return parsed;
  }

  /// Locates the header row.
  ///
  /// Exports routinely carry a title or a report date above the real header,
  /// so the first non-empty row is not a safe assumption. The header is taken
  /// to be the first row naming a column this parser recognises — data rows
  /// never do. Failing that it falls back to the first non-empty row, which
  /// then produces the "missing required column(s)" message naming what the
  /// file needs rather than a vaguer complaint.
  static int _findHeader(List<List<String>> rows) {
    for (var i = 0; i < rows.length; i++) {
      final known = rows[i].any((cell) {
        final key = _normalise(cell);
        if (key.isEmpty) return false;
        final canonical = _aliases[key] ?? key;
        return _required.containsKey(canonical) ||
            _optional.containsKey(canonical);
      });
      if (known) return i;
    }
    return rows.indexWhere((r) => r.any((c) => c.trim().isNotEmpty));
  }

  static List<List<String>> _readRows(String extension, Uint8List bytes) {
    switch (extension) {
      case 'csv':
        return CsvReader.read(bytes);
      case 'xlsx':
        try {
          return XlsxReader.readRows(bytes);
        } on XlsxException catch (e) {
          throw CasesFileException(e.message);
        }
      // The old binary .xls format is not a zip archive, so the reader cannot
      // open it — ask for a re-save rather than failing obscurely.
      case 'xls':
        throw const CasesFileException(
          'Legacy .xls files are not supported. Save the file as .xlsx or '
          '.csv and upload it again.',
        );
      default:
        throw CasesFileException(
          extension.isEmpty
              ? 'The upload did not say what type of file it is.'
              : 'Unsupported file type: .$extension',
        );
    }
  }

  static String _normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
}
