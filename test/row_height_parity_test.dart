import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/pending_case.dart';
import 'package:smart_monitor/widgets/validation_results_table.dart';

/// Vertical distance between two consecutive rows — the row pitch, which is
/// what makes one row look taller than another.
double _pitch(WidgetTester tester, String firstCell, String secondCell) {
  expect(find.text(firstCell), findsOneWidget);
  expect(find.text(secondCell), findsOneWidget);
  return tester.getTopLeft(find.text(secondCell)).dy -
      tester.getTopLeft(find.text(firstCell)).dy;
}

/// Values are kept short on purpose: the test font renders every glyph as a
/// full em square, so realistic strings wrap to two lines here and would
/// measure a row height the real app never shows.
PendingCase _case({
  required String customer,
  required String client,
  String? cpu = 'Mumbai',
  String? team = 'LMS Team',
}) {
  return PendingCase(
    clientId: client,
    customerName: customer,
    accountNo: 'ACC485',
    lineNo: 'L12',
    healthCheckCategory: 'FD Exceptions',
    subCategory: 'Downtime',
    supportSystem: 'Zendesk',
    coreSystem: 'Murex',
    maker: 'mk',
    checker: 'S41002',
    cpu: cpu,
    cpuRaw: cpu ?? 'Mumbai West',
    actionableTeam: team,
    teamRaw: team ?? 'L1 Support',
  );
}

Future<double> _pitchFor(WidgetTester tester, {required bool flagged}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValidationResultsTable(
          rows: [
            _case(
              customer: 'Manoj',
              client: 'CL22156',
              cpu: flagged ? null : 'Mumbai',
              team: flagged ? null : 'LMS Team',
            ),
            _case(
              customer: 'Amit',
              client: 'CL35203',
              cpu: flagged ? null : 'Mumbai',
              team: flagged ? null : 'LMS Team',
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _pitch(tester, 'Manoj', 'Amit');
}

void main() {
  testWidgets('flagged rows do not tower over clean ones', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A clean row is plain text in the validated columns; a flagged row swaps
    // in dropdown editors. Sizing those editors past the text line height
    // would make the error rows visibly taller and break the table's rhythm.
    final cleanPitch = await _pitchFor(tester, flagged: false);
    final flaggedPitch = await _pitchFor(tester, flagged: true);

    expect(
      flaggedPitch,
      moreOrLessEquals(cleanPitch, epsilon: 4),
      reason:
          'rows with inline editors should not tower over plain text rows '
          '(clean $cleanPitch vs flagged $flaggedPitch)',
    );
  });
}
