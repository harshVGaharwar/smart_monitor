import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/data/mock_data.dart';
import 'package:smart_monitor/models/pending_case.dart';
import 'package:smart_monitor/widgets/cases_table.dart';
import 'package:smart_monitor/widgets/validation_results_table.dart';

PendingCase _row(int i) => PendingCase(
  clientId: 'CL$i',
  customerName: 'Cust$i',
  accountNo: 'ACC$i',
  lineNo: 'L$i',
  healthCheckCategory: 'FD Exceptions',
  subCategory: 'Sub',
  supportSystem: 'LMM',
  coreSystem: 'FC',
  maker: 'mk',
  checker: 'ck',
);

/// Taps [finder] twice without pumping in between, so both handlers run
/// against the previous frame's state — what a fast double-click does.
Future<void> _doubleTapSameFrame(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('upload-cases paging survives a double-click on prev', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValidationResultsTable(
            rows: [for (var i = 0; i < 33; i++) _row(i)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Step to page 2, then double-click back: the second tap used to drive
    // the index to -1 and crash sublist with a RangeError.
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    await _doubleTapSameFrame(tester, find.byIcon(Icons.chevron_left_rounded));

    expect(tester.takeException(), isNull);
    expect(find.text('1 / 4'), findsOneWidget);
  });

  testWidgets('upload-cases paging survives a double-click on next', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValidationResultsTable(
            rows: [for (var i = 0; i < 12; i++) _row(i)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Only two pages: overshooting the end must not read past the list.
    await _doubleTapSameFrame(tester, find.byIcon(Icons.chevron_right_rounded));

    expect(tester.takeException(), isNull);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('dashboard cases table survives a double-click on prev', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CasesTable(cases: MockData.cases, onOpenCase: (_, _) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await _doubleTapSameFrame(tester, find.text('Prev'));

    expect(tester.takeException(), isNull);
  });
}
