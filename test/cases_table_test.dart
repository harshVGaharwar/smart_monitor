import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/data/mock_data.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/theme/app_theme.dart';
import 'package:smart_monitor/widgets/case_detail_panel.dart';
import 'package:smart_monitor/widgets/cases_table.dart';
import 'package:smart_monitor/widgets/searchable_dropdown.dart';

/// Records every (record, tab) pair the table asks to open.
typedef Opened = List<(CaseItem, CaseDetailTab)>;

Future<Opened> _pumpTable(WidgetTester tester, {List<CaseItem>? cases}) async {
  // Wide enough to paint the whole grid, actions column included — the table
  // itself scrolls horizontally on any real screen.
  tester.view.physicalSize = const Size(2700, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final opened = <(CaseItem, CaseDetailTab)>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: CasesTable(
          cases: cases ?? MockData.cases,
          onOpenCase: (c, tab) => opened.add((c, tab)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

/// Picks [value] in the filter row's [index]-th dropdown, counting only the
/// columns that carry one: customer name, CPU, description, team, status,
/// and so on.
Future<void> _pickFilter(
  WidgetTester tester,
  int index,
  String value,
) async {
  await tester.tap(find.byType(SearchableDropdown<String>).at(index));
  await tester.pumpAndSettle();
  // The overlay paints over the grid, so its copy of the label is the last.
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

/// The footer line for a grid holding [total] records, on its first page.
Finder _footerFor(int total) => find.text(
  'Showing ${total < 10 ? total : 10} of $total records',
  findRichText: true,
);

void main() {
  testWidgets('a row shows every field the dashboard lists', (tester) async {
    final record = MockData.cases.firstWhere((c) => c.comments.isNotEmpty);
    await _pumpTable(tester, cases: [record]);

    for (final value in [
      record.clientId,
      record.cpu,
      record.team,
      record.status.label,
      record.customerName,
      record.accountNo,
      record.lineNo,
      record.subCategory,
      record.supportSystem,
      record.coreSystem,
    ]) {
      expect(find.text(value), findsWidgets, reason: 'missing "$value"');
    }
    expect(
      find.text(
        '${record.comments.length} Message'
        '${record.comments.length == 1 ? '' : 's'}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a record with no messages says so rather than showing zero', (
    tester,
  ) async {
    final record = MockData.cases.firstWhere((c) => c.comments.isEmpty);
    await _pumpTable(tester, cases: [record]);

    expect(find.text('No Messages'), findsOneWidget);
    expect(find.text('0 Messages'), findsNothing);
  });

  testWidgets('the message count opens the record on its thread', (
    tester,
  ) async {
    final record = MockData.cases.first;
    final opened = await _pumpTable(tester, cases: [record]);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(opened.single.$2, CaseDetailTab.comments);
  });

  testWidgets('each action icon opens the drawer on its own tab', (
    tester,
  ) async {
    final record = MockData.cases.first;
    final opened = await _pumpTable(tester, cases: [record]);

    for (final (tooltip, tab) in [
      ('View details', CaseDetailTab.basicInfo),
      ('Verify', CaseDetailTab.verify),
      ('Reassign', CaseDetailTab.reassign),
    ]) {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(opened.last.$1.exceptionCode, record.exceptionCode);
      expect(opened.last.$2, tab, reason: '$tooltip opened the wrong tab');
    }
    expect(opened, hasLength(3));
  });

  testWidgets('the client id opens the record too', (tester) async {
    final record = MockData.cases.first;
    final opened = await _pumpTable(tester, cases: [record]);

    await tester.tap(find.text(record.clientId));
    await tester.pumpAndSettle();

    expect(opened.single.$2, CaseDetailTab.basicInfo);
  });

  testWidgets('sorting by client toggles between ascending and descending', (
    tester,
  ) async {
    await _pumpTable(tester);

    int firstClientOnScreen() {
      // Rows are paged, so the first client id painted is the page's smallest
      // or largest depending on the sort direction.
      final ids = MockData.cases.map((c) => int.parse(c.clientId)).toList()
        ..sort();
      return ids.first;
    }

    // Default is client ascending.
    expect(find.text('${firstClientOnScreen()}'), findsOneWidget);

    await tester.tap(find.text('CLIENT ID'));
    await tester.pumpAndSettle();

    final descendingFirst =
        (MockData.cases.map((c) => int.parse(c.clientId)).toList()..sort())
            .last;
    expect(find.text('$descendingFirst'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the select-all box ticks every row on the page', (tester) async {
    await _pumpTable(tester);

    final boxes = find.byType(Checkbox);
    // One header box plus one per row on the page.
    expect(boxes, findsWidgets);

    await tester.tap(boxes.first);
    await tester.pumpAndSettle();

    final rowsOnPage = boxes.evaluate().length - 1;
    expect(find.text('$rowsOnPage selected'), findsOneWidget);
  });

  testWidgets('the footer reports the record total', (tester) async {
    await _pumpTable(tester);

    expect(
      find.text(
        'Showing 10 of ${MockData.cases.length} records',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a column filter narrows the grid to the chosen value', (
    tester,
  ) async {
    await _pumpTable(tester);

    final cpu = MockData.cases.first.cpu;
    final matching = MockData.cases.where((c) => c.cpu == cpu).length;
    expect(matching, lessThan(MockData.cases.length), reason: 'need a slice');

    await _pickFilter(tester, 1, cpu);
    expect(_footerFor(matching), findsOneWidget);

    // Back to Show all restores every record.
    await _pickFilter(tester, 1, 'Show all');
    expect(_footerFor(MockData.cases.length), findsOneWidget);
  });

  testWidgets('two column filters compound', (tester) async {
    await _pumpTable(tester);

    final first = MockData.cases.first;
    final both = MockData.cases
        .where((c) => c.cpu == first.cpu && c.team == first.team)
        .length;

    await _pickFilter(tester, 1, first.cpu);
    await _pickFilter(tester, 3, first.team);

    expect(_footerFor(both), findsOneWidget);
  });

  testWidgets('the status filter slices on who a record waits on', (
    tester,
  ) async {
    await _pumpTable(tester);

    final open = MockData.cases
        .where((c) => c.status == CaseStatus.pending)
        .length;

    // Customer, CPU, description, team, then status.
    await _pickFilter(tester, 4, 'Pending by CPU');
    expect(_footerFor(open), findsOneWidget);
  });

  testWidgets('the health check bucket is offered while it is still empty', (
    tester,
  ) async {
    await _pumpTable(tester);

    await _pickFilter(tester, 4, 'Pending by Health Check');

    expect(find.text('No records match the current filters.'), findsOneWidget);
    expect(_footerFor(0), findsOneWidget);
  });

  testWidgets('filtering returns to the first page', (tester) async {
    await _pumpTable(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Page 2 of'), findsOneWidget);

    await _pickFilter(tester, 1, MockData.cases.first.cpu);

    expect(find.textContaining('Page 1 of'), findsOneWidget);
  });
}
