import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/models/pending_case.dart';
import 'package:smart_monitor/widgets/searchable_dropdown.dart';
import 'package:smart_monitor/widgets/validation_results_table.dart';

PendingCase _row({
  String exceptionCategory = 'Exception',
  String? cpu = 'Mumbai',
  String? team = 'CAM Renewal Team',
  String cpuRaw = '',
  int id = 2,
}) {
  return PendingCase(
    id: id,
    clientId: '4943581',
    customerName: 'ACME',
    accountNo: '50200031339584',
    lineNo: '5',
    healthCheckCategory: 'CAM Expiry Health Check',
    subCategory: 'Sub',
    supportSystem: 'LMM',
    coreSystem: 'nan',
    maker: '',
    checker: 'S41002',
    exceptionCategory: exceptionCategory,
    cpu: cpu,
    cpuRaw: cpuRaw.isEmpty ? (cpu ?? '') : cpuRaw,
    actionableTeam: team,
  );
}

// The four cell editors, in column order. The filter row's pickers are the
// same widget, told apart by the "Show all" entry only a filter carries.
const _exception = 1;
const _cpu = 2;

final Finder _editors = find.byWidgetPredicate(
  (w) => w is SearchableDropdown<String> && w.clearLabel == null,
);

Finder _editor(int column) => _editors.at(column);

Widget _host(
  List<PendingCase> rows, {
  VoidCallback? onRowsChanged,
  ValueChanged<Set<PendingCase>>? onSelectionChanged,
  ValueChanged<PendingCase>? onDeleteRow,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ValidationResultsTable(
        rows: rows,
        onRowsChanged: onRowsChanged,
        onSelectionChanged: onSelectionChanged,
        onDeleteRow: onDeleteRow,
      ),
    ),
  );
}

void main() {
  testWidgets('an exception category from the file renders without asserting', (
    tester,
  ) async {
    // 'Timeout' is not in the master list; the dropdown must absorb it rather
    // than trip its "exactly one item" assertion.
    await tester.pumpWidget(_host([_row(exceptionCategory: 'Timeout')]));

    expect(tester.takeException(), isNull);
    expect(find.text('Timeout'), findsWidgets);
  });

  testWidgets('a blank exception category falls back to the hint', (
    tester,
  ) async {
    await tester.pumpWidget(_host([_row(exceptionCategory: '')]));

    expect(tester.takeException(), isNull);
  });

  testWidgets('a valid row is editable, selectable, and carries no flag', (
    tester,
  ) async {
    await tester.pumpWidget(_host([_row()]));

    expect(tester.takeException(), isNull);
    // Header select-all plus the clean row's own box — a clean row is what
    // the submit sends, so it has to be tickable.
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    // All four master-data cells stay pickable on a row the file got right.
    expect(_editors, findsNWidgets(4));
  });

  testWidgets('an unrecognised CPU is flagged and keeps the file\'s text', (
    tester,
  ) async {
    await tester.pumpWidget(_host([_row(cpu: null, cpuRaw: 'Mumbai West')]));

    expect(tester.takeException(), isNull);
    expect(find.text('Mumbai West'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    // Header select-all plus the flagged row's own box.
    expect(find.byType(Checkbox), findsNWidgets(2));
  });

  testWidgets('correcting a flagged cell clears the error and notifies', (
    tester,
  ) async {
    // Wide enough that the CPU column is on screen and hit-testable: it
    // starts past x=1830 once every column ahead of it is laid out.
    tester.view.physicalSize = const Size(3100, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final row = _row(cpu: null, cpuRaw: 'Mumbai West');
    var notified = 0;
    await tester.pumpWidget(_host([row], onRowsChanged: () => notified++));
    await tester.pumpAndSettle();

    // Every master-data cell is a picker now, so the CPU one is taken by
    // column position rather than by being the only one on the row.
    expect(_editors, findsNWidgets(4));
    await tester.tap(_editor(_cpu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kolkata').last);
    await tester.pumpAndSettle();

    expect(row.cpu, 'Kolkata');
    expect(row.hasErrors, isFalse);
    expect(notified, 1);
    // The flag goes, but the checkbox stays: having just fixed the row, the
    // user's next move is to tick it and submit.
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(find.byType(Checkbox), findsNWidgets(2));
  });

  testWidgets('a tick survives the row being corrected', (tester) async {
    tester.view.physicalSize = const Size(3100, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final row = _row(cpu: null, cpuRaw: 'Mumbai West');
    var selection = <PendingCase>{};
    await tester.pumpWidget(
      _host([row], onSelectionChanged: (s) => selection = s),
    );
    await tester.pumpAndSettle();

    // Tick the flagged row, then fix what was wrong with it.
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    expect(selection, contains(row));

    await tester.tap(_editor(_cpu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kolkata').last);
    await tester.pumpAndSettle();

    // Turning clean must not silently drop it from what gets submitted.
    expect(row.hasErrors, isFalse);
    expect(selection, contains(row));
  });

  testWidgets('clean rows stay selectable after the last flagged row goes', (
    tester,
  ) async {
    // Regression: checkboxes used to render only on flagged rows, so removing
    // the last one left the page with nothing tickable at all.
    final clean = _row(id: 1);
    final flagged = _row(id: 2, cpu: null, cpuRaw: 'Mumbai West');
    final rows = [clean, flagged];

    await tester.pumpWidget(
      _host(rows, onDeleteRow: (r) => rows.remove(r)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).last);
    await tester.pumpAndSettle();

    expect(rows, [clean]);
    // Header select-all plus the surviving clean row.
    expect(find.byType(Checkbox), findsNWidgets(2));
  });

  testWidgets('every row carries its own delete button', (tester) async {
    final rows = [_row(id: 1), _row(id: 2, cpu: null, cpuRaw: 'Mumbai West')];
    final deleted = <PendingCase>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValidationResultsTable(rows: rows, onDeleteRow: deleted.add),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // One per row, clean and flagged alike, and no bulk control anywhere.
    final buttons = find.byIcon(Icons.delete_outline_rounded);
    expect(buttons, findsNWidgets(2));
    expect(find.text('Delete Selected'), findsNothing);

    // A single tap removes that row — no confirmation dialog in the way.
    await tester.tap(buttons.first);
    await tester.pumpAndSettle();

    expect(deleted, [rows.first]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('deleting a ticked error row drops it from the selection', (
    tester,
  ) async {
    final row = _row(id: 1, cpu: null, cpuRaw: 'Mumbai West');
    var selection = <PendingCase>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValidationResultsTable(
            rows: [row],
            onSelectionChanged: (s) => selection = s,
            onDeleteRow: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Index 0 is the header's select-all, 1 is the flagged row's own box.
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(selection, {row});

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    // Otherwise "Download Error Data" would still export the removed row.
    expect(selection, isEmpty);
  });

  testWidgets('an empty row list leaves the table in an empty state', (
    tester,
  ) async {
    await tester.pumpWidget(_host([]));

    expect(tester.takeException(), isNull);
    expect(find.text('No rows match the current filters.'), findsOneWidget);
  });

  testWidgets('the exception dropdown never offers a rejected value', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(3100, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Regression: the options used to include the file's own categories, so
    // the user could "fix" a red cell by re-picking the value that failed.
    final row = _row(exceptionCategory: 'Timeout');
    await tester.pumpWidget(_host([row]));
    await tester.pumpAndSettle();

    await tester.tap(_editor(_exception));
    await tester.pumpAndSettle();

    expect(find.text('Exclusion'), findsOneWidget);
    // Present once as the closed field's hint, never as a selectable item.
    expect(find.text('Timeout'), findsOneWidget);
  });

  testWidgets('a click that drifts still opens a cell dropdown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(3100, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host([_row(cpu: null, cpuRaw: 'Tamil Nadu')]));
    await tester.pumpAndSettle();

    // Regression: the table's horizontal pan used to accept mouse drags, and
    // Flutter's 1px slop for precise pointers meant the pan recogniser won the
    // arena on the slightest movement — eating the click entirely.
    final gesture = await tester.startGesture(
      tester.getCenter(_editor(_cpu)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(3, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Kolkata'), findsOneWidget);
  });
}
