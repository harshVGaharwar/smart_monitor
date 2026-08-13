// The dashboard heading names the side of the handover the reader works. The
// two templates share one grid and read it from opposite ends, and the heading
// is the only thing on screen that says which end they are at.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/user_rights.dart';
import 'package:smart_monitor/widgets/health_check_header.dart';

Future<void> _pump(WidgetTester tester, String role) async {
  tester.view.physicalSize = const Size(1700, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HealthCheckHeader(
          title: AppRole.parse(role).dashboardTitle,
          counts: const StatusCounts(total: 0, byStatus: {}),
          recordCount: 0,
          searchController: TextEditingController(),
          onSearchChanged: (_) {},
          lastUpdated: DateTime.now(),
          onRefresh: () {},
          onExport: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('each template names its own dashboard', () {
    expect(AppRole.maker.dashboardTitle, 'Health Check Dashboard');
    expect(AppRole.checker.dashboardTitle, 'CPU Check Dashboard');
    // Better an unadorned heading than one claiming a side they may not be on.
    expect(AppRole.unknown.dashboardTitle, 'Dashboard');
  });

  test('the role text is read as forgivingly as everywhere else', () {
    // The text is the sign-in service's, not this app's.
    expect(AppRole.parse('CHECKER').dashboardTitle, 'CPU Check Dashboard');
    expect(AppRole.parse('maker').dashboardTitle, 'Health Check Dashboard');
  });

  testWidgets('the health check side sees its own heading', (tester) async {
    await _pump(tester, 'Maker');

    expect(find.text('Health Check Dashboard'), findsOneWidget);
    expect(find.text('CPU Check Dashboard'), findsNothing);
  });

  testWidgets('the CPU side sees theirs', (tester) async {
    await _pump(tester, 'Checker');

    expect(find.text('CPU Check Dashboard'), findsOneWidget);
    expect(find.text('Health Check Dashboard'), findsNothing);
  });
}
