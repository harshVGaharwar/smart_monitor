import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/theme/app_theme.dart';
import 'package:smart_monitor/widgets/searchable_dropdown.dart';

const _options = [
  'Ahmedabad',
  'Bengaluru',
  'Chennai',
  'Gurgaon',
  'Kolkata',
  'Mohali',
  'Mumbai',
  'Pune',
];

/// Hosts the picker mid-screen so there is room below it for the overlay.
Future<List<String?>> _pump(
  WidgetTester tester, {
  String? value,
  String? clearLabel,
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final picked = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 260,
            child: SearchableDropdown<String>(
              value: value,
              options: _options,
              labelOf: (v) => v,
              hint: 'Select CPU',
              clearLabel: clearLabel,
              onChanged: picked.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return picked;
}

Finder get _field => find.byType(SearchableDropdown<String>);
Finder get _searchBox => find.byType(TextField);

void main() {
  testWidgets('the field shows the hint until a value is picked', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Select CPU'), findsOneWidget);
    // Closed: no list, no search box.
    expect(_searchBox, findsNothing);
    expect(find.text('Kolkata'), findsNothing);
  });

  testWidgets('the overlay opens below the field, search box first', (
    tester,
  ) async {
    await _pump(tester);

    final field = tester.getRect(_field);
    await tester.tap(_field);
    await tester.pumpAndSettle();

    expect(_searchBox, findsOneWidget);
    final search = tester.getRect(_searchBox);
    expect(
      search.top,
      greaterThanOrEqualTo(field.bottom),
      reason: 'the list must not cover the field it belongs to',
    );
    expect(find.text('Kolkata'), findsOneWidget);
  });

  testWidgets('typing narrows the list to what matches', (tester) async {
    await _pump(tester);

    await tester.tap(_field);
    await tester.pumpAndSettle();
    await tester.enterText(_searchBox, 'mu');
    await tester.pumpAndSettle();

    // Case-insensitive, and matches anywhere in the label.
    expect(find.text('Mumbai'), findsOneWidget);
    expect(find.text('Chennai'), findsNothing);

    await tester.enterText(_searchBox, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('picking an option reports it and closes the overlay', (
    tester,
  ) async {
    final picked = await _pump(tester);

    await tester.tap(_field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mohali'));
    await tester.pumpAndSettle();

    expect(picked, ['Mohali']);
    expect(_searchBox, findsNothing);
  });

  testWidgets('enter takes the first match', (tester) async {
    final picked = await _pump(tester);

    await tester.tap(_field);
    await tester.pumpAndSettle();
    await tester.enterText(_searchBox, 'guru');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Nothing matched, so submitting picked nothing and left the list open
    // for the user to correct their typing.
    expect(picked, isEmpty);
    expect(_searchBox, findsOneWidget);

    await tester.enterText(_searchBox, 'gur');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(picked, ['Gurgaon']);
  });

  testWidgets('a tap outside dismisses without picking', (tester) async {
    final picked = await _pump(tester);

    await tester.tap(_field);
    await tester.pumpAndSettle();
    expect(_searchBox, findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(_searchBox, findsNothing);
    expect(picked, isEmpty);
  });

  testWidgets('the clear entry reports null and is searchable too', (
    tester,
  ) async {
    final picked = await _pump(
      tester,
      value: 'Chennai',
      clearLabel: 'Show all',
    );

    // The closed field reads the selection, not the hint.
    expect(find.text('Chennai'), findsOneWidget);
    expect(find.text('Select CPU'), findsNothing);

    await tester.tap(_field);
    await tester.pumpAndSettle();
    expect(find.text('Show all'), findsOneWidget);

    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();

    expect(picked, [null]);
  });

  testWidgets('a value the options no longer carry reads as unset', (
    tester,
  ) async {
    await _pump(tester, value: 'Nagpur');
    expect(find.text('Select CPU'), findsOneWidget);
    expect(find.text('Nagpur'), findsNothing);
  });

  testWidgets('the overlay flips above a field near the bottom edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 260,
              child: SearchableDropdown<String>(
                value: null,
                options: _options,
                labelOf: (v) => v,
                hint: 'Select CPU',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.getRect(_field);
    await tester.tap(_field);
    await tester.pumpAndSettle();

    expect(
      tester.getRect(_searchBox).top,
      lessThan(field.top),
      reason: 'no room below, so the list goes above rather than off-screen',
    );
  });
}
