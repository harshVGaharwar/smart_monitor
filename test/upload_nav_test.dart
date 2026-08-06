import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_monitor/pages/dashboard_page.dart';
import 'package:smart_monitor/widgets/upload_cases_view.dart';

void main() {
  testWidgets('desktop: tapping Upload Cases swaps in the upload view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: DashboardPage(user: 'tester')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UploadCasesView), findsNothing);
    await tester.tap(find.text('Upload Document'));
    await tester.pumpAndSettle();
    expect(find.byType(UploadCasesView), findsOneWidget);
  });

  // The rail is only in the drawer on mobile, so the top bar's menu button is
  // the sole route to it. Without that button Upload Cases is unreachable.
  testWidgets('mobile: the menu button reaches Upload Cases', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: DashboardPage(user: 'tester')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.upload_file_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(UploadCasesView), findsOneWidget);
  });
}
