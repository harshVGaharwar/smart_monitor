import 'dart:convert';
import 'package:archive/archive.dart';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/services/cases_file_parser.dart';

const _headers = [
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
];

Uint8List _xlsx(List<List<String>> rows) {
  final book = Excel.createExcel();
  final sheet = book[book.getDefaultSheet()!];
  for (final row in rows) {
    sheet.appendRow([for (final c in row) TextCellValue(c)]);
  }
  return Uint8List.fromList(book.encode()!);
}

void main() {
  test('xlsx: routed row is accepted, unrouted row needs confirmation', () {
    final bytes = _xlsx([
      _headers,
      [
        '4943581',
        'MARVALA RAMESH BABU',
        '50200031339584',
        '5',
        'CAM Expiry Health Check',
        'CAM Expired Beyond 90 Days',
        'LMM',
        'FC',
        'Business Banking',
        '1',
        'ninad.thakur',
        'S41002',
        '2026-07-21',
        'Exception',
        'Renewal pending',
        'Mumbai',
        'CAM Renewal Team',
      ],
      [
        '5120774',
        'SUNRISE POLYMERS',
        '50200044912307',
        '2',
        'LMM vs UBS Mismatch',
        'Account in SNA',
        'LMM',
        'nan',
        '',
        '2',
        '',
        'S41002',
        '',
        '',
        '',
        '',
        '',
      ],
    ]);

    final out = CasesFileParser.parse(fileName: 'cases.xlsx', bytes: bytes);

    expect(out.uploaded, 1);
    expect(out.failed, hasLength(1));
    final row = out.failed.single;
    expect(row.clientId, '5120774');
    expect(row.customerName, 'SUNRISE POLYMERS');
    expect(row.coreSystem, 'nan');
    expect(row.facilitySrNo, '2');
    expect(row.checker, 'S41002');
    expect(row.cpu, isNull);
    expect(row.actionableTeam, isNull);
    // A blank category is no longer silently defaulted to 'Exception' — the
    // report flags it so the user sees what the file actually carried.
    expect(row.exceptionCategory, '');
    expect(row.exceptionValid, isFalse);
    expect(row.errorFields, containsAll(['CPU', 'Actionable Team']));

    // The clean row is kept now, not just counted.
    expect(out.rows, hasLength(2));
    final clean = out.valid.single;
    expect(clean.clientId, '4943581');
    expect(clean.cpu, 'Mumbai');
    // Numbered over data rows, so the first record is 1 and not the header's
    // position in the sheet.
    expect(clean.id, 1);
    expect(row.id, 2);
  });

  test('an unrecognised CPU keeps the file\'s original text', () {
    final bytes = _xlsx([
      _headers,
      [
        '4943581',
        'ACME',
        '50200031339584',
        '5',
        'CAM Expiry Health Check',
        'Sub',
        'LMM',
        'FC',
        'Seg',
        '1',
        'mk',
        'ck',
        '2026-07-21',
        'Exception',
        'Renewal pending',
        'Mumbai West',
        'L1 Support',
      ],
    ]);

    final row = CasesFileParser.parse(
      fileName: 'cases.xlsx',
      bytes: bytes,
    ).failed.single;

    expect(row.cpu, isNull);
    expect(row.cpuRaw, 'Mumbai West');
    expect(row.cpuDisplay, 'Mumbai West');
    expect(row.actionableTeam, isNull);
    expect(row.teamRaw, 'L1 Support');
    // The category did resolve, so it must not be counted against the row.
    expect(row.exceptionValid, isTrue);
    expect(row.errorFields, ['CPU', 'Actionable Team']);
  });

  test('an exception category outside the master list fails validation', () {
    final bytes = _xlsx([
      _headers,
      [
        '4943581',
        'ACME',
        '50200031339584',
        '5',
        'CAM Expiry Health Check',
        'Sub',
        'LMM',
        'FC',
        'Seg',
        '1',
        'mk',
        'ck',
        '2026-07-21',
        'General Exception',
        'Renewal pending',
        'Mumbai',
        'CAM Renewal Team',
      ],
    ]);

    final out = CasesFileParser.parse(fileName: 'cases.xlsx', bytes: bytes);

    expect(out.uploaded, 0);
    final row = out.failed.single;
    expect(row.exceptionCategory, 'General Exception');
    expect(row.exceptionValid, isFalse);
    expect(row.errorFields, ['Exception Category']);

    // Correcting it in the table must clear the row without a re-parse.
    row.exceptionCategory = 'Exception';
    expect(row.hasErrors, isFalse);
    expect(out.uploaded, 1);
  });

  test('csv: parses and matches CPU/team case-insensitively', () {
    final csvText = [
      _headers.join(','),
      '4943581,ACME,50200031339584,5,CAM Expiry Health Check,Sub,LMM,FC,Seg,1,mk,ck,'
          '2026-07-21,Exception,Renewal pending,mumbai,cam renewal team',
    ].join('\n');

    final out = CasesFileParser.parse(
      fileName: 'cases.csv',
      bytes: Uint8List.fromList(utf8.encode(csvText)),
    );

    expect(out.uploaded, 1);
    expect(out.failed, isEmpty);
  });

  test('missing required columns are reported by name', () {
    final bytes = _xlsx([
      ['Client id', 'Customer name'],
      ['1', 'A'],
    ]);

    expect(
      () => CasesFileParser.parse(fileName: 'bad.xlsx', bytes: bytes),
      throwsA(
        isA<CasesFileException>().having(
          (e) => e.message,
          'message',
          allOf(contains('Account no'), contains('CPU')),
        ),
      ),
    );
  });

  _absoluteTargetTests();

  test('date-formatted cells come through as dates, not serial numbers', () {
    final book = Excel.createExcel();
    final sheet = book[book.getDefaultSheet()!];
    sheet.appendRow([for (final h in _headers) TextCellValue(h)]);
    sheet.appendRow([
      TextCellValue('4943581'),
      TextCellValue('ACME'),
      TextCellValue('50200031339584'),
      IntCellValue(5),
      TextCellValue('CAM Expiry Health Check'),
      TextCellValue('Sub'),
      TextCellValue('LMM'),
      TextCellValue('FC'),
      TextCellValue('Seg'),
      IntCellValue(2),
      TextCellValue('mk'),
      TextCellValue('ck'),
      DateCellValue(year: 2026, month: 7, day: 21),
      TextCellValue('Exception'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
    ]);
    final bytes = Uint8List.fromList(book.encode()!);

    final out = CasesFileParser.parse(fileName: 'dates.xlsx', bytes: bytes);
    final row = out.failed.single;
    expect(row.lsSrmDate, '2026-07-21');
    // Integer cells must not gain a trailing ".0".
    expect(row.lineNo, '5');
    expect(row.facilitySrNo, '2');
  });

  test('legacy .xls is rejected with a clear message', () {
    expect(
      () => CasesFileParser.parse(
        fileName: 'old.xls',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(
        isA<CasesFileException>().having(
          (e) => e.message,
          'message',
          contains('.xlsx'),
        ),
      ),
    );
  });
}

// --- Regression: workbooks whose relationship targets are absolute ---------

/// Rewrites `xl/_rels/workbook.xml.rels` so every worksheet Target is an
/// absolute path, reproducing the export shape that crashed the reader.
Uint8List _withAbsoluteRelTargets(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final file in archive.files) {
    if (file.name == 'xl/_rels/workbook.xml.rels') {
      final text = utf8.decode(file.content as List<int>);
      final patched = text.replaceAllMapped(
        RegExp(r'Target="(?!/)([^"]*worksheets/[^"]*)"'),
        (m) => 'Target="/xl/${m[1]}"',
      );
      final data = utf8.encode(patched);
      out.addFile(ArchiveFile(file.name, data.length, data));
    } else {
      out.addFile(ArchiveFile(file.name, file.size, file.content as List<int>));
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(out)!);
}

void _absoluteTargetTests() {
  test('xlsx with absolute relationship targets still parses', () {
    final plain = _xlsx([
      _headers,
      [
        '4943581',
        'ACME',
        '50200031339584',
        '5',
        'CAM Expiry Health Check',
        'Sub',
        'LMM',
        'FC',
        'Seg',
        '1',
        'mk',
        'ck',
        '2026-07-21',
        'Exception',
        'Renewal pending',
        'Mumbai',
        'CAM Renewal Team',
      ],
    ]);
    final patched = _withAbsoluteRelTargets(plain);

    // Sanity: the fixture really does use absolute targets now.
    final rels = utf8.decode(
      ZipDecoder()
              .decodeBytes(patched)
              .findFile('xl/_rels/workbook.xml.rels')!
              .content
          as List<int>,
    );
    expect(rels, contains('Target="/xl/worksheets/'));

    final out = CasesFileParser.parse(fileName: 'cases.xlsx', bytes: patched);
    expect(out.uploaded, 1);
    expect(out.failed, isEmpty);
  });

  test('a non-spreadsheet file fails with a readable message', () {
    expect(
      () => CasesFileParser.parse(
        fileName: 'notes.xlsx',
        bytes: Uint8List.fromList(utf8.encode('this is not a zip')),
      ),
      throwsA(isA<CasesFileException>()),
    );
  });
}
