// Routing a record to another CPU.
//
// The tab opens on the assignment the record already has — the reviewer
// changes the one that is wrong rather than restating both — and the button
// behind it names the record, the destination and why, in one call.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/models/user_rights.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/data/master_data.dart';
import 'package:smart_monitor/widgets/case_detail_panel.dart';

import 'master_data_fixture.dart';

const _case = CaseItem(
  exceptionCode: '2287410-11930442-50301271033039',
  clientId: '2287410',
  customerName: 'NORTHGATE LOGISTICS LIMITED',
  accountNo: '11930442',
  cpu: 'Mumbai',
  team: 'Cam Renewal Team',
  status: CaseStatus.pendingWithHealthChecker,
);

late List<http.BaseRequest> _sent;
CaseItem? _changed;

Api _api({int status = 200}) => Api(
  ApiClient(
    client: MockClient((request) async {
      _sent.add(request);
      if (!request.url.path.endsWith('/reassign')) {
        return http.Response(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'success': true,
            'data': {'comments': <dynamic>[]},
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode(
          status == 200
              ? {
                'code': 0,
                'message': 'Successfully assigned to new user',
                'success': true,
                'data': 1,
              }
              : {'success': false, 'message': 'That CPU is not accepting work.'},
        ),
        status,
      );
    }),
  ),
);

Future<void> _pump(WidgetTester tester, {Api? api, CaseItem? item}) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CaseDetailPanel(
          caseItem: item ?? _case,
          initialTab: CaseDetailTab.reassign,
          tabs: tabsFor(UserRights.forRole('Maker')),
          currentUser: 'Maker',
          userId: 'OFF807292',
          role: 'Maker',
          onChanged: (c) => _changed = c,
          onClose: () {},
          api: api ?? _api(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<http.BaseRequest> _to(String path) => [
  for (final r in _sent)
    if (r.url.path.endsWith(path)) r,
];

/// Picks [option] from the dropdown currently showing [from].
Future<void> _choose(
  WidgetTester tester,
  String from,
  String option,
) async {
  await tester.tap(find.text(from).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _sent = [];
    _changed = null;
    // The panel is built on its own here, with no dashboard above it to fetch
    // the lists its dropdowns are drawn from.
    seedMasterData();
  });
  tearDown(MasterData.reset);

  testWidgets('the dropdowns open on where the record already is', (
    tester,
  ) async {
    await _pump(tester);

    // Both the banner and the two dropdowns, so the reviewer changes the one
    // that is wrong instead of restating both.
    expect(find.text('Mumbai'), findsWidgets);
    expect(find.text('Cam Renewal Team'), findsWidgets);
    expect(find.text('Select CPU...'), findsNothing);
    expect(find.text('Select Team...'), findsNothing);
  });

  testWidgets('a value the workflow does not name leaves it empty', (
    tester,
  ) async {
    // Rather than asserting on a dropdown value it cannot show.
    await _pump(
      tester,
      item: const CaseItem(
        exceptionCode: 'EXC-1',
        clientId: '2287410',
        customerName: 'ACME',
        accountNo: '1',
        cpu: 'Atlantis',
        team: 'Cam Renewal Team',
        status: CaseStatus.pendingWithHealthChecker,
      ),
    );

    expect(find.text('Select CPU...'), findsOneWidget);
  });

  testWidgets('confirming names the record, the destination and why', (
    tester,
  ) async {
    await _pump(tester);

    await _choose(tester, 'Mumbai', 'Chennai');
    await _choose(tester, 'Cam Renewal Team', 'Disbursement Team');
    await _choose(tester, 'Select reason...', 'Incorrect CPU mapping');
    await tester.enterText(
      find.byType(TextField).first,
      'Wrong team, sending this back.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Reassignment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final sent = _to('/reassign').single as http.Request;
    expect(sent.method, 'POST');
    expect(jsonDecode(sent.body), {
      'clientId': '2287410',
      'userId': 'OFF807292',
      'role': 'Maker',
      'cpu': 'Chennai',
      'team': 'Disbursement Team',
      'reason': 'Incorrect CPU mapping',
      'comments': 'Wrong team, sending this back.',
      'document': null,
    });

    // Back to the CPU side under its new team — the status move is what takes
    // the row out of the maker's grid.
    expect(_changed?.status, CaseStatus.pendingWithCpu);
    expect(_changed?.cpu, 'Chennai');
    expect(_changed?.team, 'Disbursement Team');
  });

  testWidgets('the service\'s own words are what the reviewer is told', (
    tester,
  ) async {
    await _pump(tester);

    await _choose(tester, 'Mumbai', 'Chennai');
    await tester.tap(find.text('Confirm Reassignment'));
    await tester.pumpAndSettle();

    // In a dialog the reader has to dismiss, since the row leaves their grid
    // behind it.
    expect(find.text('Reassigned'), findsOneWidget);
    expect(find.text('Successfully assigned to new user'), findsOneWidget);
    expect(_changed, isNull);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(_changed?.status, CaseStatus.pendingWithCpu);
  });

  testWidgets('a refused reassignment changes nothing on screen', (
    tester,
  ) async {
    await _pump(tester, api: _api(status: 400));

    await _choose(tester, 'Mumbai', 'Chennai');
    await tester.tap(find.text('Confirm Reassignment'));
    await tester.pumpAndSettle();

    expect(find.text('That CPU is not accepting work.'), findsOneWidget);
    // Nothing claimed the server did not accept, and the choice is still
    // there to try again with.
    expect(_changed, isNull);
    expect(find.text('Chennai'), findsWidgets);
  });
}
