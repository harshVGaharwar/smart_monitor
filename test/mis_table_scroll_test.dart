import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/data/mock_data.dart';
import 'package:smart_monitor/theme/app_theme.dart';
import 'package:smart_monitor/widgets/mis_table.dart';
import 'package:smart_monitor/widgets/pan_scroll_view.dart';
import 'package:smart_monitor/widgets/searchable_dropdown.dart';
import 'package:smart_monitor/widgets/table_scroll_frame.dart';

/// Pumps the register wide enough that every column is laid out.
Future<void> _pumpRegister(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1700, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: MisTable(reports: MockData.misReports))),
  );
  await tester.pumpAndSettle();
}

/// The date part of what a freshly stamped completion cell reads.
String _today() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

/// The green wash a just-stamped completion date carries while it fades. The
/// card behind the table is a DecoratedBox too, so this matches on the wash's
/// own colour rather than on any box carrying one.
final Finder _flash = find.byWidgetPredicate((w) {
  if (w is! DecoratedBox) return false;
  final decoration = w.decoration;
  if (decoration is! BoxDecoration) return false;
  final colour = decoration.color;
  if (colour == null || colour.a <= 0.02) return false;
  const wash = AppColors.successBg;
  return colour.r == wash.r && colour.g == wash.g && colour.b == wash.b;
});

void main() {
  testWidgets('MIS table scrolls horizontally past the viewport', (
    tester,
  ) async {
    // Narrower than the table's ~1442px of columns, so it must scroll.
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MisTable(reports: MockData.misReports)),
      ),
    );
    await tester.pumpAndSettle();

    // Scoped to the table body — the search TextField also owns a horizontal
    // scrollable, so a bare axis match would be ambiguous.
    final scrollable = find.descendant(
      of: find.byType(PanScrollView),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      ),
    );
    expect(scrollable, findsOneWidget);

    final position = tester.state<ScrollableState>(scrollable).position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'columns are wider than the viewport, so there is room to scroll',
    );

    // Touch and trackpad still pan it. Mouse drag is deliberately off: the
    // filter row under the headings holds dropdowns, and a drag that wins the
    // arena cancels the click that would open one.
    await tester.drag(
      scrollable,
      const Offset(-600, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
      reason: 'a touch drag should pan the table',
    );
    expect(find.text('LAST PUBLISHED DATE'), findsOneWidget);
  });

  testWidgets('a mouse drag does not pan, so filter clicks survive', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MisTable(reports: MockData.misReports)),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.descendant(
      of: find.byType(PanScrollView),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      ),
    );

    await tester.drag(
      scrollable,
      const Offset(-600, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
  });

  testWidgets('a column filter narrows the register', (tester) async {
    // Wide enough that the filter row's dropdowns are all laid out.
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MisTable(reports: MockData.misReports)),
      ),
    );
    await tester.pumpAndSettle();

    final frequency = MockData.misReports.first.frequency;
    final matching = MockData.misReports
        .where((r) => r.frequency == frequency)
        .length;
    expect(matching, lessThan(MockData.misReports.length));

    // MIS RECD FROM is the first filterable column, FREQUENCY the second —
    // the lead-in tick column carries no filter.
    await tester.tap(find.byType(SearchableDropdown<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text(frequency).last);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Showing $matching of ${MockData.misReports.length} reports',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('approval boxes sit under their heading, before completion', (
    tester,
  ) async {
    await _pumpRegister(tester);

    expect(find.text('TICK DATE'), findsNothing);
    expect(find.text('APPROVE DATE'), findsOneWidget);
    expect(find.text('COMPLETION DATE'), findsOneWidget);

    // One box per row, and none in the header band.
    expect(find.byType(Checkbox), findsNWidgets(MockData.misReports.length));

    final box = tester.getRect(find.byType(Checkbox).first);
    final approve = tester.getRect(find.text('APPROVE DATE'));
    final completion = tester.getRect(find.text('COMPLETION DATE'));

    expect(box.left, moreOrLessEquals(approve.left, epsilon: 4));
    expect(box.right, lessThan(completion.left));
  });

  testWidgets('approving a report stamps today, and withdrawing undoes it', (
    tester,
  ) async {
    await _pumpRegister(tester);

    final today = _today();
    expect(
      find.textContaining(today),
      findsNothing,
      reason: 'the register arrives with older dates only',
    );

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('1 ticked'), findsOneWidget);
    expect(find.textContaining(today), findsOneWidget);

    // Withdrawing the approval hands the row back its original date.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('0 ticked'), findsOneWidget);
    expect(find.textContaining(today), findsNothing);
  });

  testWidgets('the stamped date flashes, then settles', (tester) async {
    await _pumpRegister(tester);

    // Nothing is washed before the first approval.
    expect(_flash, findsNothing);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_flash, findsOneWidget, reason: 'the new date should be washed');

    await tester.pumpAndSettle();
    expect(_flash, findsNothing, reason: 'and the wash should fade out');
  });

  testWidgets('both scrollbars stay pinned to the card edges', (tester) async {
    tester.view.physicalSize = const Size(900, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MisTable(reports: MockData.misReports)),
      ),
    );
    await tester.pumpAndSettle();

    // Two Scrollbars over the table body: one per axis.
    final bars = find.descendant(
      of: find.byType(TableScrollFrame),
      matching: find.byType(Scrollbar),
    );
    expect(bars, findsNWidgets(2));

    final frameRect = tester.getRect(find.byType(TableScrollFrame));
    final verticalBarRect = tester.getRect(bars.first);

    // The vertical bar must span the frame's full width so it paints at the
    // right-hand edge — nested inside the pan view it would be clipped away.
    expect(
      verticalBarRect.right,
      moreOrLessEquals(frameRect.right, epsilon: 1),
    );

    // Panning right must not move the vertical bar.
    final hPane = find.descendant(
      of: find.byType(PanScrollView),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      ),
    );
    await tester.drag(
      hPane,
      const Offset(-400, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(bars.first),
      verticalBarRect,
      reason:
          'the vertical bar is outside the horizontal pane, so it stays put',
    );
  });
}
