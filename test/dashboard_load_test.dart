// The dashboard reads its rows from GET /get-smartpointer rather than the
// in-memory mock list, so the states around that fetch — loading, failure,
// retry, and an empty store — are what this covers.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/pages/dashboard_page.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/theme/app_theme.dart';

Map<String, dynamic> _row({
  String clientId = '4943581',
  String customerName = 'ACME',
  String status = 'Pending',
}) => {
  'client_id': clientId,
  'customer_name': customerName,
  'account_no': '50200031339584',
  'line_no': '5',
  'health_check_category': 'CAM Expiry Health Check',
  'sub_category': 'Sub',
  'cpu': 'Mumbai',
  'team': 'Cam Renewal Team',
  'status': status,
};

Future<void> _pump(WidgetTester tester, CaseApi api) async {
  tester.view.physicalSize = const Size(1700, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: DashboardPage(user: 'ninad.thakur', api: api),
    ),
  );
}

void main() {
  testWidgets('rows from the endpoint reach the grid', (tester) async {
    final api = CaseApi(
      ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'rows': [
                _row(customerName: 'ACME'),
                _row(clientId: '5120774', customerName: 'SUNRISE'),
              ],
            }),
            200,
          ),
        ),
      ),
    );

    await _pump(tester, api);
    await tester.pumpAndSettle();

    expect(find.text('ACME'), findsOneWidget);
    expect(find.text('SUNRISE'), findsOneWidget);
    expect(find.text('2 records'), findsOneWidget);
  });

  testWidgets('a spinner shows until the first load lands', (tester) async {
    final gate = Completer<http.Response>();
    final api = CaseApi(
      ApiClient(client: MockClient((_) => gate.future)),
    );

    await _pump(tester, api);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete(
      http.Response(
        jsonEncode({
          'rows': [_row()],
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('ACME'), findsOneWidget);
  });

  testWidgets('a failed load explains itself and offers a retry', (
    tester,
  ) async {
    var calls = 0;
    final api = CaseApi(
      ApiClient(
        client: MockClient((_) async {
          calls++;
          // Fails first, succeeds on the retry.
          if (calls == 1) {
            return http.Response(
              jsonEncode({'message': 'The database is unavailable.'}),
              503,
            );
          }
          return http.Response(
            jsonEncode({
              'rows': [_row()],
            }),
            200,
          );
        }),
      ),
    );

    await _pump(tester, api);
    await tester.pumpAndSettle();

    // The server's own message, not a generic failure.
    expect(find.text('The database is unavailable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('The database is unavailable.'), findsNothing);
    expect(find.text('ACME'), findsOneWidget);
  });

  testWidgets('an empty store is the grid empty state, not an error', (
    tester,
  ) async {
    final api = CaseApi(
      ApiClient(
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'rows': <dynamic>[], 'count': 0}), 200),
        ),
      ),
    );

    await _pump(tester, api);
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsNothing);
    expect(find.text('No records match the current filters.'), findsOneWidget);
    expect(find.text('0 records'), findsOneWidget);
  });

  testWidgets('refresh re-reads the endpoint', (tester) async {
    var calls = 0;
    final api = CaseApi(
      ApiClient(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'rows': [
                for (var i = 0; i < calls; i++)
                  _row(clientId: 'CL$i', customerName: 'Cust$i'),
              ],
            }),
            200,
          );
        }),
      ),
    );

    await _pump(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('1 record'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('2 records'), findsOneWidget);
  });
}
