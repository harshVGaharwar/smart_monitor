// A scratch harness for a captured `read-excel` response.
//
// Paste a payload into [_response], run, and read what the app made of it:
//
//     flutter test test/read_excel_response_test.dart
//
// It passes either way — a rejected file is printed rather than thrown, so any
// response can be dropped in without rewriting an assertion. The endpoint's
// real assertions live in `case_api_test.dart`.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/data/master_data.dart';
import 'package:smart_monitor/services/case_api.dart';

import 'master_data_fixture.dart';

// ---------------------------------------------------------------------------
// PASTE YOUR RESPONSE HERE
// ---------------------------------------------------------------------------
const _response = '''
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
                "ls_srm_date": "0001-01-01"
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

void main() {
  // Without these the harness reports every CPU and team unresolved and every
  // row in error, which says nothing about the pasted payload — the app fetches
  // the lists from `/getMasterData`, and nothing here does that.
  setUp(seedMasterData);
  tearDown(MasterData.reset);

  test('the pasted response, as the app reads it', () async {
    final api = Api(
      ApiClient(client: MockClient((_) async => http.Response(_response, 200))),
    );

    try {
      final result = await api.uploadCasesFile(
        bytes: Uint8List(0),
        filename: 'cases.xlsx',
      );
      final outcome = result.toOutcome();
      // ignore: avoid_print
      print('''message   ${result.message}
rows      ${result.rowCount}
  ready     ${outcome.valid.length}
  errors    ${outcome.rows.length - outcome.valid.length}
''');
      for (final row in result.rows) {
        // ignore: avoid_print
        print(
          '  ${row.id}  ${row.clientId}  ${row.customerName}  '
          '${row.cpu ?? '(cpu unresolved)'}  '
          '${row.team ?? '(team unresolved)'}',
        );
      }
      // ignore: avoid_print
      print('');
    } on ApiException catch (e) {
      // Printed, not rethrown: a rejected file is worth pasting in too.
      // ignore: avoid_print
      print('\n  rejected  ${e.message}\n');
    }
  });
}
