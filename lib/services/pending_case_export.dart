import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart' as csv;

import '../models/pending_case.dart';

/// Builds the "Download Error Data" file from rows that failed validation.
///
/// The output carries the same columns the upload expects, so the user can fix
/// the flagged values in Excel and re-upload the file as-is. A trailing
/// `Errors` column names the fields that failed, and the CPU / Actionable Team
/// / Exception Category cells carry whatever the original file said rather
/// than a blank — the point is to show what was rejected.
///
/// CSV rather than a real .xlsx workbook, matching [CaseExport] in
/// `case_export.dart`: Excel opens it natively and it keeps the app free of a
/// spreadsheet-writing dependency.
class PendingCaseExport {
  PendingCaseExport._();

  static const List<String> _headers = [
    'ID',
    'Client id',
    'Customer name',
    'Account no',
    'Line no',
    'Health Check Category',
    'Sub category',
    'Support system',
    'Core system',
    'Segment',
    'Facility Sr. no',
    'Maker',
    'Checker',
    'LS SRM Date',
    'Exception category',
    'Reason',
    'CPU',
    'Actionable Team',
    'Errors',
  ];

  static String buildCsv(List<PendingCase> rows) {
    final table = <List<String>>[
      _headers,
      for (final r in rows)
        [
          r.id == 0 ? '' : '${r.id}',
          r.clientId,
          r.customerName,
          r.accountNo,
          r.lineNo,
          r.healthCheckCategory,
          r.subCategory,
          r.supportSystem,
          r.coreSystem,
          r.segment,
          r.facilitySrNo,
          r.maker,
          r.checker,
          r.lsSrmDate,
          r.exceptionCategory,
          r.reason,
          r.cpuDisplay,
          r.teamDisplay,
          r.errorFields.join('; '),
        ],
    ];
    return csv.Csv(lineDelimiter: '\r\n').encode(table);
  }

  /// UTF-8 with a BOM, so Excel picks up the encoding and renders accented
  /// customer names correctly instead of mojibake.
  static Uint8List buildCsvBytes(List<PendingCase> rows) {
    return Uint8List.fromList([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(buildCsv(rows)),
    ]);
  }

  static String fileName([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'health-check-errors-${d.year}${two(d.month)}${two(d.day)}-'
        '${two(d.hour)}${two(d.minute)}.csv';
  }
}
