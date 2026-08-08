// Service-level cover for the three endpoints the app actually talks to.
//
// Everything else that exercises them does so through a screen, which means a
// method with no widget behind it — or an error branch a screen swallows — can
// regress unseen. These tests stand between `CaseApi` and a stubbed transport
// instead: what goes out on the wire, and what comes back out of the model.
//
// The stub answers exactly what the Dart Frog backend answers, envelope and
// all, so a change to the contract fails here before it reaches a screen.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/core/constants.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/models/pending_case.dart';
import 'package:smart_monitor/services/case_api.dart';

/// The envelope every endpoint shares, in the order the service sends it.
Map<String, dynamic> _envelope(
  Object? data, {
  int code = 0,
  bool success = true,
  String message = 'Upload Successful',
  int count = 0,
}) => {
  'code': code,
  'message': message,
  'body': null,
  'success': success,
  'data': data,
  'count': count,
  'userName': null,
  'userCode': null,
  'branchName': null,
  'branchCode': null,
  'menu': null,
};

/// A row as the two read endpoints return it — `smartRow` shape, with blanks
/// as nulls and `sr_no` a number.
Map<String, dynamic> _wireRow({
  String lineNo = '5',
  String cpu = 'Mumbai',
  String? status,
}) => {
  'client_id': '4943581',
  'customer_name': 'ACME',
  'account_no': '50200031339584',
  'line_no': lineNo,
  'health_check_category': 'CAM Expiry Health Check',
  'sub_category': 'Sub',
  'support_system': 'LMM',
  'core_system': 'FC',
  'exception_category': 'Exception',
  'reason': 'Renewal pending',
  'cpu': cpu,
  'team': 'Cam Renewal Team',
  'segment': null,
  'facility': null,
  'sr_no': 0,
  'maker': 'mk',
  'checker': 'ck',
  'ls_srm_date': '0001-01-01',
  if (status != null) 'status': status,
};

/// Requests the stub received, newest last.
late List<http.BaseRequest> _sent;

/// A [CaseApi] over a transport that answers [respond] and records what it was
/// asked. [rawBodies] keeps the decoded text of each request, which is how a
/// multipart upload is inspected.
CaseApi _api(
  http.Response Function(http.Request request) respond, {
  List<String>? rawBodies,
}) {
  return CaseApi(
    ApiClient(
      baseUrl: 'https://example.test/api',
      client: MockClient((request) async {
        _sent.add(request);
        rawBodies?.add(request.body);
        return respond(request);
      }),
    ),
  );
}

/// A [CaseApi] answering every call with [body] as JSON.
CaseApi _answering(Object? body, {int status = 200}) => _api(
  (_) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  ),
);

/// The JSON body of the last request the stub received.
Map<String, dynamic> _lastJson() =>
    jsonDecode((_sent.last as http.Request).body) as Map<String, dynamic>;

/// The rows of the last request's body.
List<Map<String, dynamic>> _lastRows() => [
  for (final row in _lastJson()['rows'] as List) row as Map<String, dynamic>,
];

void main() {
  setUp(() => _sent = []);

  group('GET ${ApiEndpoints.smartPointer}', () {
    test('reads the stored cases off the envelope', () async {
      final api = _answering(
        _envelope({
          'rows': [
            _wireRow(status: 'Pending with CPU'),
            _wireRow(lineNo: '6', status: 'Verified'),
          ],
        }),
      );

      final response = await api.fetchSmartPointer();

      expect(_sent.single.method, 'GET');
      expect(_sent.single.url.path, '/api/get-smartpointer');
      expect(response.rowCount, 2);

      final cases = response.cases;
      expect(cases.first.clientId, '4943581');
      expect(cases.first.status, CaseStatus.pendingWithCpu);
      expect(cases.last.status, CaseStatus.verified);
      // The natural key, since the wire carries no id of its own.
      expect(cases.first.exceptionCode, '4943581-50200031339584-5');
    });

    test('an empty store is a result, not an error', () async {
      final api = _answering(_envelope({'rows': <dynamic>[]}));

      final response = await api.fetchSmartPointer();

      expect(response.isSuccess, isTrue);
      expect(response.rowCount, 0);
    });

    test('a failure the envelope reports on a 200 is still raised', () async {
      final api = _answering(
        _envelope(
          null,
          code: 1,
          success: false,
          message: 'The database is unavailable.',
        ),
      );

      // A 200 whose envelope says otherwise must not reach the grid as an
      // empty result — the dashboard would show "no cases" for an outage.
      await expectLater(
        api.fetchSmartPointer(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'The database is unavailable.',
          ),
        ),
      );
    });

    test('an expired session surfaces as an unauthorised failure', () async {
      final api = _answering({'message': 'Session expired.'}, status: 401);

      await expectLater(
        api.fetchSmartPointer(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
              .having((e) => e.message, 'message', 'Session expired.'),
        ),
      );
    });
  });

  group('POST ${ApiEndpoints.uploadCases}', () {
    test('posts the workbook as multipart, stating the file type', () async {
      final bodies = <String>[];
      final api = _api(
        (_) => http.Response(
          jsonEncode(_envelope({'rows': [_wireRow()]})),
          200,
          headers: {'content-type': 'application/json'},
        ),
        rawBodies: bodies,
      );

      await api.uploadCasesFile(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'HealthCheck.XLSX',
      );

      expect(_sent.single.method, 'POST');
      expect(_sent.single.url.path, '/api/read-excel');
      expect(_sent.single.headers['content-type'],
          contains('multipart/form-data'));
      expect(bodies.single, contains('name="file"'));
      expect(bodies.single, contains('filename="HealthCheck.XLSX"'));
      // Stated alongside the part and lowercased, because the server cannot
      // rely on a browser's filename.
      expect(bodies.single, contains('name="fileType"'));
      expect(bodies.single, contains('xlsx'));
    });

    test('hands back rows numbered by their place in the file', () async {
      final api = _answering(
        _envelope({
          'rows': [_wireRow(), _wireRow(lineNo: '6'), _wireRow(lineNo: '7')],
        }),
      );

      final response = await api.uploadCasesFile(
        bytes: Uint8List.fromList([1]),
        filename: 'cases.csv',
      );

      final rows = response.rows;
      expect(rows.map((r) => r.id), [1, 2, 3]);
      expect(rows.first, isA<PendingCase>());
      expect(rows.first.customerName, 'ACME');
      // A null column is a blank cell, not the text "null".
      expect(rows.first.segment, '');
      // 0 means the file stated no serial number.
      expect(rows.first.facilitySrNo, '');
    });

    test('a rejected file raises the message the server gave', () async {
      final api = _answering(
        _envelope(
          null,
          code: 1,
          success: false,
          message: 'The file is missing required column(s): CPU.',
        ),
        status: 422,
      );

      await expectLater(
        api.uploadCasesFile(
          bytes: Uint8List.fromList([1]),
          filename: 'cases.xlsx',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            // Passed through as it arrived: it names the column to fix.
            'The file is missing required column(s): CPU.',
          ),
        ),
      );
    });

    test('a 200 carrying nothing usable says so, and says what arrived',
        () async {
      final api = _answering({'ok': true, 'data2': <dynamic>[]});

      await expectLater(
        api.uploadCasesFile(
          bytes: Uint8List.fromList([1]),
          filename: 'cases.xlsx',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', contains('returned no rows'))
              // Naming the shape sends the reader to the endpoint rather than
              // back to their spreadsheet.
              .having((e) => e.message, 'message', contains('ok, data2')),
        ),
      );
    });
  });

  group('POST ${ApiEndpoints.upddateCase}', () {
    /// A reviewed upload row, as the results table hands it to the submit.
    PendingCase pending({String lineNo = '5'}) => PendingCase(
      clientId: '4943581',
      customerName: 'ACME',
      accountNo: '50200031339584',
      lineNo: lineNo,
      subCategory: 'Sub',
      supportSystem: 'LMM',
      coreSystem: 'FC',
      maker: 'mk',
      checker: 'ck',
      segment: 'Retail',
      facility: 'Cash Credit',
      facilitySrNo: '1',
      lsSrmDate: '2026-07-21',
      healthCheckCategory: 'CAM Expiry Health Check',
      exceptionCategory: 'Exception',
      reason: 'Renewal pending',
      cpu: 'Mumbai',
      actionableTeam: 'Cam Renewal Team',
    );

    /// What the backend answers a successful submit with.
    Map<String, dynamic> stored(int total, {String? status}) => _envelope(
      {
        'rows': [
          for (var i = 0; i < total; i++)
            {
              ..._wireRow(lineNo: '${i + 5}'),
              'sr_no': '1',
              'status': status ?? 'Pending with CPU',
            },
        ],
        'inserted': total,
        'updated': 0,
        'total': total,
      },
      message: 'Updated Successfully',
      count: total,
    );

    test('sends the approved rows in the request model', () async {
      final api = _answering(stored(2));

      await api.importCases([pending(), pending(lineNo: '6')]);

      expect(_sent.single.method, 'POST');
      expect(_sent.single.url.path, '/api/update-smartpointer');

      final rows = _lastRows();
      expect(rows, hasLength(2));
      expect(rows.first['client_id'], '4943581');
      expect(rows.first['line_no'], '5');
      expect(rows.last['line_no'], '6');
      // The resolved values, not the file's raw text.
      expect(rows.first['cpu'], 'Mumbai');
      expect(rows.first['team'], 'Cam Renewal Team');
    });

    test('every column goes out, the serial number as text', () async {
      final api = _answering(stored(1));

      await api.importCases([pending()]);

      final row = _lastRows().single;
      // The whole model, so a row that omitted a column does not blank what is
      // stored against the case.
      expect(row, hasLength(19));
      expect(row['sr_no'], '1');
      expect(row['facility'], 'Cash Credit');
      expect(row['ls_srm_date'], '2026-07-21');
      // Present and null: an upload states no status, and the server leaves a
      // reviewed case's status alone rather than reading a blank as a reset.
      expect(row.containsKey('status'), isTrue);
      expect(row['status'], isNull);
    });

    test('reads the stored rows and the count back', () async {
      final api = _answering(stored(2));

      final response = await api.importCases([pending(), pending(lineNo: '6')]);

      expect(response.total, 2);
      expect(response.message, 'Updated Successfully');
      expect(response.hasRows, isTrue);
      expect(response.rows, hasLength(2));
      // What the store settled on, which the client never sent.
      expect(response.rows.first.status, 'Pending with CPU');
      expect(response.summary(), '2 case(s) imported');
    });

    test('a server reporting no count is trusted for what was sent', () async {
      final api = _answering(_envelope(null, message: 'Updated Successfully'));

      final response = await api.importCases([pending(), pending(lineNo: '6')]);

      // The rows were written; claiming zero would be worse than trusting
      // what went out.
      expect(response.total, 2);
      expect(response.rows, isEmpty);
    });

    test('an empty submit never reaches the network', () async {
      final api = _answering(stored(0));

      await expectLater(
        api.importCases([]),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'There were no rows to import.',
          ),
        ),
      );
      expect(_sent, isEmpty);
    });

    test('a refused submit is raised rather than reported as imported',
        () async {
      final api = _answering(
        _envelope(
          null,
          code: 1,
          success: false,
          message: 'The database is unavailable.',
        ),
      );

      await expectLater(
        api.importCases([pending()]),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'The database is unavailable.',
          ),
        ),
      );
    });

    test('a single case carries its status and its natural key', () async {
      final api = _answering(stored(1, status: 'Verified'));

      final response = await api.updateCase(
        CaseItem(
          exceptionCode: 'EXC-1',
          clientId: '4943581',
          customerName: 'ACME',
          accountNo: '50200031339584',
          lineNo: '5',
          status: CaseStatus.verified,
          facility: 'Cash Credit',
          facilitySrNo: '1',
          lsrmDate: DateTime.utc(2026, 7, 21),
          cpu: 'Mumbai',
          team: 'Cam Renewal Team',
        ),
      );

      final row = _lastRows().single;
      expect(row['status'], 'Verified');
      // Without the triple the server cannot find the row to update.
      expect(row['client_id'], '4943581');
      expect(row['account_no'], '50200031339584');
      expect(row['line_no'], '5');
      // Carried through though the detail screen never shows them.
      expect(row['facility'], 'Cash Credit');
      expect(row['sr_no'], '1');
      expect(row['ls_srm_date'], '2026-07-21T00:00:00.000Z');

      expect(response.total, 1);
      expect(response.rows.single.status, 'Verified');
    });

    test('a failed save is raised so the panel can keep the record', () async {
      final api = _answering({'message': 'Not allowed.'}, status: 403);

      await expectLater(
        api.updateCase(
          const CaseItem(
            exceptionCode: 'EXC-1',
            clientId: '1',
            customerName: 'ACME',
            accountNo: '2',
            lineNo: '3',
            status: CaseStatus.verified,
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.message, 'message',
            'Not allowed.')),
      );
    });
  });
}
