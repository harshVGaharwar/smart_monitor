// The upload report's column filters.
//
// A validated column filters against the master list, not against what the
// file happened to contain. The user is on this screen precisely to correct
// rows, and a filter built from the file's own values would offer the wrong
// spellings and drop options as the corrections land.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/data/master_data.dart';
import 'package:smart_monitor/models/pending_case.dart';
import 'package:smart_monitor/theme/app_theme.dart';
import 'package:smart_monitor/widgets/searchable_dropdown.dart';
import 'package:smart_monitor/widgets/validation_results_table.dart';

import 'master_data_fixture.dart';

PendingCase _row({
  String client = '2287410',
  String? cpu = 'Chennai',
  String? cpuRaw,
  String team = 'Disbursement Team',
}) => PendingCase(
  clientId: client,
  customerName: 'NORTHGATE LOGISTICS LIMITED',
  accountNo: '11930442',
  lineNo: '50301271033039',
  subCategory: 'Policy lapsed',
  supportSystem: 'LMM',
  coreSystem: 'FC',
  maker: 'OFF807292',
  checker: 'r14878',
  healthCheckCategory: 'FD Exceptions',
  cpu: cpu,
  cpuRaw: cpuRaw,
  team: team,
);

Future<void> _pump(WidgetTester tester, List<PendingCase> rows) async {
  tester.view.physicalSize = const Size(1800, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: ValidationResultsTable(rows: rows)),
    ),
  );
  await tester.pumpAndSettle();
}

/// What the filter under [column] offers.
///
/// Read off the widget rather than by opening the menu: the filter row is the
/// band of `Show all` pickers under the headings, in column order, and its
/// options are the thing under test — driving the popup would test the
/// dropdown instead.
List<String> _filterOptions(WidgetTester tester, String column) {
  const filterable = [
    'CUSTOMER NAME',
    'ACCOUNT NO',
    'LINE NO',
    'HEALTH CHECK CATEGORY',
    'SUB CATEGORY',
    'SUPPORT SYSTEM',
    'CORE SYSTEM',
    'SEGMENT',
    'FACILITY SR. NO',
    'MAKER',
    'CHECKER',
    'LS SRM DATE',
    'EXCEPTION CATEGORY',
    'CPU',
    'ACTIONABLE TEAM',
  ];
  final index = filterable.indexOf(column);
  expect(index, isNot(-1), reason: '$column is not a filterable column');

  final filters = tester
      .widgetList<SearchableDropdown<String>>(
        find.byType(SearchableDropdown<String>),
      )
      .where((d) => d.hint == 'Show all')
      .toList();
  expect(
    filters.length,
    filterable.length,
    reason: 'the filter row should carry one picker per filterable column',
  );
  return filters[index].options;
}

void main() {
  setUp(seedMasterData);
  tearDown(MasterData.reset);

  testWidgets('a validated column offers the whole master list', (
    tester,
  ) async {
    // One row, naming one CPU. The filter still offers all six: the point of
    // this screen is correcting rows onto values the file does not have yet.
    await _pump(tester, [_row()]);

    final options = _filterOptions(tester, 'CPU');
    for (final cpu in masterCpus) {
      expect(options, contains(cpu), reason: '$cpu missing from the filter');
    }
  });

  testWidgets('a value the master does not name is still offered', (
    tester,
  ) async {
    // The unresolved spelling is exactly what someone filtering this report is
    // looking for — those are the rows with work left on them.
    await _pump(tester, [
      _row(cpu: null, cpuRaw: 'Atlantis'),
      _row(client: '9084412'),
    ]);

    final options = _filterOptions(tester, 'CPU');
    expect(options, contains('Atlantis'));
    expect(options, contains('Chennai'));
  });

  testWidgets('a column with no master offers what the file said', (
    tester,
  ) async {
    // Sub category has no master list, so there is nothing to offer but the
    // values the rows carry.
    await _pump(tester, [_row()]);

    final options = _filterOptions(tester, 'SUB CATEGORY');
    expect(options, contains('Policy lapsed'));
  });

  testWidgets('an unloaded master leaves the filter with the file values', (
    tester,
  ) async {
    // What a failed /getMasterData looks like here: empty master, so the
    // filter falls back to the rows rather than offering nothing at all.
    MasterData.reset();
    await _pump(tester, [_row()]);

    final options = _filterOptions(tester, 'CPU');
    expect(options, contains('Chennai'));
  });
}
