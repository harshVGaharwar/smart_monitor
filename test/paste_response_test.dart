// A scratch harness for a captured response.
//
// Paste a payload into [_response], run, and read what the app made of it:
//
//     flutter test test/paste_response_test.dart
//
// It passes either way — a failure envelope is printed rather than thrown, so
// any response can be dropped in without rewriting an assertion. The real
// assertions live in `case_api_test.dart`.
//
// This reads the payload the way the dashboard does. `fetchSmartPointer` takes
// no arguments, so there is no request to invent — only the response matters.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/models/smart_pointer_request.dart';
import 'package:smart_monitor/services/case_api.dart';

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
  test('the pasted response, as the app reads it', () async {
    final api = Api(
      ApiClient(client: MockClient((_) async => http.Response(_response, 200))),
    );

    try {
      final result = await api.fetchSmartPointer(
        const SmartPointerRequest(employeeCode: 'OFF807292', role: 'Maker'),
      );
      // ignore: avoid_print
      print('''

  message   ${result.message}
  rows      ${result.rowCount}
  cases     ${result.cases.length}
''');
      for (final c in result.cases) {
        // ignore: avoid_print
        print('  ${c.exceptionCode}  ${c.customerName}  ${c.status.label}');
      }
      // ignore: avoid_print
      print('');
    } on ApiException catch (e) {
      // Printed, not rethrown: a rejected response is worth pasting in too.
      // ignore: avoid_print
      print('\n  rejected  ${e.message}\n');
    }
  });
}
