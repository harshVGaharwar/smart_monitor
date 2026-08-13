// The dashboard header hiding its status breakdown, and keeping everything
// else.
//
// "View the summary" is a supervisor's right, but the header it lives on also
// carries search, refresh, the record total and export — the controls a reader
// works their own rows with. Gating the whole header would have taken those
// from the one template that verifies records, so only the counts go.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/widgets/health_check_header.dart';

CaseItem _case(CaseStatus status) => CaseItem(
  exceptionCode: 'EXC-${status.index}',
  clientId: '1',
  customerName: 'ACME',
  accountNo: '2',
  status: status,
);

Future<void> _pump(WidgetTester tester, {required bool showSummary}) async {
  tester.view.physicalSize = const Size(1700, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HealthCheckHeader(
          title: 'Health Check Dashboard',
          counts: StatusCounts.of([
            _case(CaseStatus.pendingWithCpu),
            _case(CaseStatus.verified),
          ]),
          recordCount: 2,
          searchController: TextEditingController(),
          onSearchChanged: (_) {},
          lastUpdated: DateTime.now(),
          onRefresh: () {},
          onExport: () {},
          showSummary: showSummary,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a supervisor sees the status breakdown', (tester) async {
    await _pump(tester, showSummary: true);

    // The counts are RichText spans — number and label styled apart.
    expect(find.textContaining('Total', findRichText: true), findsWidgets);
    expect(find.textContaining('with CPU', findRichText: true), findsWidgets);
  });

  testWidgets('without the right the counts go and nothing else does', (
    tester,
  ) async {
    await _pump(tester, showSummary: false);

    expect(find.textContaining('Total', findRichText: true), findsNothing);
    expect(find.textContaining('with CPU', findRichText: true), findsNothing);

    // The working controls stay: this is the template that verifies rows.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.textContaining('2 records'), findsOneWidget);
  });
}
