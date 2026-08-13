// The case drawer showing only the tabs its reader may open.
//
// `role_tabs_test.dart` covers the mapping; this covers the wiring behind it.
// The bar and the view are built from the same list, and a TabController whose
// length disagrees with either one throws on the first build — which is
// exactly what a role dropping a tab out of the middle would cause.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/models/user_rights.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/widgets/case_detail_panel.dart';

const _case = CaseItem(
  exceptionCode: 'EXC-1',
  clientId: '3332125',
  customerName: 'ACME',
  accountNo: '11424036',
  lineNo: '5',
  status: CaseStatus.pendingWithCpu,
);

Api _api() => Api(
  ApiClient(
    client: MockClient((_) async => http.Response('{"updated":1}', 200)),
  ),
);

Future<void> _pump(
  WidgetTester tester,
  String role, {
  CaseDetailTab initialTab = CaseDetailTab.basicInfo,
}) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CaseDetailPanel(
          caseItem: _case,
          initialTab: initialTab,
          tabs: tabsFor(UserRights.forRole(role)),
          currentUser: 'Someone',
          userId: 'OFF807292',
          role: role,
          onChanged: (_) {},
          onClose: () {},
          api: _api(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The tab bar's labels, which carry a count suffix on two of them.
List<String> _tabLabels(WidgetTester tester) => [
  for (final tab in tester.widgetList<Tab>(find.byType(Tab))) tab.text ?? '',
];

void main() {
  testWidgets('a maker gets both writing tabs', (tester) async {
    await _pump(tester, 'Maker');

    expect(_tabLabels(tester), hasLength(5));
    expect(find.widgetWithText(Tab, 'Verify'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Reassign'), findsOneWidget);
  });

  testWidgets('an unknown template gets the reading tabs only', (tester) async {
    await _pump(tester, 'Regional Head');

    expect(_tabLabels(tester), hasLength(3));
    expect(find.widgetWithText(Tab, 'Verify'), findsNothing);
    expect(find.widgetWithText(Tab, 'Reassign'), findsNothing);
    // The reading tabs are all still there.
    expect(find.widgetWithText(Tab, 'Basic Info'), findsOneWidget);
    // Off for both templates for now.
    expect(find.widgetWithText(Tab, 'Activity'), findsNothing);
  });

  testWidgets('a checker gets neither writing tab', (tester) async {
    await _pump(tester, 'Checker');

    expect(_tabLabels(tester), hasLength(3));
    expect(find.widgetWithText(Tab, 'Verify'), findsNothing);
    expect(find.widgetWithText(Tab, 'Reassign'), findsNothing);
  });

  testWidgets('the Reassign tab opens on the right body', (tester) async {
    // Third in the maker's bar, behind Basic Info and Verify. The bar and the
    // view only line up if both are built from the same list.
    await _pump(tester, 'Maker', initialTab: CaseDetailTab.reassign);

    final controller = tester.widget<TabBar>(find.byType(TabBar)).controller;
    expect(controller!.index, 2);
    expect(find.text('Current Assignment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('asking for a dropped tab opens the first one instead', (
    tester,
  ) async {
    // The grid gates its row actions, but a stale route or a deep link could
    // still ask for Verify. Landing on Basic Info beats a range error.
    await _pump(tester, 'Checker', initialTab: CaseDetailTab.verify);

    // The panel owns its controller, so read it off the bar itself rather than
    // through DefaultTabController — there isn't one, and asking would answer
    // null and pass for the wrong reason.
    final controller = tester.widget<TabBar>(find.byType(TabBar)).controller;
    expect(controller, isNotNull);
    expect(controller!.length, 3);
    expect(controller.index, 0);
  });

  testWidgets('a dropped middle tab does not shift the body', (tester) async {
    // Reassign sits between Verify and Comments in the enum, so a maker's bar
    // and view only line up if both are built from the same list.
    await _pump(tester, 'Maker', initialTab: CaseDetailTab.comments);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
