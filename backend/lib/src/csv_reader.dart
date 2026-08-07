import 'dart:convert';
import 'dart:typed_data';

/// Minimal RFC 4180 CSV reader.
///
/// Hand-rolled rather than taken from a package so the server is not pinned to
/// a Dart SDK floor by its CSV dependency — the same constraint that pushed
/// the writer in the Flutter app to be hand-rolled.
class CsvReader {
  CsvReader._();

  /// Decodes [bytes] into rows of raw cell text.
  ///
  /// A UTF-8 BOM is stripped, and malformed bytes are replaced rather than
  /// thrown on, because exports out of Excel are routinely mis-encoded and a
  /// mojibake cell is more useful to the user than a rejected file.
  static List<List<String>> read(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    // Normalise line endings so the state machine only handles '\n'.
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return parse(text, delimiter: _detectDelimiter(text));
  }

  /// Semicolon-separated exports are common wherever the decimal separator is
  /// a comma, so the delimiter is sniffed from the header line rather than
  /// assumed.
  static String _detectDelimiter(String text) {
    final firstLine = text.split('\n').first;
    var commas = 0;
    var semicolons = 0;
    var inQuotes = false;
    for (final unit in firstLine.codeUnits) {
      if (unit == 0x22) {
        inQuotes = !inQuotes;
      } else if (!inQuotes && unit == 0x2C) {
        commas++;
      } else if (!inQuotes && unit == 0x3B) {
        semicolons++;
      }
    }
    return semicolons > commas ? ';' : ',';
  }

  /// Splits [text] on [delimiter], honouring quoted fields — which may contain
  /// the delimiter, newlines, and doubled quotes.
  static List<List<String>> parse(String text, {String delimiter = ','}) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var sawAnyChar = false;

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];

      if (inQuotes) {
        if (ch == '"') {
          // A doubled quote inside a quoted field is a literal quote.
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
        continue;
      }

      if (ch == '"') {
        inQuotes = true;
        sawAnyChar = true;
      } else if (ch == delimiter) {
        row.add(field.toString());
        field.clear();
        sawAnyChar = true;
      } else if (ch == '\n') {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
        sawAnyChar = false;
      } else {
        field.write(ch);
        sawAnyChar = true;
      }
    }

    // A file not ending in a newline still has a final row to flush.
    if (sawAnyChar || field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }

    // Drop rows that are entirely empty — trailing blank lines mostly.
    return [
      for (final r in rows)
        if (r.any((c) => c.trim().isNotEmpty)) r,
    ];
  }
}
