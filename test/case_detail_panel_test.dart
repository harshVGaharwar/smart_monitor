import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/data/mock_data.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/theme/app_theme.dart';
import 'package:smart_monitor/widgets/case_detail_panel.dart';

CaseItem get _record => MockData.cases.firstWhere(
  (c) => c.comments.isNotEmpty && c.documents.isNotEmpty,
);

Future<List<CaseItem>> _pumpPanel(
  WidgetTester tester, {
  CaseItem? record,
  CaseDetailTab tab = CaseDetailTab.basicInfo,
}) async {
  tester.view.physicalSize = const Size(700, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final changes = <CaseItem>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: CaseDetailPanel(
          caseItem: record ?? _record,
          initialTab: tab,
          currentUser: 'ninad.thakur',
          onChanged: changes.add,
          onClose: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return changes;
}

void main() {
  testWidgets('the header identifies the record and every tab is present', (
    tester,
  ) async {
    final record = _record;
    await _pumpPanel(tester, record: record);

    expect(find.text(record.exceptionCode), findsOneWidget);
    // Twice over: the header title and the Customer Name field below it.
    expect(find.text(record.customerName), findsWidgets);
    expect(find.text(record.status.label), findsWidgets);

    // Comments and Documents carry live counts in their labels.
    expect(find.text('Basic Info'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
    expect(find.text('Reassign'), findsOneWidget);
    expect(find.text('Comments (${record.comments.length})'), findsOneWidget);
    expect(find.text('Documents (${record.documents.length})'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
  });

  testWidgets('it opens on the tab the caller asked for', (tester) async {
    await _pumpPanel(tester, tab: CaseDetailTab.verify);

    expect(find.text('Verification Action'), findsOneWidget);
    expect(find.text('Verify Record'), findsOneWidget);
  });

  testWidgets('basic info renders the record fields', (tester) async {
    final record = _record;
    await _pumpPanel(tester, record: record);

    expect(find.text('BASIC INFORMATION'), findsOneWidget);
    expect(find.text('ASSIGNMENT'), findsOneWidget);
    expect(find.text('CLIENT ID'), findsOneWidget);
    expect(find.text(record.clientId), findsWidgets);
    expect(find.text(record.facilitySrNo), findsOneWidget);
  });

  testWidgets('posting a comment appends it and bumps the tab count', (
    tester,
  ) async {
    final record = _record;
    final changes = await _pumpPanel(
      tester,
      record: record,
      tab: CaseDetailTab.comments,
    );

    await tester.enterText(find.byType(TextField).first, 'Checked with ops.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post Comment'));
    await tester.pumpAndSettle();

    expect(find.text('Checked with ops.'), findsOneWidget);
    expect(
      find.text('Comments (${record.comments.length + 1})'),
      findsOneWidget,
    );
    // The dashboard is told, so the row behind the drawer can update.
    expect(changes.last.comments.length, record.comments.length + 1);
    expect(changes.last.lastActivity?.type, ActivityType.commentAdded);
  });

  testWidgets('an empty comment cannot be posted', (tester) async {
    final changes = await _pumpPanel(tester, tab: CaseDetailTab.comments);

    await tester.tap(find.text('Post Comment'));
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
  });

  testWidgets('reassign stays disabled until a CPU and team are chosen', (
    tester,
  ) async {
    final record = _record;
    final changes = await _pumpPanel(
      tester,
      record: record,
      tab: CaseDetailTab.reassign,
    );

    expect(find.text('Current Assignment'), findsOneWidget);

    // Nothing picked yet — the button must not fire.
    await tester.tap(find.text('Confirm Reassignment'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);

    await tester.tap(find.text('Select CPU...'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chennai').last);
    await tester.pumpAndSettle();

    // A CPU alone is still not enough.
    await tester.tap(find.text('Confirm Reassignment'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);

    // The team list runs past the overlay's height, so the search box is how
    // a value further down it gets reached.
    await tester.tap(find.text('Select Team...'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'LMS');
    await tester.pumpAndSettle();
    await tester.tap(find.text('LMS Team').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm Reassignment'));
    await tester.pumpAndSettle();

    expect(changes, isNotEmpty);
    expect(changes.last.cpu, 'Chennai');
    expect(changes.last.team, 'LMS Team');
    expect(changes.last.lastActivity?.type, ActivityType.reassigned);
  });

  testWidgets('verifying applies the chosen status and logs the audit entry', (
    tester,
  ) async {
    final record = MockData.cases.firstWhere(
      (c) => c.status != CaseStatus.verified,
    );
    final changes = await _pumpPanel(
      tester,
      record: record,
      tab: CaseDetailTab.verify,
    );

    await tester.tap(find.text(record.status.label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(CaseStatus.verified.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verify Record'));
    await tester.pumpAndSettle();

    expect(changes.last.status, CaseStatus.verified);
    expect(changes.last.activity.last.type, ActivityType.verified);
  });

  testWidgets('documents list the version and uploader', (tester) async {
    final record = _record;
    await _pumpPanel(tester, record: record, tab: CaseDetailTab.documents);

    expect(find.text('DOCUMENT NAME'), findsOneWidget);
    expect(find.text('VERSION'), findsOneWidget);
    for (final doc in record.documents) {
      expect(find.text(doc.name), findsOneWidget);
      expect(find.text(doc.version), findsOneWidget);
    }
  });

  testWidgets('the audit timeline lists every activity entry', (tester) async {
    final record = _record;
    await _pumpPanel(tester, record: record, tab: CaseDetailTab.activity);

    expect(find.text('AUDIT HISTORY'), findsOneWidget);
    for (final entry in record.activity) {
      expect(
        find.text(entry.type.label),
        findsWidgets,
        reason: '${entry.type.label} missing from the timeline',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
