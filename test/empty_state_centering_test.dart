// The empty-state message used to live inside the horizontally scrolling
// pane, so it centred itself across the full width of the columns — on a wide
// table that put it off the right-hand edge of the viewport, and it drifted
// as the user panned.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/models/pending_case.dart';
import 'package:smart_monitor/widgets/cases_table.dart';
import 'package:smart_monitor/widgets/validation_results_table.dart';

/// How far the message's centre may sit from the viewport's, in pixels.
const _tolerance = 2.0;

void _expectCentredIn(WidgetTester tester, Finder message, Size viewport) {
  final box = tester.getRect(message);
  expect(
    box.center.dx,
    closeTo(viewport.width / 2, _tolerance),
    reason: 'the empty state is not centred on the visible area',
  );
  // The real symptom: it sat past the right edge entirely.
  expect(box.right, lessThan(viewport.width));
  expect(box.left, greaterThan(0));
}

void main() {
  testWidgets('cases table centres its empty state on the viewport', (
    tester,
  ) async {
    const viewport = Size(1400, 900);
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CasesTable(cases: const <CaseItem>[], onOpenCase: (_, _) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final message = find.text('No records match the current filters.');
    expect(message, findsOneWidget);
    _expectCentredIn(tester, message, viewport);
  });

  testWidgets('validation table centres its empty state on the viewport', (
    tester,
  ) async {
    const viewport = Size(1400, 900);
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ValidationResultsTable(rows: <PendingCase>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final message = find.text('No rows match the current filters.');
    expect(message, findsOneWidget);
    _expectCentredIn(tester, message, viewport);
  });
}
