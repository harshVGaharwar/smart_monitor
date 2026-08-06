import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/data/mock_data.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/pages/dashboard_page.dart';
import 'package:smart_monitor/services/case_export.dart';
import 'package:smart_monitor/theme/app_theme.dart';
import 'package:smart_monitor/widgets/health_check_header.dart';

Future<void> _pumpDashboard(WidgetTester tester, {double width = 1700}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const DashboardPage(user: 'ninad.thakur'),
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

    // Counts are derived from the data, not hardcoded.
    final all = MockData.cases;
    final pending = all.where((c) => c.status == CaseStatus.pending).length;
    final verified = all.where((c) => c.status == CaseStatus.verified).length;

    final inReview = all.where((c) => c.status == CaseStatus.inReview).length;
    final completed = all.where((c) => c.status == CaseStatus.completed).length;
    final needsClarification = all
        .where((c) => c.status == CaseStatus.needClarification)
        .length;

    // The counts strip uses RichText so the number and label can carry
    // different colours; findRichText matches on the joined span text, which
    // pins the number to its label.
    for (final entry in {
      '${all.length} Total': 'total',
      '$pending Pending': 'pending',
      '$inReview In Review': 'in review',
      '$verified Verified': 'verified',
      '$completed Completed': 'completed',
      '$needsClarification Needs Clarification': 'needs clarification',
    }.entries) {
      expect(
        find.text(entry.key, findRichText: true),
        findsOneWidget,
        reason: '${entry.value} count wrong or missing',
      );
    }
    expect(
      find.text('${all.length} record${all.length == 1 ? '' : 's'}'),
      findsOneWidget,
    );
    expect(pending + verified, lessThanOrEqualTo(all.length));
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
    await _pumpDashboard(tester, width: 2100);

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
