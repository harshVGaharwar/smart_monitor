import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/services/cases_file_parser.dart';
import 'package:smart_monitor/services/pending_case_export.dart';
import 'package:smart_monitor/widgets/upload_cases_view.dart';

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

/// One clean row and one whose CPU and team the master data will reject.
Uint8List _csv() {
  final text = [
    _headers.join(','),
    '4943581,ACME,50200031339584,5,CAM Expiry Health Check,Sub,LMM,FC,Retail,1,mk,ck,'
        '2026-07-21,Exception,Renewal pending,Mumbai,CAM Renewal Team',
    '5120774,SUNRISE,50200044912307,2,LMM vs UBS Mismatch,SNA,LMM,nan,SME,2,mk,ck,'
        '2026-07-22,Exception,Pending,Mumbai West,L1 Support',
  ].join('\n');
  return Uint8List.fromList(utf8.encode(text));
}

void main() {
  testWidgets('idle screen shows the dropzone and the validated fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UploadCasesView())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Upload Document'), findsOneWidget);
    expect(find.text('Upload Health Check Excel'), findsOneWidget);
    expect(find.text('.xlsx · .xls · .csv · Max 25 MB'), findsOneWidget);
    expect(
      find.text(
        'Drag & drop your Excel file or browse to upload Health Check '
        'exception records for validation.',
      ),
      findsOneWidget,
    );

    expect(find.text('VALIDATED FIELDS'), findsOneWidget);
    for (final field in [
      'Health Check Category',
      'Exception Category',
      'CPU',
      'Actionable Team',
    ]) {
      expect(find.text(field), findsOneWidget, reason: '$field pill missing');
    }
    expect(
      find.text(
        'These fields are checked against the master database. All other '
        'columns are imported as-is from the Excel file.',
      ),
      findsOneWidget,
    );

    // The column contract is folded away, not dropped.
    expect(
      find.text('Columns required in the file for each case'),
      findsNothing,
    );
  });

  testWidgets('the required columns are still reachable behind the tile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UploadCasesView())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View required columns'));
    await tester.pumpAndSettle();

    // The existing validation copy has to carry over word for word.
    expect(
      find.text('Columns required in the file for each case'),
      findsOneWidget,
    );
    expect(find.text('Additional columns'), findsOneWidget);
    for (final col in [
      'Client id',
      'Customer name',
      'Account no',
      'Line no',
      'Sub category',
      'Support system',
      'Core system',
      'Exception category',
      'Reason',
      'Maker',
      'Checker',
      'Segment',
      'Facility Sr. no',
      'LS SRM Date',
    ]) {
      expect(find.text(col), findsOneWidget, reason: '$col bullet missing');
    }
    // The validated fields are each both a pill and a required-column bullet.
    for (final field in ['Health Check Category', 'CPU', 'Actionable Team']) {
      expect(find.text(field), findsNWidgets(2), reason: field);
    }
  });

  testWidgets('disposing an idle view does not build the ticker late', (
    tester,
  ) async {
    // Regression: a lazily-created AnimationController used to be constructed
    // from inside dispose() when the view never reached the validating stage.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UploadCasesView())),
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('parsed outcome', () {
    test('splits clean and flagged rows for the stats strip', () {
      final out = CasesFileParser.parse(fileName: 'c.csv', bytes: _csv());

      expect(out.processed, 2);
      expect(out.uploaded, 1);
      expect(out.failed, hasLength(1));
      // Processed must always reconcile with what the strip shows.
      expect(out.uploaded + out.failed.length, out.processed);

      // Correcting the flagged row moves it across, live.
      final bad = out.failed.single;
      bad.cpu = 'Kolkata';
      bad.actionableTeam = 'LMS Team';
      expect(out.uploaded, 2);
      expect(out.failed, isEmpty);
    });

    test('a removed row leaves the outcome and is never submitted', () {
      final out = CasesFileParser.parse(fileName: 'c.csv', bytes: _csv());
      final clean = out.valid.single;

      expect(out.removeRow(clean), 0);

      // What submit uploads is outcome.valid, so a removed row cannot reach it.
      expect(out.valid, isEmpty);
      expect(out.rows, hasLength(1));
      expect(out.processed, 1);
      expect(out.removed, 1);

      // Removing the last row leaves nothing to import at all.
      out.removeRow(out.rows.single);
      expect(out.rows, isEmpty);
      expect(out.removed, 2);
      expect(out.uploaded, 0);
    });

    test('undo puts a removed row back where it was', () {
      final out = CasesFileParser.parse(fileName: 'c.csv', bytes: _csv());
      final first = out.rows.first;

      final index = out.removeRow(first);
      out.restore(index, first);

      expect(out.rows.first, same(first));
      expect(out.processed, 2);
      // The counter has to unwind too, or the strip keeps claiming a removal.
      expect(out.removed, 0);
      expect(out.uploaded, 1);
    });

    test('removing a flagged row clears the error it contributed', () {
      final out = CasesFileParser.parse(fileName: 'c.csv', bytes: _csv());
      expect(out.failed, hasLength(1));

      out.removeRow(out.failed.single);

      expect(out.failed, isEmpty);
      // The clean row survives and is still what gets imported.
      expect(out.uploaded, 1);
      expect(out.valid.single.clientId, '4943581');
    });

    test('error export carries the rejected values and the reasons', () {
      final out = CasesFileParser.parse(fileName: 'c.csv', bytes: _csv());
      final csv = PendingCaseExport.buildCsv(out.failed);

      expect(csv, contains('Mumbai West'));
      expect(csv, contains('L1 Support'));
      expect(csv, contains('CPU; Actionable Team'));
      // Header plus the single error row, and the clean row left out.
      expect(csv.trim().split('\r\n'), hasLength(2));
      expect(csv, isNot(contains('ACME')));
    });

    test('the export is BOM-prefixed so Excel reads it as UTF-8', () {
      final out = CasesFileParser.parse(fileName: 'c.csv', bytes: _csv());
      final bytes = PendingCaseExport.buildCsvBytes(out.failed);

      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(
        PendingCaseExport.fileName(DateTime(2026, 8, 4, 9, 5)),
        'health-check-errors-20260804-0905.csv',
      );
    });
  });
}
