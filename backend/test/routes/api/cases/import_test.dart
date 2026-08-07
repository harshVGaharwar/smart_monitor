import 'dart:convert';
import 'dart:io';

import 'package:backend/src/cases_repository.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../../routes/api/cases/import.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

late CasesRepository _repo;

Map<String, dynamic> _row({String lineNo = '5', String cpu = 'Mumbai'}) => {
  'client_id': '4943581',
  'customer_name': 'ACME',
  'account_no': '50200031339584',
  'line_no': lineNo,
  'health_check_category': 'CAM Expiry Health Check',
  'sub_category': 'Sub',
  'support_system': 'LMM',
  'core_system': 'FC',
  'segment': 'Retail',
  'facility_sr_no': '1',
  'maker': 'mk',
  'checker': 'ck',
  'ls_srm_date': '2026-07-21',
  'exception_category': 'Exception',
  'reason': 'Renewal pending',
  'cpu': cpu,
  'team': 'Cam Renewal Team',
};

Future<Response> _post(Object body, {HttpMethod method = HttpMethod.post}) {
  final context = _MockRequestContext();
  when(() => context.read<CasesRepository>()).thenReturn(_repo);
  when(() => context.request).thenReturn(
    method == HttpMethod.post
        ? Request.post(
            Uri.parse('http://localhost/api/cases/import'),
            body: body is String ? body : jsonEncode(body),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          )
        : Request.get(Uri.parse('http://localhost/api/cases/import')),
  );
  return route.onRequest(context);
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.body()) as Map<String, dynamic>;

void main() {
  setUp(() => _repo = CasesRepository(':memory:'));
  tearDown(() => _repo.close());

  group('POST /api/cases/import', () {
    test('writes the rows and reports what it did', () async {
      final response = await _post({
        'rows': [_row(lineNo: '1'), _row(lineNo: '2')],
      });

      expect(response.statusCode, HttpStatus.ok);

      final body = await _json(response);
      expect(body['inserted'], 2);
      expect(body['updated'], 0);
      expect(body['total'], 2);
      // The submit is only real if it survives the request.
      expect(_repo.count(), 2);
    });

    test('a bare array is accepted as well as the rows envelope', () async {
      final response = await _post([_row()]);

      expect(response.statusCode, HttpStatus.ok);
      expect(_repo.count(), 1);
    });

    test('re-submitting a corrected row updates rather than duplicates',
        () async {
      await _post({
        'rows': [_row()],
      });
      final response = await _post({
        'rows': [_row(cpu: 'Kolkata')],
      });

      final body = await _json(response);
      expect(body['updated'], 1);
      expect(body['inserted'], 0);
      expect(_repo.count(), 1);
    });

    test('refuses rows with no identity rather than colliding them', () async {
      final response = await _post({
        'rows': [
          _row(),
          {..._row(lineNo: '9'), 'client_id': ''},
        ],
      });

      expect(response.statusCode, HttpStatus.unprocessableEntity);
      final body = await _json(response);
      expect(body['message'], contains('cannot be saved'));
      // Nothing is written when the submit is refused.
      expect(_repo.count(), 0);
    });

    test('rejects an empty rows array', () async {
      final response = await _post({'rows': <dynamic>[]});

      expect(response.statusCode, HttpStatus.badRequest);
      expect(_repo.count(), 0);
    });

    test('rejects a body with no rows at all', () async {
      final response = await _post({'nope': true});

      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('rejects a body that is not JSON', () async {
      final response = await _post('not json at all');

      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('refuses anything but POST', () async {
      final response = await _post(<String, dynamic>{}, method: HttpMethod.get);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
