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
  // A long option list runs past the overlay's height, and an option below
  // the fold is never built for a tap to find — so narrow it by search first.
  await tester.enterText(find.byType(TextField).last, value);
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

  testWidgets('the select-all box ticks every filtered row', (tester) async {
    await _pumpTable(tester);

    final boxes = find.byType(Checkbox);
    // One header box plus one per row on the page.
    expect(boxes, findsWidgets);

    await tester.tap(boxes.first);
    await tester.pumpAndSettle();

    // Every record, not just the page: the rows behind the pager are part of
    // the same filtered set, and leaving them out put ticks out of reach.
    expect(find.text('${MockData.cases.length} selected'), findsOneWidget);
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

  testWidgets('the status filter slices on the status the badge shows', (
    tester,
  ) async {
    await _pumpTable(tester);

    final pending = MockData.cases
        .where((c) => c.status == CaseStatus.pendingWithCpu)
        .length;
    expect(pending, greaterThan(0), reason: 'fixture has no pending records');

    // Customer, CPU, description, team, then status.
    await _pickFilter(tester, 4, CaseStatus.pendingWithCpu.label);
    expect(_footerFor(pending), findsOneWidget);
  });

  testWidgets('an assignable status is offered while it is still empty', (
    tester,
  ) async {
    await _pumpTable(tester);

    // Nothing in the fixture is waiting on the health checker, but the choice
    // is part of the workflow and has to stay on offer.
    await _pickFilter(tester, 4, CaseStatus.pendingWithHealthChecker.label);

    expect(find.text('No records match the current filters.'), findsOneWidget);
    expect(_footerFor(0), findsOneWidget);
  });

  testWidgets('the status filter offers only the two workflow statuses', (
    tester,
  ) async {
    await _pumpTable(tester);

    await tester.tap(find.byType(SearchableDropdown<String>).at(4));
    await tester.pumpAndSettle();

    // "Pending" was a bucket nothing could put a record in and no reviewer
    // could assign; it has no place in the picker.
    expect(find.text('Pending'), findsNothing);
    expect(find.text(CaseStatus.pendingWithCpu.label), findsWidgets);
    expect(find.text(CaseStatus.pendingWithHealthChecker.label), findsWidgets);

    // Read the options off the widget rather than counting what the overlay
    // draws: a status the fixture carries is painted on its rows' badges too,
    // so a text finder cannot tell a picker entry from a badge.
    final status = tester.widget<SearchableDropdown<String>>(
      find.byType(SearchableDropdown<String>).at(4),
    );
    expect(status.options, [
      CaseStatus.pendingWithCpu.label,
      CaseStatus.pendingWithHealthChecker.label,
    ]);
  });

  // The grid takes its rows from the server, so a status outside the workflow
  // can always arrive on one — a record stored before the list was cut to two,
  // or a value the backend spells its own way. It gets shown on the row, but
  // it must not widen the picker into offering a third status.
  testWidgets('a status outside the workflow stays out of the filter', (
    tester,
  ) async {
    final stray = MockData.cases.first.copyWith(status: CaseStatus.completed);
    await _pumpTable(tester, cases: [stray, ...MockData.cases.skip(1)]);

    final status = tester.widget<SearchableDropdown<String>>(
      find.byType(SearchableDropdown<String>).at(4),
    );
    expect(status.options, isNot(contains(CaseStatus.completed.label)));
    expect(status.options, hasLength(2));
  });

  group('row selection', () {
    /// The footer's "N selected", or 0 when it is not shown at all.
    int selectedCount(WidgetTester tester) {
      final f = find.textContaining(' selected');
      if (f.evaluate().isEmpty) return 0;
      return int.parse(tester.widget<Text>(f.first).data!.split(' ').first);
    }

    /// The header checkbox: true all, false none, null partly.
    bool? headerValue(WidgetTester tester) =>
        tester.widgetList<Checkbox>(find.byType(Checkbox)).first.value;

    testWidgets('one tick counts one, and reads as a partial selection', (
      tester,
    ) async {
      await _pumpTable(tester);

      // Index 0 is the header's; 1 is the first data row's.
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();

      expect(selectedCount(tester), 1);
      expect(headerValue(tester), isNull, reason: 'partial, not empty');
    });

    testWidgets('select-all covers every filtered row, not just the page', (
      tester,
    ) async {
      await _pumpTable(tester);
      final total = MockData.cases.length;
      expect(total, greaterThan(10), reason: 'need more than one page');

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      // Regression: this used to tick only the ten rows on screen, leaving the
      // rest behind the pager where unticking could not reach them.
      expect(selectedCount(tester), total);
      expect(headerValue(tester), isTrue);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(headerValue(tester), isTrue, reason: 'page 2 is selected too');

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(selectedCount(tester), 0, reason: 'one untick clears the lot');
    });

    testWidgets('filtering drops the selections it hides', (tester) async {
      await _pumpTable(tester);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(selectedCount(tester), MockData.cases.length);

      final cpu = MockData.cases.first.cpu;
      final matching = MockData.cases.where((c) => c.cpu == cpu).length;
      expect(matching, lessThan(MockData.cases.length), reason: 'need a slice');
      await _pickFilter(tester, 1, cpu);

      // A tick the filter has hidden cannot be cleared, so it is not kept.
      expect(selectedCount(tester), matching);
    });

    testWidgets('a reload that drops rows drops their ticks', (tester) async {
      await _pumpTable(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(selectedCount(tester), MockData.cases.length);

      final fewer = MockData.cases.take(3).toList();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CasesTable(cases: fewer, onOpenCase: (_, _) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(selectedCount(tester), 3, reason: 'no ghosts from the old list');
    });
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
