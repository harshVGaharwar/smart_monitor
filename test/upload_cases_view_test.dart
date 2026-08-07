import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/pending_case.dart';
import 'package:smart_monitor/services/pending_case_export.dart';
import 'package:smart_monitor/widgets/upload_cases_view.dart';

/// The rows an upload response yields: one clean, and one whose CPU and team
/// the master data rejects.
///
/// Built directly rather than parsed from a file — the server does the parsing
/// now, so what is under test here is [UploadOutcome] and the error export.
UploadOutcome _outcome() {
  return UploadOutcome(
    rows: [
      PendingCase(
        id: 1,
        clientId: '4943581',
        customerName: 'ACME',
        accountNo: '50200031339584',
        lineNo: '5',
        healthCheckCategory: 'CAM Expiry Health Check',
        subCategory: 'Sub',
        supportSystem: 'LMM',
        coreSystem: 'FC',
        segment: 'Retail',
        facilitySrNo: '1',
        maker: 'mk',
        checker: 'ck',
        lsSrmDate: '2026-07-21',
        exceptionCategory: 'Exception',
        reason: 'Renewal pending',
        cpu: 'Mumbai',
        actionableTeam: 'Cam Renewal Team',
      ),
      PendingCase(
        id: 2,
        clientId: '5120774',
        customerName: 'SUNRISE',
        accountNo: '50200044912307',
        lineNo: '2',
        healthCheckCategory: 'LMM vs UBS Mismatch',
        subCategory: 'SNA',
        supportSystem: 'LMM',
        coreSystem: '',
        segment: 'SME',
        facilitySrNo: '2',
        maker: 'mk',
        checker: 'ck',
        lsSrmDate: '2026-07-22',
        exceptionCategory: 'Exception',
        reason: 'Pending',
        // Unresolved against the master data, so the row lands in the report
        // carrying what the file said.
        cpu: null,
        cpuRaw: 'Mumbai West',
        actionableTeam: null,
        teamRaw: 'L1 Support',
      ),
    ],
  );
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
      final out = _outcome();

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
      final out = _outcome();
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
      final out = _outcome();
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
      final out = _outcome();
      expect(out.failed, hasLength(1));

      out.removeRow(out.failed.single);

      expect(out.failed, isEmpty);
      // The clean row survives and is still what gets imported.
      expect(out.uploaded, 1);
      expect(out.valid.single.clientId, '4943581');
    });

    test('error export carries the rejected values and the reasons', () {
      final out = _outcome();
      final csv = PendingCaseExport.buildCsv(out.failed);

      expect(csv, contains('Mumbai West'));
      expect(csv, contains('L1 Support'));
      expect(csv, contains('CPU; Actionable Team'));
      // Header plus the single error row, and the clean row left out.
      expect(csv.trim().split('\r\n'), hasLength(2));
      expect(csv, isNot(contains('ACME')));
    });

    test('the export is BOM-prefixed so Excel reads it as UTF-8', () {
      final out = _outcome();
      final bytes = PendingCaseExport.buildCsvBytes(out.failed);

      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(
        PendingCaseExport.fileName(DateTime(2026, 8, 4, 9, 5)),
        'health-check-errors-20260804-0905.csv',
      );
    });
  });
}
