// Opening a record from the grid reads its thread and its files.
//
// The panel's own tests build it directly; this covers the path the app
// actually takes — dashboard, row action, end drawer, panel — so a drawer that
// is never built, or built without the signed-in session's api, is caught here
// rather than in front of a user.
//
// Neither read is gated on a template: both sides of the handover open the same
// record and see the same thread and the same attachments.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/models/login_response.dart';
import 'package:smart_monitor/pages/dashboard_page.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/theme/app_theme.dart';

late List<http.BaseRequest> _sent;

String _envelope(Object? data) =>
    jsonEncode({'code': 0, 'message': 'ok', 'success': true, 'data': data});

const _row = <String, dynamic>{
  'client_id': '1130488',
  'customer_name': 'TRANSIT ELECTRONICS LTD',
  'account_no': '11264580',
  'line_no': '50301271033004',
  'health_check_category': 'FD Exceptions',
  'sub_category': 'Excess lien marked in Core',
  'cpu': 'Chennai',
  'team': 'Disbursement Team',
  'imported_at': '2026-08-08T11:18:08.918901Z',
};

Api _api(String status) => Api(
  ApiClient(
    client: MockClient((request) async {
      _sent.add(request);
      final path = request.url.path;
      if (path.endsWith('/get-smartpointer')) {
        return http.Response(
          _envelope({
            'rows': [
              {..._row, 'status': status},
            ],
          }),
          200,
        );
      }
      if (path.endsWith('/getDocuments')) {
        return http.Response(
          _envelope({
            'documents': [
              {
                'clientId': '1130488',
                'userID': 'OFF807292',
                'fileName': 'lien.xlsx',
                'uploadedBy': 'Maker',
                'uploadedDate': '2026-08-11T12:13:00.000Z',
              },
            ],
          }),
          200,
        );
      }
      if (path.endsWith('/getComments')) {
        return http.Response(_envelope({'comments': []}), 200);
      }
      return http.Response(_envelope(1), 200);
    }),
  ),
);

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

/// Signs in, waits for the queue, then opens the one row's drawer the way a
/// reader does — the eye on its Actions column.
Future<void> _openRecord(
  WidgetTester tester, {
  required String role,
  required String employeeCode,
  required String status,
}) async {
  tester.view.physicalSize = const Size(1700, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: DashboardPage(
        session: _session(employeeCode: employeeCode, role: role),
        api: _api(status),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // The Actions column is the last of many, so it starts off to the right of
  // the viewport — scrolled to rather than tapped blind, which would send the
  // gesture at empty canvas and quietly open nothing.
  final view = find.byIcon(Icons.visibility_outlined).first;
  await tester.ensureVisible(view);
  await tester.pumpAndSettle();
  await tester.tap(view);
  await tester.pumpAndSettle();
}

List<http.BaseRequest> _to(String path) => [
  for (final r in _sent)
    if (r.url.path.endsWith(path)) r,
];

void main() {
  setUp(() => _sent = []);

  testWidgets('the health check side’s drawer reads the files', (tester) async {
    await _openRecord(
      tester,
      role: 'Maker',
      employeeCode: 'OFF807292',
      status: 'Pending with Health Checker',
    );

    final read = _to('/getDocuments').single;
    expect(read.method, 'GET');
    // The record opened, and the signed-in reader — not the row's own maker.
    expect(read.url.queryParameters, {
      'clientId': '1130488',
      'userID': 'OFF807292',
    });
  });

  testWidgets('the CPU side’s drawer reads them too', (tester) async {
    await _openRecord(
      tester,
      role: 'Checker',
      employeeCode: 'r14878',
      status: 'Pending with CPU',
    );

    expect(_to('/getDocuments').single.url.queryParameters, {
      'clientId': '1130488',
      'userID': 'r14878',
    });
  });

  testWidgets('the thread is read alongside them', (tester) async {
    // One open, both reads — a drawer that fetched only one of the two would
    // leave the other tab looking like the case has nothing on it.
    await _openRecord(
      tester,
      role: 'Checker',
      employeeCode: 'r14878',
      status: 'Pending with CPU',
    );

    expect(_to('/getComments'), hasLength(1));
    expect(_to('/getDocuments'), hasLength(1));
  });

  testWidgets('the files land on the tab the reader opens', (tester) async {
    await _openRecord(
      tester,
      role: 'Checker',
      employeeCode: 'r14878',
      status: 'Pending with CPU',
    );

    final tab = find.textContaining('Documents').first;
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();

    expect(find.text('lien.xlsx'), findsOneWidget);
  });
}
