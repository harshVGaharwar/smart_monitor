import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Thrown when a workbook cannot be opened or contains no readable sheet.
class XlsxException implements Exception {
  final String message;
  const XlsxException(this.message);

  @override
  String toString() => message;
}

/// Minimal .xlsx reader: pulls the first populated worksheet out as rows of
/// display text.
///
/// Written against the raw package parts rather than a workbook library
/// because real-world exports vary in ways those libraries assert on — notably
/// relationship targets written as absolute paths ("/xl/worksheets/sheet1.xml"),
/// which is handled here by [_resolveTarget].
class XlsxReader {
  XlsxReader._();

  /// Number formats that are dates in every workbook.
  static const _builtinDateFormats = <int>{
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    45,
    46,
    47,
  };

  static List<List<String>> readRows(Uint8List bytes) {
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const XlsxException(
        'The file could not be opened as a spreadsheet. Make sure it is a '
        'valid .xlsx workbook.',
      );
    }

    final workbook = _xml(archive, 'xl/workbook.xml');
    if (workbook == null) {
      throw const XlsxException('The workbook is missing its index.');
    }

    final rels = _relationships(archive);
    final sharedStrings = _sharedStrings(archive);
    final dateStyles = _dateStyles(archive);
    final epoch1904 = workbook
        .findAllElements('workbookPr')
        .any(
          (e) =>
              e.getAttribute('date1904') == '1' ||
              e.getAttribute('date1904') == 'true',
        );

    final sheets = workbook.findAllElements('sheet').toList();
    if (sheets.isEmpty) {
      throw const XlsxException('The workbook has no sheets.');
    }

    for (final sheet in sheets) {
      final rid = sheet.getAttribute('r:id') ?? sheet.getAttribute('id');
      final path = _resolveTarget(archive, rels[rid]);
      if (path == null) continue;

      final doc = _xml(archive, path);
      if (doc == null) continue;

      final rows = _readSheet(doc, sharedStrings, dateStyles, epoch1904);
      if (rows.any((r) => r.any((c) => c.trim().isNotEmpty))) return rows;
    }

    throw const XlsxException('The workbook has no populated sheet.');
  }

  // --- Package parts ------------------------------------------------------

  static XmlDocument? _xml(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(file.content as List<int>));
    } on Object {
      return null;
    }
  }

  static Map<String, String> _relationships(Archive archive) {
    final doc = _xml(archive, 'xl/_rels/workbook.xml.rels');
    if (doc == null) return {};
    return {
      for (final node in doc.findAllElements('Relationship'))
        if (node.getAttribute('Id') != null &&
            node.getAttribute('Target') != null)
          node.getAttribute('Id')!: node.getAttribute('Target')!,
    };
  }

  /// Maps a relationship target onto an actual entry in the archive.
  ///
  /// Targets appear as "worksheets/sheet1.xml" (relative to xl/),
  /// "/xl/worksheets/sheet1.xml" (absolute) or "../xl/worksheets/sheet1.xml";
  /// each candidate is tried before giving up.
  static String? _resolveTarget(Archive archive, String? target) {
    if (target == null || target.isEmpty) return null;
    final clean = target.replaceAll('\\', '/');
    final bare = clean
        .replaceFirst(RegExp(r'^/+'), '')
        .replaceAll(RegExp(r'^(\.\./)+'), '');

    for (final candidate in {clean, bare, 'xl/$bare'}) {
      final normalised = candidate.replaceFirst(RegExp(r'^/+'), '');
      if (archive.findFile(normalised) != null) return normalised;
    }

    // Last resort: match on file name alone.
    final name = bare.split('/').last;
    for (final file in archive.files) {
      if (file.name.endsWith('/$name')) return file.name;
    }
    return null;
  }

  static List<String> _sharedStrings(Archive archive) {
    final doc = _xml(archive, 'xl/sharedStrings.xml');
    if (doc == null) return const [];
    return [
      for (final si in doc.findAllElements('si'))
        si.findAllElements('t').map((t) => t.innerText).join(),
    ];
  }

  /// Style indices whose number format renders as a date.
  static Set<int> _dateStyles(Archive archive) {
    final doc = _xml(archive, 'xl/styles.xml');
    if (doc == null) return const {};

    final customDateFormats = <int>{};
    for (final fmt in doc.findAllElements('numFmt')) {
      final id = int.tryParse(fmt.getAttribute('numFmtId') ?? '');
      final code = fmt.getAttribute('formatCode');
      if (id == null || code == null) continue;
      // Strip literal sections before looking for date tokens.
      final stripped = code.replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]'), '');
      if (RegExp(r'[ymdhs]').hasMatch(stripped.toLowerCase())) {
        customDateFormats.add(id);
      }
    }

    final cellXfs = doc.findAllElements('cellXfs').firstOrNull;
    if (cellXfs == null) return const {};

    final dateStyles = <int>{};
    final xfs = cellXfs.findElements('xf').toList();
    for (var i = 0; i < xfs.length; i++) {
      final id = int.tryParse(xfs[i].getAttribute('numFmtId') ?? '');
      if (id == null) continue;
      if (_builtinDateFormats.contains(id) || customDateFormats.contains(id)) {
        dateStyles.add(i);
      }
    }
    return dateStyles;
  }

  // --- Sheet --------------------------------------------------------------

  static List<List<String>> _readSheet(
    XmlDocument doc,
    List<String> sharedStrings,
    Set<int> dateStyles,
    bool epoch1904,
  ) {
    final rows = <List<String>>[];

    for (final row in doc.findAllElements('row')) {
      final cells = <int, String>{};
      var maxIndex = -1;

      for (final cell in row.findElements('c')) {
        final index = _columnIndex(cell.getAttribute('r'));
        if (index == null) continue;
        final text = _cellText(cell, sharedStrings, dateStyles, epoch1904);
        if (text.isNotEmpty) {
          cells[index] = text;
          if (index > maxIndex) maxIndex = index;
        }
      }

      rows.add([for (var i = 0; i <= maxIndex; i++) cells[i] ?? '']);
    }

    return rows;
  }

  /// Zero-based column index from a cell reference such as "AB12".
  static int? _columnIndex(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    var index = 0;
    var seen = false;
    for (final unit in ref.toUpperCase().codeUnits) {
      if (unit < 65 || unit > 90) break; // past the letters
      index = index * 26 + (unit - 64);
      seen = true;
    }
    return seen ? index - 1 : null;
  }

  static String _cellText(
    XmlElement cell,
    List<String> sharedStrings,
    Set<int> dateStyles,
    bool epoch1904,
  ) {
    final type = cell.getAttribute('t');

    if (type == 'inlineStr') {
      return cell.findAllElements('t').map((t) => t.innerText).join().trim();
    }

    final raw = cell.findElements('v').firstOrNull?.innerText;
    if (raw == null || raw.isEmpty) return '';

    switch (type) {
      case 's':
        final index = int.tryParse(raw);
        if (index == null || index >= sharedStrings.length) return '';
        return sharedStrings[index].trim();
      case 'b':
        return raw == '1' ? 'TRUE' : 'FALSE';
      case 'e':
        return raw.trim();
      case 'd':
        return raw.trim();
      case 'str':
        return raw.trim();
    }

    // Untyped cells are numeric; a date number format makes them a date.
    final number = double.tryParse(raw);
    if (number == null) return raw.trim();

    final styleIndex = int.tryParse(cell.getAttribute('s') ?? '');
    if (styleIndex != null && dateStyles.contains(styleIndex)) {
      return _fmtSerialDate(number, epoch1904);
    }

    // Whole numbers should not pick up a trailing ".0".
    if (number == number.roundToDouble() && number.abs() < 1e15) {
      return '${number.round()}';
    }
    return raw.trim();
  }

  /// Converts an Excel serial date to text. The 1900 epoch is offset by two
  /// days: one for the 1-based count and one for Excel's phantom 1900-02-29.
  static String _fmtSerialDate(double serial, bool epoch1904) {
    final base = epoch1904 ? DateTime(1904, 1, 1) : DateTime(1899, 12, 30);
    final whole = serial.floor();
    final fraction = serial - whole;
    final date = base.add(
      Duration(
        days: whole,
        milliseconds: (fraction * Duration.millisecondsPerDay).round(),
      ),
    );

    String two(int v) => v.toString().padLeft(2, '0');
    final ymd = '${date.year}-${two(date.month)}-${two(date.day)}';
    if (date.hour == 0 && date.minute == 0 && date.second == 0) return ymd;
    return '$ymd ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }
}
