import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart' as csv;

import '../data/mock_data.dart';
import '../models/pending_case.dart';
import 'xlsx_reader.dart';

/// Raised when a file cannot be read as a cases upload — wrong format, no
/// header row, or missing required columns.
class CasesFileException implements Exception {
  final String message;
  const CasesFileException(this.message);

  @override
  String toString() => message;
}

/// Reads an uploaded cases file (.xlsx or .csv) into [PendingCase] rows.
///
/// Every data row comes back in [UploadOutcome.rows], clean or not, so the
/// validation report can show the whole file. Whether a row is importable is
/// decided by [PendingCase.hasErrors], which re-checks CPU, actionable team and
/// exception category against the master data each time it is read.
class CasesFileParser {
  CasesFileParser._();

  /// Column header -> normalised key. Required for every row.
  static const _required = <String, String>{
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
    'lssrmdt': 'lssrmdate',
  };

  static UploadOutcome parse({
    required String fileName,
    required Uint8List bytes,
  }) {
    // Readers can fail with an Error rather than an Exception on malformed
    // input, so everything unexpected is funnelled into CasesFileException.
    List<List<String>> rows;
    try {
      rows = _readRows(fileName, bytes);
    } on CasesFileException {
      rethrow;
    } on Object catch (e) {
      throw CasesFileException('The file could not be read: $e');
    }

    if (rows.isEmpty) {
      throw const CasesFileException('The file is empty.');
    }

    // The header is the first row that actually has content — exports often
    // carry a blank or title row above it.
    final headerIndex = rows.indexWhere(
      (r) => r.any((c) => c.trim().isNotEmpty),
    );
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

    final missing = _required.entries
        .where((e) => !columns.containsKey(e.key))
        .map((e) => e.value)
        .toList();
    if (missing.isNotEmpty) {
      throw CasesFileException(
        'The file is missing required column(s): ${missing.join(', ')}.',
      );
    }

    final parsed = <PendingCase>[];

    for (var i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((c) => c.trim().isEmpty)) continue;

      String cell(String key) {
        final idx = columns[key];
        if (idx == null || idx >= row.length) return '';
        return row[idx].trim();
      }

      final cpuRaw = cell('cpu');
      final teamRaw = cell('team');
      final categoryRaw = cell('exceptioncategory');
      final healthCheckRaw = cell('healthcheckcategory');

      parsed.add(
        PendingCase(
          // Numbered over data rows only, so the ID column runs 1, 2, 3 …
          // regardless of where the header sat in the file.
          id: parsed.length + 1,
          clientId: cell('clientid'),
          customerName: cell('customername'),
          accountNo: cell('accountno'),
          lineNo: cell('lineno'),
          subCategory: cell('subcategory'),
          supportSystem: cell('supportsystem'),
          coreSystem: cell('coresystem'),
          segment: cell('segment'),
          facilitySrNo: cell('facilitysrno'),
          maker: cell('maker'),
          checker: cell('checker'),
          lsSrmDate: cell('lssrmdate'),
          // Unrecognised values stay as-is so the report can show what the
          // file said; validity is derived from them, not stored.
          healthCheckCategory:
              _matchOption(healthCheckRaw, MockData.healthCheckCategories) ??
              healthCheckRaw,
          healthCheckCategoryRaw: healthCheckRaw,
          exceptionCategory:
              _matchOption(categoryRaw, MockData.exceptionCategories) ??
              categoryRaw,
          exceptionCategoryRaw: categoryRaw,
          reason: cell('reason'),
          cpu: _matchOption(cpuRaw, MockData.cpus),
          cpuRaw: cpuRaw,
          actionableTeam: _matchOption(teamRaw, MockData.teams),
          teamRaw: teamRaw,
        ),
      );
    }

    if (parsed.isEmpty) {
      throw const CasesFileException('The file has no data rows.');
    }

    return UploadOutcome(rows: parsed);
  }

  // --- Reading ------------------------------------------------------------

  static List<List<String>> _readRows(String fileName, Uint8List bytes) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'csv' => _readCsv(bytes),
      'xlsx' => _readXlsx(bytes),
      // The old binary .xls format is not a zip archive, so the reader cannot
      // open it — ask for a re-save rather than failing obscurely.
      'xls' => throw const CasesFileException(
        'Legacy .xls files are not supported. Save the file as .xlsx or .csv '
        'and upload it again.',
      ),
      _ => throw CasesFileException('Unsupported file type: .$ext'),
    };
  }

  static List<List<String>> _readCsv(Uint8List bytes) {
    late final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } on FormatException {
      throw const CasesFileException('The CSV file could not be decoded.');
    }
    // autoDetect picks up ';' separated exports as well as plain commas.
    final rows = csv.Csv(
      skipEmptyLines: true,
    ).decode(text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
    return [
      for (final row in rows) [for (final cell in row) '${cell ?? ''}'],
    ];
  }

  static List<List<String>> _readXlsx(Uint8List bytes) {
    try {
      return XlsxReader.readRows(bytes);
    } on XlsxException catch (e) {
      throw CasesFileException(e.message);
    }
  }

  // --- Matching -----------------------------------------------------------

  static String _normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Resolves a free-text value onto one of [options], ignoring case and
  /// punctuation. Returns null when the file's value isn't recognised, which
  /// sends the row to the confirmation table.
  static String? _matchOption(String value, List<String> options) {
    if (value.trim().isEmpty) return null;
    final key = _normalise(value);
    for (final opt in options) {
      if (_normalise(opt) == key) return opt;
    }
    return null;
  }
}
