import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';
import 'package:smart_monitor/models/case_item.dart';
import 'package:smart_monitor/services/case_api.dart';

ApiClient _clientReturning(
  Object? body, {
  int status = 200,
  void Function(http.Request request)? capture,
}) {
  return ApiClient(
    baseUrl: 'https://example.test/api',
    client: MockClient((request) async {
      capture?.call(request);
      return http.Response(
        body == null ? '' : jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

void main() {
  group('ApiClient', () {
    test('GET decodes the body and appends non-null query params', () async {
      late http.Request seen;
      final client = _clientReturning({'ok': true}, capture: (r) => seen = r);

      final body = await client.get(
        '/cases',
        query: {'search': 'fd', 'status': null, 'page': 2},
      );

      expect(body, {'ok': true});
      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/cases');
      expect(seen.url.queryParameters, {'search': 'fd', 'page': '2'});
      // A null filter must be dropped, not sent as the string "null".
      expect(seen.url.queryParameters.containsKey('status'), isFalse);
    });

    test('POST sends JSON with the right content type', () async {
      late http.Request seen;
      final client = _clientReturning(null, capture: (r) => seen = r);

      await client.post('/cases/1/messages', body: {'text': 'hi'});

      expect(seen.method, 'POST');
      expect(jsonDecode(seen.body), {'text': 'hi'});
      expect(seen.headers['Content-Type'], contains('application/json'));
    });

    test('PUT carries the auth token once set', () async {
      late http.Request seen;
      final client = _clientReturning(null, capture: (r) => seen = r);
      client.setAuthToken('abc123');

      await client.put('/cases/1/verify');

      expect(seen.method, 'PUT');
      expect(seen.headers['Authorization'], 'Bearer abc123');
    });

    test('an empty 204 body decodes to null rather than throwing', () async {
      final client = _clientReturning(null, status: 204);
      expect(await client.put('/cases/1/verify'), isNull);
    });

    test('a non-2xx surfaces the server message', () async {
      final client = _clientReturning({
        'message': 'Case already verified',
      }, status: 409);

      await expectLater(
        client.put('/cases/1/verify'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', 'Case already verified'),
        ),
      );
    });

    test('a non-2xx without a message falls back to status text', () async {
      final client = _clientReturning(null, status: 500);

      await expectLater(
        client.get('/cases'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('server ran into a problem'),
          ),
        ),
      );
    });

    test('HTML error pages do not crash the decoder', () async {
      final client = ApiClient(
        baseUrl: 'https://example.test/api',
        client: MockClient((_) async => http.Response('<html>502</html>', 502)),
      );

      await expectLater(
        client.get('/cases'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'code', 502)),
      );
    });

    test('a transport failure becomes a network ApiException', () async {
      final client = ApiClient(
        baseUrl: 'https://example.test/api',
        client: MockClient((_) => throw http.ClientException('no route')),
      );

      await expectLater(
        client.get('/cases'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isNetworkError, 'isNetworkError', isTrue)
              .having((e) => e.message, 'message', contains('no route')),
        ),
      );
    });

    test('uploadBytes posts multipart with the file attached', () async {
      late http.BaseRequest seen;
      late String rawBody;
      final client = ApiClient(
        baseUrl: 'https://example.test/api',
        client: MockClient((request) async {
          seen = request;
          rawBody = request.body;
          return http.Response('{"uploaded":1}', 200);
        }),
      );

      final body = await client.uploadBytes(
        '/cases/upload',
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'cases.xlsx',
        fields: {'notify': 'true'},
      );

      expect(body, {'uploaded': 1});
      expect(seen.method, 'POST');
      expect(seen.headers['content-type'], contains('multipart/form-data'));
      expect(rawBody, contains('filename="cases.xlsx"'));
      expect(rawBody, contains('notify'));
    });
  });

  group('CaseApi', () {
    test('parses a case list, tolerating a data envelope', () async {
      final client = _clientReturning({
        'data': [
          {
            'exception_code': 'EXC-02009',
            'health_check_category': 'FD Exceptions',
            'cpu': 'Mumbai',
            'team': 'CAM Renewal Team',
            'status': 'Pending',
            'updated_at': '2026-05-11T10:00:00Z',
            'updated_note': 'Docs pending',
            'client_id': '4943581',
            'core_system': 'nan',
            'comments': [
              {'author': 'Prashant', 'text': 'hi', 'sent_at': '2026-05-11'},
            ],
            'activity': [
              {'type': 'Reassigned', 'actor': 'Rahul M.', 'at': '2026-05-11'},
            ],
          },
        ],
      });

      final cases = await CaseApi(client).fetchCases(search: 'cam');

      expect(cases, hasLength(1));
      final c = cases.single;
      expect(c.exceptionCode, 'EXC-02009');
      expect(c.healthCheckCategory, 'FD Exceptions');
      expect(c.status, CaseStatus.pending);
      expect(c.updatedAt?.year, 2026);
      expect(c.clientId, '4943581');
      expect(c.comments.single.author, 'Prashant');
      // The grid's Activity cell falls back to the newest audit entry.
      expect(c.lastActivity?.type, ActivityType.reassigned);
    });

    test('missing and placeholder fields become empty, not crashes', () async {
      final client = _clientReturning([
        {
          'exception_code': 'EXC-1',
          'status': 'Verified',
          'customer_name': 'nan',
        },
      ]);

      final c = (await CaseApi(client).fetchCases()).single;

      expect(c.status, CaseStatus.verified);
      // "nan" is what the spreadsheet exports put in blank cells.
      expect(c.customerName, isEmpty);
      expect(c.subCategory, isEmpty);
      expect(c.lastActivity, isNull);
    });

    test(
      'an unknown status falls back to pending instead of dropping',
      () async {
        final client = _clientReturning([
          {'exception_code': 'EXC-1', 'status': 'Something New'},
        ]);

        final c = (await CaseApi(client).fetchCases()).single;
        expect(c.status, CaseStatus.pending);
      },
    );

    test('reassign PUTs the destination', () async {
      late http.Request seen;
      final client = _clientReturning(null, capture: (r) => seen = r);

      await CaseApi(client).reassignCase(7, cpu: 'Mohali', team: 'LMS Team');

      expect(seen.method, 'PUT');
      expect(seen.url.path, '/api/cases/7/reassign');
      expect(jsonDecode(seen.body), {'cpu': 'Mohali', 'team': 'LMS Team'});
    });
  });
}
