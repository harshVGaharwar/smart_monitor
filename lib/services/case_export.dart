import 'dart:convert';
import 'dart:typed_data';

import '../models/case_item.dart';
import 'csv_writer.dart';

/// Builds the "Export Excel" download from the rows currently on screen.
///
/// The output is CSV rather than a real .xlsx workbook — Excel opens it
/// natively, and it keeps the export free of a spreadsheet-writing dependency.
/// Swap [buildCsv] for a workbook encoder if formatting is ever needed.
class CaseExport {
  CaseExport._();

  static const List<String> _headers = [
    'Exception code',
    'Client id',
    'Customer name',
    'Account no',
    'Line no',
    'Health check category',
    'Sub category',
    'Exception category',
    'Reason',
    'CPU',
    'Team',
    'Status',
    'Priority',
    'Assigned by',
    'Segment',
    'Facility Sr. no',
    'Maker',
    'Checker',
    'Last activity',
    'Updated',
  ];

  static String buildCsv(List<CaseItem> cases) {
    final rows = <List<String>>[
      _headers,
      for (final c in cases)
        [
          c.exceptionCode,
          c.clientId,
          c.customerName,
          c.accountNo,
          c.lineNo,
          c.healthCheckCategory,
          c.subCategory,
          c.exceptionCategory,
          c.reason,
          c.cpu,
          c.team,
          c.status.label,
          c.priority,
          c.assignedBy,
          c.segment,
          c.srNo,
          c.maker,
          c.checker,
          c.lastActivity?.type.label ?? '',
          c.updatedNote,
        ],
    ];
    return CsvWriter.encode(rows);
  }

  /// UTF-8 with a BOM, so Excel picks up the encoding and renders accented
  /// customer names correctly instead of mojibake.
  static Uint8List buildCsvBytes(List<CaseItem> cases) {
    return Uint8List.fromList([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(buildCsv(cases)),
    ]);
  }

  static String fileName([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'health-check-${d.year}${two(d.month)}${two(d.day)}-'
        '${two(d.hour)}${two(d.minute)}.csv';
  }
}
