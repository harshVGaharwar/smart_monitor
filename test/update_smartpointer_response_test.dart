// A scratch harness for a real `update-smartpointer` response.
//
// Paste a payload into [_response], run, and read what the models made of it:
//
//     flutter test test/update_smartpointer_response_test.dart
//
// It passes either way — a failure envelope is printed rather than thrown, so
// any response can be dropped in without rewriting an assertion. The real
// assertions for this endpoint live in `case_api_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/models/pending_case.dart';
import 'package:smart_monitor/services/case_api.dart';

// ---------------------------------------------------------------------------
// PASTE YOUR RESPONSE HERE
// ---------------------------------------------------------------------------
const _response = '''
{
  "rows": [
    {
     
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
      "segment": "",
      "facility": "",
      "sr_no": null,
      "maker": "OFF550975",
      "checker": "r14878",
      "ls_srm_date": null,
      "status": "Pending with CPu "
    }
  ]
}
''';

void main() {
  test('the pasted response, as the app reads it', () async {
    final api = Api(
      ApiClient(client: MockClient((_) async => http.Response(_response, 200))),
    );

    try {
      final result = await api.updateCases([_row()]);
      // ignore: avoid_print
      print('''

  message   ${result.message ?? '(none)'}
  count     ${result.updatedCount ?? '(the server sent none)'}
  total     ${result.total}
  rows      ${result.rows.length}
  summary   ${result.summary()}
''');
    } on ApiException catch (e) {
      // Printed, not rethrown: a rejected response is a thing worth pasting in
      // and looking at too.
      // ignore: avoid_print
      print('\n  rejected  ${e.message}\n');
    }
  });
}

/// One row to send, so the call has a body. The response is stubbed, so what
/// is in it does not matter.
PendingCase _row() => PendingCase(
  clientId: 'CL1',
  customerName: 'Cust1',
  accountNo: 'ACC1',
  lineNo: 'L1',
  subCategory: '',
  supportSystem: '',
  coreSystem: '',
  maker: '',
  checker: '',
);
