import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/data/mock_data.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/pages/dashboard_page.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/services/case_export.dart';
import 'package:smart_monitor/theme/app_theme.dart';
import 'package:smart_monitor/widgets/health_check_header.dart';

/// A backend serving [MockData.cases] the way `/get-smartpointer` would, so
/// the page under test shows the same records these assertions compare with.
CaseApi _api({List<CaseItem>? cases, int status = 200, String? error}) {
  final rows = [
    for (final c in cases ?? MockData.cases)
      {
        'exception_code': c.exceptionCode,
        'client_id': c.clientId,
        'customer_name': c.customerName,
        'account_no': c.accountNo,
        'line_no': c.lineNo,
        'health_check_category': c.healthCheckCategory,
        'sub_category': c.subCategory,
        'support_system': c.supportSystem,
        'core_system': c.coreSystem,
        'exception_category': c.exceptionCategory,
        'reason': c.reason,
        'segment': c.segment,
        'facility_sr_no': c.facilitySrNo,
        'maker': c.maker,
        'checker': c.checker,
        'cpu': c.cpu,
        'team': c.team,
        'status': c.status.label,
      },
  ];
  final body = error != null
      ? jsonEncode({'message': error})
      : jsonEncode({'rows': rows, 'count': rows.length});

  return CaseApi(
    ApiClient(client: MockClient((_) async => http.Response(body, status))),
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  double width = 1700,
  CaseApi? api,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: DashboardPage(user: 'ninad.thakur', api: api ?? _api()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('header shows the title, counts and record total', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    expect(find.text('Health Check Dashboard'), findsOneWidget);

    // Counts are derived from the data, not hardcoded — and the buckets are
    // driven by the statuses themselves, so this follows the enum rather than
    // restating a fixed five.
    final all = MockData.cases;
    final counts = StatusCounts.of(all);

    // The counts strip uses RichText so the number and label can carry
    // different colours; findRichText matches on the joined span text, which
    // pins the number to its label.
    expect(
      find.text('${all.length} Total', findRichText: true),
      findsOneWidget,
      reason: 'total count wrong or missing',
    );
    for (final status in counts.shown) {
      expect(
        find.text('${counts[status]} ${status.label}', findRichText: true),
        findsOneWidget,
        reason: '${status.label} count wrong or missing',
      );
    }
    // Every status a reviewer can assign is listed even at zero.
    expect(counts.shown, containsAll(CaseStatus.assignable));

    expect(
      find.text('${all.length} record${all.length == 1 ? '' : 's'}'),
      findsOneWidget,
    );
    expect(find.text('Export Excel'), findsOneWidget);
  });

  testWidgets('filtering belongs to the grid, not the header', (tester) async {
    await _pumpDashboard(tester);

    // The header's pills are gone; the only picker it still holds is none at
    // all, so every dropdown on screen is one of the table's column filters.
    expect(
      find.descendant(
        of: find.byType(HealthCheckHeader),
        matching: find.byType(DropdownButton<String?>),
      ),
      findsNothing,
    );
    expect(find.text('Show all'), findsWidgets);
  });

  testWidgets('searching narrows the rows and the record count', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    final target = MockData.cases.first;
    await tester.enterText(find.byType(TextField).first, target.customerName);
    await tester.pumpAndSettle();

    final expected = MockData.cases
        .where(
          (c) => c.customerName.toLowerCase().contains(
            target.customerName.toLowerCase(),
          ),
        )
        .length;

    expect(expected, greaterThan(0));
    expect(
      find.text('$expected record${expected == 1 ? '' : 's'}'),
      findsOneWidget,
    );
  });

  group('CaseExport', () {
    test('csv carries a header row and one line per case', () {
      final csv = CaseExport.buildCsv(MockData.cases.take(2).toList());
      final lines = csv.trim().split('\r\n');

      expect(lines.first, startsWith('Exception code,'));
      expect(lines.first, contains('Customer name'));
      expect(lines, hasLength(3)); // header + 2 rows
      expect(lines[1], contains(MockData.cases.first.exceptionCode));
    });

    test('values containing commas stay in one field', () {
      final withComma = MockData.cases.firstWhere(
        (c) => c.team.contains('/') || c.subCategory.contains(','),
        orElse: () => MockData.cases.first,
      );
      final csv = CaseExport.buildCsv([withComma]);
      expect(csv.trim().split('\r\n'), hasLength(2));
    });

    test('bytes start with a UTF-8 BOM so Excel picks the encoding', () {
      final bytes = CaseExport.buildCsvBytes(MockData.cases.take(1).toList());
      expect(bytes.take(3).toList(), [0xEF, 0xBB, 0xBF]);
    });

    test('filename is timestamped', () {
      final name = CaseExport.fileName(DateTime(2026, 8, 3, 15, 7));
      expect(name, 'health-check-20260803-1507.csv');
    });
  });

  testWidgets('the record count and export close the counts line', (
    tester,
  ) async {
    // Wider than the other cases on purpose: the test font draws every glyph
    // as a square, so the counts strip measures nearly twice what it does
    // with a real face and would wrap at a width no real screen wraps at.
    //
    // The fixture carries only the two statuses a reviewer can assign, which
    // is what stored data looks like — the retired ones exist in MockData
    // alone, and listing all seven would wrap the strip over a layout no user
    // ever sees.
    final live = [
      for (final (i, c) in MockData.cases.indexed)
        c.copyWith(
          status: i.isEven
              ? CaseStatus.pendingWithCpu
              : CaseStatus.pendingWithHealthChecker,
        ),
    ];
    await _pumpDashboard(tester, width: 2100, api: _api(cases: live));

    final header = tester.getRect(find.byType(HealthCheckHeader));
    final total = tester.getRect(find.text('16 Total', findRichText: true));
    final records = tester.getRect(find.text('16 records'));
    final export = tester.getRect(find.text('Export Excel'));

    // One line: the counts strip on the left, count and export closing it.
    expect(records.center.dy, moreOrLessEquals(total.center.dy, epsilon: 6));
    expect(export.center.dy, moreOrLessEquals(total.center.dy, epsilon: 6));
    expect(records.left, greaterThan(total.right));
    expect(export.left, greaterThan(records.right));
    expect(export.right, lessThanOrEqualTo(header.right));
    expect(header.right - export.right, lessThan(40));
  });
}
