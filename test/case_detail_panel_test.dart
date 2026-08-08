import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/data/mock_data.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/theme/app_theme.dart';
import 'package:smart_monitor/widgets/case_detail_panel.dart';

/// A backend that accepts any write, so the panel's own behaviour is what
/// these tests exercise rather than the transport.
CaseApi _okApi() => CaseApi(
  ApiClient(
    client: MockClient(
      (_) async => http.Response(jsonEncode({'updated': 1}), 200),
    ),
  ),
);

CaseItem get _record => MockData.cases.firstWhere(
  (c) => c.comments.isNotEmpty && c.documents.isNotEmpty,
);

Future<List<CaseItem>> _pumpPanel(
  WidgetTester tester, {
  CaseItem? record,
  CaseDetailTab tab = CaseDetailTab.basicInfo,
  CaseApi? api,
  VoidCallback? onClose,
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
          onClose: onClose ?? () {},
          api: api ?? _okApi(),
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
    expect(find.text(record.srNo), findsOneWidget);
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
    final record = MockData.cases.first;
    final changes = await _pumpPanel(
      tester,
      record: record,
      tab: CaseDetailTab.verify,
    );

    // A record carrying a legacy status opens on the first assignable one,
    // since the older statuses can no longer be chosen.
    await tester.tap(find.text(CaseStatus.pendingWithCpu.label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(CaseStatus.pendingWithHealthChecker.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verify Record'));
    await tester.pumpAndSettle();

    expect(changes.last.status, CaseStatus.pendingWithHealthChecker);
    expect(changes.last.activity.last.type, ActivityType.verified);
  });

  testWidgets('a successful verify closes the panel, a failed one does not', (
    tester,
  ) async {
    var closes = 0;
    await _pumpPanel(
      tester,
      record: MockData.cases.first,
      tab: CaseDetailTab.verify,
      onClose: () => closes++,
    );

    await tester.tap(find.text('Verify Record'));
    await tester.pumpAndSettle();
    expect(closes, 1, reason: 'the drawer stayed open after verifying');

    final failing = CaseApi(
      ApiClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode({'message': 'Nope.'}), 503),
        ),
      ),
    );
    var failedCloses = 0;
    await _pumpPanel(
      tester,
      record: MockData.cases.first,
      tab: CaseDetailTab.verify,
      api: failing,
      onClose: () => failedCloses++,
    );

    await tester.tap(find.text('Verify Record'));
    await tester.pumpAndSettle();
    // The reviewer keeps the panel — and their notes — to retry.
    expect(failedCloses, 0);
  });

  testWidgets('the status dropdown offers only the two assignable statuses', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      record: MockData.cases.first,
      tab: CaseDetailTab.verify,
    );

    await tester.tap(find.text(CaseStatus.pendingWithCpu.label).last);
    await tester.pumpAndSettle();

    expect(find.text(CaseStatus.pendingWithHealthChecker.label), findsWidgets);
    for (final gone in [
      CaseStatus.inReview,
      CaseStatus.verified,
      CaseStatus.completed,
      CaseStatus.needClarification,
    ]) {
      expect(find.text(gone.label), findsNothing, reason: gone.label);
    }
  });

  testWidgets('verify posts the case with the chosen status', (tester) async {
    final sent = <http.Request>[];
    final api = CaseApi(
      ApiClient(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response(jsonEncode({'updated': 1}), 200);
        }),
      ),
    );

    final record = MockData.cases.first;
    await _pumpPanel(
      tester,
      record: record,
      tab: CaseDetailTab.verify,
      api: api,
    );

    await tester.tap(find.text(CaseStatus.pendingWithCpu.label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(CaseStatus.pendingWithHealthChecker.label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify Record'));
    await tester.pumpAndSettle();

    expect(sent, hasLength(1), reason: 'verify did not call the API');
    expect(sent.single.url.path, endsWith('/update-smartpointer'));

    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    final row = (body['rows'] as List).single as Map<String, dynamic>;
    expect(row['status'], 'Pending with Health Checker');
    // The natural key has to travel, or the server cannot find the row.
    expect(row['client_id'], record.clientId);
    expect(row['account_no'], record.accountNo);
    expect(row['line_no'], record.lineNo);
  });

  testWidgets('a failed verify keeps the record unchanged and says why', (
    tester,
  ) async {
    final failing = CaseApi(
      ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'message': 'The database is unavailable.'}),
            503,
          ),
        ),
      ),
    );

    final changes = await _pumpPanel(
      tester,
      record: MockData.cases.first,
      tab: CaseDetailTab.verify,
      api: failing,
    );

    await tester.tap(find.text('Verify Record'));
    await tester.pumpAndSettle();

    // Nothing is claimed on screen that the server did not accept.
    expect(changes, isEmpty);
    expect(find.text('The database is unavailable.'), findsOneWidget);
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
