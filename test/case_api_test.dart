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
import 'package:smart_monitor/models/add_comment_request.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/models/comment_response.dart';
import 'package:smart_monitor/models/get_comments_request.dart';
import 'package:smart_monitor/models/reassign_request.dart';
import 'package:smart_monitor/models/verify_request.dart';
import 'package:smart_monitor/models/pending_case.dart';
import 'package:smart_monitor/models/smart_pointer_request.dart';
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

/// A [Api] over a transport that answers [respond] and records what it was
/// asked. [rawBodies] keeps the decoded text of each request, which is how a
/// multipart upload is inspected.
Api _api(
  http.Response Function(http.Request request) respond, {
  List<String>? rawBodies,
}) {
  return Api(
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

/// A [Api] answering every call with [body] as JSON.
Api _answering(Object? body, {int status = 200}) => _api(
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

/// Whose queue the read tests ask for. The endpoint has no unfiltered read,
/// so every call carries one.
const _queue = SmartPointerRequest(employeeCode: 'OFF807292', role: 'Maker');

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

      final response = await api.fetchSmartPointer(_queue);

      expect(_sent.single.method, 'GET');
      expect(_sent.single.url.path, '/api/get-smartpointer');
      // The whole point of the call: the server reads a queue from these two,
      // and a request that dropped one would come back as somebody else's
      // rows or as none.
      expect(_sent.single.url.queryParameters, {
        'employeeCode': 'OFF807292',
        'role': 'Maker',
      });
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

      final response = await api.fetchSmartPointer(_queue);

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
        api.fetchSmartPointer(_queue),
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
        api.fetchSmartPointer(_queue),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
              .having((e) => e.message, 'message', 'Session expired.'),
        ),
      );
    });

    test('a transport failure surfaces as a network error', () async {
      final api = _api((_) => throw http.ClientException('no route'));

      // Told apart from a server that answered, because only this one is worth
      // a retry button.
      await expectLater(
        api.fetchSmartPointer(_queue),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isNetworkError, 'isNetworkError', isTrue)
              .having((e) => e.message, 'message', contains('no route')),
        ),
      );
    });

    test('a gateway page on a 200 is raised, not read as no cases', () async {
      final api = _api(
        (_) => http.Response('<html>502 Bad Gateway</html>', 200),
      );

      // The status line says the request worked; the body never came from this
      // service. Reading it as zero rows would show an empty grid for an
      // outage.
      await expectLater(
        api.fetchSmartPointer(_queue),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('502 Bad Gateway'),
          ),
        ),
      );
    });
  });

  group('POST ${ApiEndpoints.login}', () {
    /// What the sign-in service answers, raw rather than enveloped.
    Map<String, dynamic> session({
      String role = 'Supervisor',
      List<Map<String, dynamic>>? menu,
    }) => {
      'token': 'tok-123',
      'refreshToken': 'ref-456',
      'user': {
        'id': 7,
        'name': 'Ninad Thakur',
        'employeeCode': 'n2346',
        'role': role,
        'profileId': 'P1',
        'menuList':
            menu ??
            [
              {
                'id': 1,
                'menuName': 'Dashboard',
                'profileId': 'P1',
                'isActive': 'Y',
              },
              {'id': 2, 'menuName': 'MIS', 'profileId': 'P1', 'isActive': 'N'},
            ],
      },
    };

    test('posts the credentials in the service\'s own key casing', () async {
      final api = _answering(session());

      await api.login(name: 'ninad.thakur', password: 's3cret');

      expect(_sent.single.method, 'POST');
      expect(_sent.single.url.path, '/api/login');

      final body = _lastJson();
      // Mirrored from the service, not tidied: `Name` and `LOCATIONCODE` are
      // capitalised and `password` is not, and the server matches on that.
      expect(body['Name'], 'ninad.thakur');
      expect(body['password'], 's3cret');
      expect(body.containsKey('LOCATIONCODE'), isTrue);
      // Hardcoded until the employee code can be resolved for real.
      expect(body['EmployeeCode'], 'n2346');
      expect(body, hasLength(14));
    });

    test('reads the session and the menu back', () async {
      final api = _answering(session());

      final response = await api.login(name: 'ninad.thakur', password: 'x');

      expect(response.token, 'tok-123');
      expect(response.refreshToken, 'ref-456');
      expect(response.user.name, 'Ninad Thakur');
      expect(response.user.role, 'Supervisor');
      // Closed menus arrive too, flagged rather than omitted.
      expect(response.user.menuList, hasLength(2));
      expect(response.user.menuList.first.isEnabled, isTrue);
      expect(response.user.menuList.last.isEnabled, isFalse);
    });

    test('a refused sign-in raises the message the server gave', () async {
      final api = _answering({'message': 'Invalid credentials.'}, status: 401);

      await expectLater(
        api.login(name: 'ninad.thakur', password: 'wrong'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
              .having((e) => e.message, 'message', 'Invalid credentials.'),
        ),
      );
    });

    test('a 200 carrying no token is raised, not signed in', () async {
      final api = _answering({'token': '', 'user': <String, dynamic>{}});

      // Letting this through would push a dashboard that cannot authenticate a
      // single call, which reads as an outage rather than a bad password.
      await expectLater(
        api.login(name: 'ninad.thakur', password: 'x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Sign-in failed'),
          ),
        ),
      );
    });

    test('a body that is not an object is raised', () async {
      final api = _answering(<dynamic>[]);

      await expectLater(
        api.login(name: 'ninad.thakur', password: 'x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('unexpected response'),
          ),
        ),
      );
    });
  });

  group('POST ${ApiEndpoints.uploadCases}', () {
    test('posts the workbook as multipart, stating the file type', () async {
      final bodies = <String>[];
      final api = _api(
        (_) => http.Response(
          jsonEncode(
            _envelope({
              'rows': [_wireRow()],
            }),
          ),
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
      expect(
        _sent.single.headers['content-type'],
        contains('multipart/form-data'),
      );
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
      expect(rows.first.srNo, '');
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

    test(
      'a 200 carrying nothing usable is raised, not read as zero rows',
      () async {
        final api = _answering({'ok': true, 'data2': <dynamic>[]});

        await expectLater(
          api.uploadCasesFile(
            bytes: Uint8List.fromList([1]),
            filename: 'cases.xlsx',
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('returned no rows'),
            ),
          ),
        );
      },
    );

    test(
      'an empty 200 body is reported rather than read as an empty file',
      () async {
        final api = _api((_) => http.Response('', 200));

        // A 200 with nothing behind it is a broken endpoint, not a workbook with
        // no data rows, and the upload card has to say so.
        await expectLater(
          api.uploadCasesFile(
            bytes: Uint8List.fromList([1]),
            filename: 'cases.xlsx',
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              'The server sent an empty response.',
            ),
          ),
        );
      },
    );

    test('a name carrying no extension still states the file type', () async {
      final bodies = <String>[];
      final api = _api(
        (_) => http.Response(
          jsonEncode(
            _envelope({
              'rows': [_wireRow()],
            }),
          ),
          200,
          headers: {'content-type': 'application/json'},
        ),
        rawBodies: bodies,
      );

      await api.uploadCasesFile(
        bytes: Uint8List.fromList([1]),
        filename: 'workbook',
      );

      expect(_sent.single.url.path, '/api/read-excel');
      // Sent empty rather than omitted: the server reads the field either way,
      // and a missing part is harder to tell from a truncated upload.
      expect(bodies.single, contains('name="fileType"'));
    });

    test(
      'an upload that never reaches the server is a network error',
      () async {
        final api = _api(
          (_) => throw http.ClientException('connection closed'),
        );

        await expectLater(
          api.uploadCasesFile(
            bytes: Uint8List.fromList([1]),
            filename: 'cases.xlsx',
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.isNetworkError, 'isNetworkError', isTrue)
                .having(
                  (e) => e.message,
                  'message',
                  contains('connection closed'),
                ),
          ),
        );
      },
    );
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
      srNo: '1',
      lsSrmDate: '2026-07-21',
      healthCheckCategory: 'CAM Expiry Health Check',
      exceptionCategory: 'Exception',
      reason: 'Renewal pending',
      cpu: 'Mumbai',
      team: 'Cam Renewal Team',
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

      await api.updateCases([pending(), pending(lineNo: '6')]);

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

      await api.updateCases([pending()]);

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

      final response = await api.updateCases([pending(), pending(lineNo: '6')]);

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

      final response = await api.updateCases([pending(), pending(lineNo: '6')]);

      // The rows were written; claiming zero would be worse than trusting
      // what went out.
      expect(response.total, 2);
      expect(response.rows, isEmpty);
    });

    test('an empty submit never reaches the network', () async {
      final api = _answering(stored(0));

      await expectLater(
        api.updateCases([]),
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

    test(
      'a refused submit is raised rather than reported as imported',
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
          api.updateCases([pending()]),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              'The database is unavailable.',
            ),
          ),
        );
      },
    );
  });

  group('POST ${ApiEndpoints.verify}', () {
    const verifying = VerifyRequest(
      clientId: '2287410',
      userId: 'OFF807292',
      role: 'Maker',
      comments: 'Lien released, checked in core.',
      isVerified: true,
    );

    test('the record is named, not restated', () async {
      final api = _answering(_envelope(1, message: 'Updated Successfully'));

      await api.verifyCase(verifying);

      expect(_sent.single.method, 'POST');
      expect(_sent.single.url.path, '/api/verify');
      // The whole contract, and nothing of the case. Both flags go every
      // time: "I am not approving" is a statement, not a missing field.
      expect(_lastJson(), {
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': 'Maker',
        'comments': 'Lien released, checked in core.',
        // The word, not a JSON boolean — the service spells this one out.
        'isVerified': 'yes',
        // Null, not a no: the health check side has no such decision to make,
        // and inventing one would say it did.
        'status': null,
      });
    });

    test('a reviewer with nothing to add still verifies', () async {
      final api = _answering(_envelope(1, message: 'Updated Successfully'));

      await api.verifyCase(
        const VerifyRequest(
          clientId: '2287410',
          userId: 'OFF807292',
          role: 'Maker',
          isVerified: true,
        ),
      );

      expect(_lastJson()['comments'], '');
      expect(_lastJson()['isVerified'], 'yes');
      expect(_lastJson()['status'], isNull);
    });

    test('the CPU side passes a record on with its own decision', () async {
      final api = _answering(_envelope(1, message: 'Updated Successfully'));

      await api.verifyCase(
        const VerifyRequest(
          clientId: '1130488',
          userId: 'r14878',
          role: 'Checker',
          comments: 'Documents in order.',
          status: ApprovalStatus.approved,
        ),
      );

      // The other half of the handover: the checker approves, the maker
      // verifies, and each side's field is null from the other — a decision
      // nobody made is not a no.
      expect(_lastJson()['status'], 'Approved');
      expect(_lastJson()['isVerified'], isNull);
    });

    test('a rejection goes out as the word too', () async {
      final api = _answering(_envelope(0, message: 'Updated Successfully'));

      await api.verifyCase(
        const VerifyRequest(
          clientId: '1130488',
          userId: 'r14878',
          role: 'Checker',
          comments: 'Missing the statement.',
          status: ApprovalStatus.reject,
        ),
      );

      expect(_lastJson()['status'], 'Reject');
    });

    test('a note that decides nothing says so on the wire', () async {
      final api = _answering(_envelope(0, message: 'Updated Successfully'));

      await api.verifyCase(
        const VerifyRequest(
          clientId: '2287410',
          userId: 'OFF807292',
          role: 'Maker',
          comments: 'Waiting on the branch.',
          isVerified: false,
        ),
      );

      // The record keeps its status; only the note is written. Anything the
      // other end does not read as an affirmative decides nothing.
      expect(_lastJson()['isVerified'], 'no');
      expect(_lastJson()['status'], isNull);
    });

    test('the count comes back off a plain integer', () async {
      final api = _answering(_envelope(1, message: 'Updated Successfully'));

      final response = await api.verifyCase(verifying);

      expect(response.updatedCount, 1);
      expect(response.total, 1);
    });

    test(
      'a verify the server does not count still counts the one row',
      () async {
        final api = _answering(
          _envelope(null, message: 'Updated Successfully'),
        );

        final response = await api.verifyCase(verifying);

        // The row was written; reporting zero would tell the reviewer their
        // verification was dropped.
        expect(response.total, 1);
      },
    );

    test('a refused verify is raised so the panel keeps the record', () async {
      final api = _answering({'message': 'Not allowed.'}, status: 403);

      await expectLater(
        api.verifyCase(verifying),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Not allowed.',
          ),
        ),
      );
    });

    test('a note carrying a file goes up as multipart', () async {
      final bodies = <String>[];
      final api = _api(
        (_) => http.Response(
          jsonEncode(_envelope(1, message: 'Updated Successfully')),
          200,
          headers: {'content-type': 'application/json'},
        ),
        rawBodies: bodies,
      );

      await api.verifyCase(
        VerifyRequest(
          clientId: '1130488',
          userId: 'r14878',
          role: 'Checker',
          comments: 'Documents in order.',
          status: ApprovalStatus.approved,
          supportDocument: CommentAttachment(
            filename: 'lien.xlsx',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );

      expect(_sent.single.url.path, '/api/verify');
      expect(
        _sent.single.headers['content-type'],
        contains('multipart/form-data'),
      );
      // The file under the key the service reads it by, and every text value
      // alongside it — the flags included, since a multipart body it can parse
      // is the only one it will get.
      expect(bodies.single, contains('name="supportDocument"'));
      expect(bodies.single, contains('filename="lien.xlsx"'));
      expect(bodies.single, contains('name="status"'));
      expect(bodies.single, contains('Approved'));
      // The other side's field is present and null, not dropped: the body
      // keeps one shape whether or not a file rode along, so the two can be
      // read against each other. A form value is text, so the null is spelled
      // out — and the server takes it, a missing flag and a `no` the same way.
      expect(bodies.single, contains('name="isVerified"'));
      expect(
        bodies.single,
        contains('name="isVerified"\r\n\r\nnull\r\n'),
      );
      expect(bodies.single, contains('name="comments"'));
    });

    test('the multipart body carries every key the JSON one does', () async {
      const checker = VerifyRequest(
        clientId: '1130488',
        userId: 'r14878',
        role: 'Checker',
        comments: 'Documents in order.',
        status: ApprovalStatus.approved,
      );

      // Same request, one shape. A checker never sets `isVerified`, and the
      // key still goes — dropping it on the multipart path would make the two
      // bodies disagree about what the contract is.
      expect(checker.toFields().keys, checker.toJson().keys);
      // The same null on both paths, said the only way each can say it: JSON
      // has the value, a form field has only text to spell it with.
      expect(checker.toFields()['isVerified'], 'null');
      expect(checker.toJson()['isVerified'], isNull);

      // And the mirror of it, so neither side of the handover is left to
      // assumption: a maker states `isVerified` and has no `status` to give.
      const maker = VerifyRequest(
        clientId: '1130488',
        userId: 'OFF807292',
        role: 'Maker',
        comments: 'Checked in core.',
        isVerified: true,
      );
      expect(maker.toFields()['status'], 'null');
      expect(maker.toFields()['isVerified'], 'yes');
      expect(maker.toJson()['status'], isNull);
    });

    test('a note with no file stays a plain JSON post', () async {
      final api = _answering(_envelope(1, message: 'Updated Successfully'));

      await api.verifyCase(verifying);

      expect(
        _sent.single.headers['content-type'],
        contains('application/json'),
      );
    });

    test('a failure the envelope reports on a 200 is still raised', () async {
      final api = _answering(
        _envelope(
          null,
          code: 1,
          success: false,
          message: 'clientId and userId are required.',
        ),
      );

      await expectLater(
        api.verifyCase(verifying),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'clientId and userId are required.',
          ),
        ),
      );
    });
  });

  group('${ApiEndpoints.getComments} / ${ApiEndpoints.addComment}', () {
    const thread = GetCommentsRequest(clientId: '1130488', userId: 'r14878');

    Map<String, dynamic> comment({
      String role = 'Checker',
      String text = 'Checked in core',
    }) => {
      'clientId': '1130488',
      'userId': 'r14878',
      'role': role,
      'comments': text,
      'createdAt': '2026-08-11T12:13:00.000Z',
    };

    test('the thread is read by case and by caller', () async {
      final api = _answering(
        _envelope({
          'comments': [comment(), comment(role: 'Maker', text: 'Ack')],
        }),
      );

      final response = await api.fetchComments(thread);

      expect(_sent.single.method, 'GET');
      expect(_sent.single.url.queryParameters, {
        'clientId': '1130488',
        'userId': 'r14878',
      });
      expect(
        [for (final c in response.comments) c.comments],
        ['Checked in core', 'Ack'],
      );
      // The template is what the thread shows as the author — a note from the
      // CPU side reads differently from one from the health check.
      expect(response.comments.first.author, 'Checker');
      expect(
        response.comments.first.createdAt,
        DateTime.parse('2026-08-11T12:13:00.000Z').toLocal(),
      );
    });

    test('a case nobody has commented on is a result, not an error', () async {
      final api = _answering(_envelope({'comments': <dynamic>[]}));

      final response = await api.fetchComments(thread);

      expect(response.isSuccess, isTrue);
      expect(response.comments, isEmpty);
    });

    test('a comment carrying no template falls back to its author', () async {
      final api = _answering(
        _envelope({
          'comments': [comment(role: '')],
        }),
      );

      final response = await api.fetchComments(thread);

      // An author line is never blank: the employee code stands in.
      expect(response.comments.single.author, 'r14878');
    });

    test('a failure the envelope reports on a 200 is still raised', () async {
      final api = _answering(
        _envelope(
          null,
          code: 1,
          success: false,
          message: 'clientId and userId are required.',
        ),
      );

      await expectLater(
        api.fetchComments(thread),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'clientId and userId are required.',
          ),
        ),
      );
    });

    test('a note carrying a file goes up as multipart', () async {
      final bodies = <String>[];
      final api = _api(
        (_) => http.Response(
          jsonEncode(
            _envelope({
              'comment': {
                'id': 1,
                'clientId': '1130488',
                'userId': 'r14878',
                'role': 'Checker',
                'comments': 'asd',
                'supportDocument': 'lien.xlsx',
                'createdAt': '2026-08-11T12:31:50.576409Z',
              },
            }, message: 'Comment Added'),
          ),
          200,
          headers: {'content-type': 'application/json'},
        ),
        rawBodies: bodies,
      );

      final response = await api.addComment(
        AddCommentRequest(
          clientId: '1130488',
          userId: 'r14878',
          comments: 'asd',
          role: 'Checker',
          supportDocument: CommentAttachment(
            filename: 'lien.xlsx',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );

      expect(_sent.single.method, 'POST');
      expect(_sent.single.url.path, '/api/addComment');
      expect(
        _sent.single.headers['content-type'],
        contains('multipart/form-data'),
      );
      // The file under the key the service reads it by, and the four text
      // values alongside it rather than in a JSON body it will never parse.
      expect(bodies.single, contains('name="supportDocument"'));
      expect(bodies.single, contains('filename="lien.xlsx"'));
      expect(bodies.single, contains('name="clientId"'));
      expect(bodies.single, contains('name="comments"'));
      expect(bodies.single, contains('name="role"'));
      expect(response.comment?.supportDocument, 'lien.xlsx');
    });

    test('a note with no file stays a plain JSON post', () async {
      final api = _answering(
        _envelope({
          'comment': {
            'id': 2,
            'clientId': '1130488',
            'userId': 'r14878',
            'comments': 'no file',
            'createdAt': '2026-08-11T12:31:50.576409Z',
          },
        }, message: 'Comment Added'),
      );

      await api.addComment(
        const AddCommentRequest(
          clientId: '1130488',
          userId: 'r14878',
          comments: 'no file',
          role: 'Checker',
        ),
      );

      // Unchanged for the common case: a comment on its own is still JSON.
      expect(
        _sent.single.headers['content-type'],
        contains('application/json'),
      );
      expect(_lastJson()['comments'], 'no file');
      expect(_lastJson().containsKey('supportDocument'), isFalse);
    });

    test('a posted comment goes out as the four fields', () async {
      final api = _answering(_envelope({'comment': comment()}));

      final response = await api.addComment(
        const AddCommentRequest(
          clientId: '1130488',
          userId: 'r14878',
          comments: 'Checked in core',
          role: 'Checker',
        ),
      );

      expect(_sent.single.method, 'POST');
      expect(_lastJson(), {
        'clientId': '1130488',
        'userId': 'r14878',
        'comments': 'Checked in core',
        'role': 'Checker',
      });
      // What was stored, not what was sent: the stamp is the server's.
      expect(response.comment?.createdAt, isNotNull);
      expect(response.comment?.comments, 'Checked in core');
    });

    test('an acknowledged write that echoes nothing is still a success', () {
      // The thread is re-read after a post, so a server that answers with an
      // empty envelope has still done the job.
      final response = AddCommentResponse.fromBody(_envelope(null));

      expect(response.isSuccess, isTrue);
      expect(response.comment, isNull);
    });

    test('a rejected comment is raised with the server\'s reason', () async {
      final api = _answering({
        'success': false,
        'message': 'A comment cannot be empty.',
      }, status: 400);

      await expectLater(
        api.addComment(
          const AddCommentRequest(
            clientId: '1130488',
            userId: 'r14878',
            comments: '',
            role: 'Checker',
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'A comment cannot be empty.',
          ),
        ),
      );
    });
  });

  group('POST ${ApiEndpoints.reassign}', () {
    const routing = ReassignRequest(
      clientId: '2287410',
      userId: 'OFF807292',
      role: 'Maker',
      cpu: 'Chennai',
      team: 'Disbursement Team',
      reason: 'Incorrect CPU mapping',
      comments: 'Wrong team, sending this back.',
    );

    test('the record, the destination and why go out', () async {
      final api = _answering(
        _envelope(1, message: 'Successfully assigned to new user'),
      );

      final response = await api.reassignCase(routing);

      expect(_sent.single.method, 'POST');
      expect(_sent.single.url.path, '/api/reassign');
      expect(_lastJson(), {
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': 'Maker',
        'cpu': 'Chennai',
        'team': 'Disbursement Team',
        'reason': 'Incorrect CPU mapping',
        'comments': 'Wrong team, sending this back.',
        // Null with no file: the name is all this key carries, and the bytes
        // ride as the multipart file when there are any.
        'document': null,
      });
      // A sentence to show the reviewer, not a count of rows.
      expect(response.message, 'Successfully assigned to new user');
      expect(response.movedCount, 1);
    });

    test('a document goes up as multipart, under its own key', () async {
      final bodies = <String>[];
      final api = _api(
        (_) => http.Response(
          jsonEncode(
            _envelope(1, message: 'Successfully assigned to new user'),
          ),
          200,
          headers: {'content-type': 'application/json'},
        ),
        rawBodies: bodies,
      );

      await api.reassignCase(
        ReassignRequest(
          clientId: '2287410',
          userId: 'OFF807292',
          role: 'Maker',
          cpu: 'Chennai',
          team: 'Disbursement Team',
          document: CommentAttachment(
            filename: 'handover.pdf',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );

      expect(
        _sent.single.headers['content-type'],
        contains('multipart/form-data'),
      );
      expect(bodies.single, contains('name="document"'));
      expect(bodies.single, contains('filename="handover.pdf"'));
      expect(bodies.single, contains('name="cpu"'));
      expect(bodies.single, contains('name="team"'));
    });

    test(
      'a service that sends no message still has something to say',
      () async {
        final api = _answering(_envelope(1, message: ''));

        final response = await api.reassignCase(routing);

        // The toast is what the reviewer sees; an empty one reads as nothing
        // having happened.
        expect(response.toastText, 'Successfully assigned to new user');
      },
    );

    test('a refused reassignment is raised, not reported as done', () async {
      final api = _answering({
        'success': false,
        'message': 'A reassignment needs both a CPU and a team.',
      }, status: 400);

      await expectLater(
        api.reassignCase(routing),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'A reassignment needs both a CPU and a team.',
          ),
        ),
      );
    });

    test('a failure the envelope reports on a 200 is still raised', () async {
      final api = _answering(
        _envelope(
          null,
          code: 1,
          success: false,
          message: 'Only the health check side can reassign a record.',
        ),
      );

      await expectLater(
        api.reassignCase(routing),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('Api.fileExtension', () {
    // What goes out as the `fileType` form field, so the server does not have
    // to trust a browser's filename.
    test('is the extension, lowercased', () {
      expect(Api.fileExtension('HealthCheck.XLSX'), 'xlsx');
    });

    test('reads the last dot, not the first', () {
      expect(Api.fileExtension('quarter.2.report.csv'), 'csv');
    });

    test('is empty when the name carries no extension', () {
      expect(Api.fileExtension('cases'), '');
    });

    test('is empty when the name ends on the dot', () {
      expect(Api.fileExtension('cases.'), '');
    });

    test('is empty for an empty name', () {
      expect(Api.fileExtension(''), '');
    });
  });
}
