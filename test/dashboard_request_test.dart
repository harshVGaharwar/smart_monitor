// What the dashboard asks the server for, and what it does with the answer.
//
// The queue is the server's decision: the page sends the signed-in user's
// employee code and role, and renders the rows that come back without applying
// a filter of its own. Both halves are pinned here — a request that dropped a
// parameter would ask for a queue the server cannot resolve, and a page that
// filtered again would hide rows the server had already vetted.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/models/login_response.dart';
import 'package:smart_monitor/pages/dashboard_page.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/data/master_data.dart';
import 'package:smart_monitor/theme/app_theme.dart';

import 'master_data_fixture.dart';

/// Every request the page made.
late List<http.BaseRequest> _sent;

String _body(List<Map<String, dynamic>> rows) => jsonEncode({
  'code': 0,
  'message': 'Upload Successful',
  'success': true,
  'data': {'rows': rows},
});

Map<String, dynamic> _row({
  required String customer,
  required String client,
  required String status,
}) => {
  'client_id': client,
  'customer_name': customer,
  'account_no': '11424036',
  'line_no': '50301271033004',
  'health_check_category': 'FD Exceptions',
  'sub_category': 'Excess lien marked in Core',
  'cpu': 'Chennai',
  'team': 'Disbursement Team',
  'status': status,
  'imported_at': '2026-08-08T11:18:08.918901Z',
};

Api _api(String body, {bool mastersFail = false}) => Api(
  ApiClient(
    client: MockClient((request) async {
      _sent.add(request);
      // The page reads its master lists alongside the queue. Answered here so
      // the dropdowns it hands the drawer are the ones the server sent, and so
      // the queue assertions below are not tripped by a second request.
      if (request.url.path.endsWith('/getMasterData')) {
        return mastersFail
            ? http.Response('{"message":"Master data is unavailable."}', 503)
            : http.Response(masterDataBody(), 200);
      }
      return http.Response(body, 200);
    }),
  ),
);

/// The queue read, picked out of everything the page sent.
http.BaseRequest get _queueRequest =>
    _sent.singleWhere((r) => r.url.path.endsWith('/get-smartpointer'));

LoginResponse _session({required String employeeCode, required String role}) =>
    LoginResponse(
      token: 'tok',
      refreshToken: 'ref',
      user: LoginUser(
        name: 'Ninad Thakur',
        employeeCode: employeeCode,
        role: role,
        menuList: const [
          MenuPermission(
            id: 1,
            menuName: 'Dashboard',
            profileId: 'P1',
            isActive: 'Y',
          ),
        ],
      ),
    );

Future<void> _pump(
  WidgetTester tester, {
  required String employeeCode,
  required String role,
  required String body,
  bool mastersFail = false,
}) async {
  tester.view.physicalSize = const Size(1700, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: DashboardPage(
        session: _session(employeeCode: employeeCode, role: role),
        api: _api(body, mastersFail: mastersFail),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _sent = []);
  tearDown(MasterData.reset);

  testWidgets('the page asks for the signed-in user\'s queue', (tester) async {
    await _pump(
      tester,
      employeeCode: 'OFF807292',
      role: 'Maker',
      body: _body([
        _row(
          customer: 'HEALTH CHECK SIDE LTD',
          client: '2000002',
          status: 'Pending with Health Checker',
        ),
      ]),
    );

    // Straight off the session — nothing here is hardcoded or defaulted, so a
    // second user signing in reads their own records.
    expect(_queueRequest.url.path, '/api/get-smartpointer');
    expect(_queueRequest.url.queryParameters, {
      'employeeCode': 'OFF807292',
      'role': 'Maker',
    });
    expect(find.text('HEALTH CHECK SIDE LTD'), findsOneWidget);
  });

  testWidgets('a checker asks with their own code and template', (
    tester,
  ) async {
    await _pump(
      tester,
      employeeCode: 'r14878',
      role: 'Checker',
      body: _body([
        _row(
          customer: 'CPU SIDE LTD',
          client: '1000001',
          status: 'Pending with CPU',
        ),
      ]),
    );

    expect(_queueRequest.url.queryParameters, {
      'employeeCode': 'r14878',
      'role': 'Checker',
    });
    expect(find.text('CPU SIDE LTD'), findsOneWidget);
  });

  testWidgets('every row the server sent reaches the grid', (tester) async {
    // Including one in the other side's status. The server vetted these rows
    // against the queue it was asked for; a page that filtered them again
    // would be second-guessing an answer it cannot improve on, and would drop
    // records on any workflow this build does not know about yet.
    await _pump(
      tester,
      employeeCode: 'OFF807292',
      role: 'Maker',
      body: _body([
        _row(
          customer: 'HEALTH CHECK SIDE LTD',
          client: '2000002',
          status: 'Pending with Health Checker',
        ),
        _row(
          customer: 'ESCALATED LTD',
          client: '3000003',
          status: 'Need Clarification',
        ),
      ]),
    );

    expect(find.text('HEALTH CHECK SIDE LTD'), findsOneWidget);
    expect(find.text('ESCALATED LTD'), findsOneWidget);
    expect(find.text('2 records'), findsOneWidget);
  });

  testWidgets('a rejected queue is shown as the failure it is', (tester) async {
    // What a missing parameter looks like coming back: the server refuses
    // rather than answering with everyone's rows, and the page shows the
    // message over its retry instead of an empty grid.
    await _pump(
      tester,
      employeeCode: '',
      role: '',
      body: jsonEncode({
        'code': 1,
        'message': 'employeeCode and role are required to read a queue.',
        'success': false,
        'data': null,
      }),
    );

    expect(
      find.text('employeeCode and role are required to read a queue.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the master lists are read alongside the queue', (tester) async {
    await _pump(
      tester,
      employeeCode: 'OFF807292',
      role: 'Maker',
      body: _body([
        _row(
          customer: 'HEALTH CHECK SIDE LTD',
          client: '2000002',
          status: 'Pending with Health Checker',
        ),
      ]),
    );

    // One call, no parameters — the lists do not depend on who is asking.
    final masters = _sent.singleWhere(
      (r) => r.url.path.endsWith('/getMasterData'),
    );
    expect(masters.method, 'GET');
    expect(masters.url.queryParameters, isEmpty);

    // In the cache the drawer's dropdowns and the upload screen both read.
    expect(MasterData.isLoaded, isTrue);
    expect(MasterData.cpus, masterCpus);
    expect(MasterData.reassignReasons, masterReassignReasons);
  });

  testWidgets('master data failing does not take the grid down with it', (
    tester,
  ) async {
    await _pump(
      tester,
      employeeCode: 'OFF807292',
      role: 'Maker',
      mastersFail: true,
      body: _body([
        _row(
          customer: 'HEALTH CHECK SIDE LTD',
          client: '2000002',
          status: 'Pending with Health Checker',
        ),
      ]),
    );

    // The rows loaded fine and are still on screen: the two reads are
    // independent, and blanking a working grid over a missing dropdown would
    // hide data the user came for.
    expect(find.text('HEALTH CHECK SIDE LTD'), findsOneWidget);

    // Said out loud rather than left to be discovered at the reassign dialog.
    expect(find.text('Master data is unavailable.'), findsOneWidget);

    // Empty rather than a bundled fallback — a dropdown offering a CPU the
    // server never sent would let a user route a case nowhere.
    expect(MasterData.isLoaded, isFalse);
    expect(MasterData.cpus, isEmpty);
  });
}
