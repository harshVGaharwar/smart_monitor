// The get-smartpointer response exactly as the service sends it, driven
// through the model and onto the dashboard grid.
//
// The payload here is a captured response, pasted unchanged — nulls where the
// file left a column empty, the numeric `sr_no`, .NET's minimum date, and the
// `status` a stored case carries. A server writing `sr_no` as text has its own
// test below. `dashboard_load_test.dart` covers the states
// around the fetch with a convenient body; this one pins the row contract
// itself, so a change to the envelope, `CaseItem` or the grid is caught
// against the real thing rather than against a body written to suit the code.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/models/cases_response.dart';
import 'package:smart_monitor/pages/dashboard_page.dart';
import 'package:smart_monitor/services/case_api.dart';
import 'package:smart_monitor/theme/app_theme.dart';

/// `GET /SmartAPI/get-smartpointer`, captured verbatim.
///
/// `message` really does read "Upload Successful" on this call too — the
/// service answers both reads with the same text. Nothing shows it; it is kept
/// so a local response stays diffable against a captured one.
const _dashboardResponse = '''
{
    "code": 0,
    "message": "Upload Successful",
    "body": null,
    "success": true,
    "data": {
        "rows": [
            {
                "client_id": "3332125",
                "customer_name": "LEHRY INSTRUMENTATION AND VALVES PVT LTD",
                "account_no": "11424036",
                "line_no": "50301271033004",
                "health_check_category": "FD Exceptions",
                "sub_category": "Excess lien marked in Core",
                "support_system": "787920",
                "core_system": "986920",
                "exception_category": "Exception",
                "reason": "Fd Lien Amount Mismatch Between Lmm And Core; To Be Reviewed And Rectified",
                "cpu": "Chennai",
                "team": "Disbursement Team",
                "segment": null,
                "facility": null,
                "sr_no": 0,
                "maker": "OFF550975",
                "checker": "r14878",
                "ls_srm_date": "0001-01-01",
                "status": "Pending with CPU",
                "imported_at": "2026-08-08T11:18:08.918901Z"
            }
        ]
    },
    "count": 0,
    "userName": null,
    "userCode": null,
    "branchName": null,
    "branchCode": null,
    "menu": null
}
''';

CaseApi _api([String body = _dashboardResponse]) => CaseApi(
  ApiClient(client: MockClient((_) async => http.Response(body, 200))),
);

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
  await tester.pumpAndSettle();
}

void main() {
  group('the get-smartpointer response', () {
    test('reads into the dashboard model', () {
      final response = CasesResponse.fromJson(jsonDecode(_dashboardResponse));

      expect(response.isSuccess, isTrue);
      expect(response.message, 'Upload Successful');
      // `count` is the field as the service stated it — 0 even here, on a
      // response plainly carrying a row — so the grid counts the rows it got.
      expect(response.count, 0);
      expect(response.rowCount, 1);
      expect(response.cases, hasLength(1));

      final item = response.cases.single;
      expect(item.clientId, '3332125');
      expect(item.customerName, 'LEHRY INSTRUMENTATION AND VALVES PVT LTD');
      expect(item.accountNo, '11424036');
      expect(item.lineNo, '50301271033004');
      expect(item.healthCheckCategory, 'FD Exceptions');
      expect(item.subCategory, 'Excess lien marked in Core');
      expect(item.supportSystem, '787920');
      expect(item.coreSystem, '986920');
      expect(item.exceptionCategory, 'Exception');
      expect(item.cpu, 'Chennai');
      expect(item.team, 'Disbursement Team');
      expect(item.maker, 'OFF550975');
      expect(item.checker, 'r14878');
      expect(item.status, CaseStatus.pendingWithCpu);
    });

    test('the shapes only this response uses are read, not shown raw', () {
      final item =
          CasesResponse.fromJson(jsonDecode(_dashboardResponse)).cases.single;

      // A null column is blank, not the text "null".
      expect(item.segment, '');
      expect(item.facility, '');
      // The service's stand-in for "not numbered" — serials start at 1.
      expect(item.srNo, '');
      // .NET's DateTime.MinValue means no date, not the year 1.
      expect(item.lsrmDate, isNull);
      // The response carries no id, so the natural key is the reference shown
      // in the detail header.
      expect(item.exceptionCode, '3332125-11424036-50301271033004');
      // `imported_at` is what the grid dates the row by.
      expect(item.updatedAt, DateTime.parse('2026-08-08T11:18:08.918901Z'));
    });

    test('a server writing sr_no as text reads the same', () {
      // The service types this one as a number and sends 0 for a row it never
      // numbered. This server sent \"0\" as text for a while; pointing the app
      // at either has to leave the same blank cell.
      final asText = CasesResponse.fromJson(
        jsonDecode(
              _dashboardResponse.replaceFirst('"sr_no": 0', '"sr_no": "0"'),
            )
            as Map<String, dynamic>,
      );

      expect(asText.rows.single.srNo, 0);
      expect(asText.cases.single.srNo, '');
    });

    testWidgets('the row reaches the grid', (tester) async {
      await _pump(tester, _api());

      expect(
        find.text('LEHRY INSTRUMENTATION AND VALVES PVT LTD'),
        findsOneWidget,
      );
      expect(find.text('3332125'), findsWidgets);
      expect(find.text('1 record'), findsOneWidget);
      // The status the row carries, on its badge — the grid's filter works off
      // this, so a row arriving without one would silently pile into the
      // default bucket.
      expect(find.text('Pending with CPU'), findsWidgets);
    });
  });
}
