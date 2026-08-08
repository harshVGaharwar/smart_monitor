import 'dart:convert';
import 'dart:io';

import 'package:backend/src/cases_repository.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../routes/api/update-smartpointer.dart' as route;

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
            Uri.parse('http://localhost/api/update-smartpointer'),
            body: body is String ? body : jsonEncode(body),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          )
        : Request.get(Uri.parse('http://localhost/api/update-smartpointer')),
  );
  return route.onRequest(context);
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.body()) as Map<String, dynamic>;

void main() {
  setUp(() => _repo = CasesRepository(':memory:'));
  tearDown(() => _repo.close());

  group('POST /api/update-smartpointer', () {
    test('writes the rows and reports how many landed', () async {
      final response = await _post({
        'rows': [_row(lineNo: '1'), _row(lineNo: '2')],
      });

      expect(response.statusCode, HttpStatus.ok);

      final body = await _json(response);
      expect(body['message'], 'Updated Successfully');
      expect(body['success'], isTrue);

      final data = body['data'] as Map<String, dynamic>;
      expect(data['total'], 2);
      expect(data['inserted'], 2);
      expect(data['updated'], 0);
      expect(body['count'], 2);
      // The submit is only real if it survives the request.
      expect(_repo.count(), 2);
    });

    test('echoes the rows it stored, in the model the request used', () async {
      final response = await _post({
        'rows': [_row(lineNo: '1')],
      });

      final data = (await _json(response))['data'] as Map<String, dynamic>;
      final rows = (data['rows'] as List).cast<Map<String, dynamic>>();
      expect(rows, hasLength(1));
      expect(
        rows.single.keys,
        containsAllInOrder([
          'client_id',
          'customer_name',
          'account_no',
          'line_no',
          'health_check_category',
          'sub_category',
          'support_system',
          'core_system',
          'exception_category',
          'reason',
          'cpu',
          'team',
          'segment',
          'facility',
          'sr_no',
          'maker',
          'checker',
          'ls_srm_date',
          'status',
        ]),
      );
      expect(rows.single['client_id'], '4943581');
      expect(rows.single['cpu'], 'Mumbai');
      expect(rows.single['team'], 'Cam Renewal Team');
      // The fixture spells it the old way; the row comes back under the name
      // the wire actually uses.
      expect(rows.single['sr_no'], '1');
      // Stated by nobody, filled in by the store — which is the point of
      // echoing what was written rather than what was posted.
      expect(rows.single['status'], 'Pending with CPU');
    });

    test('a stated status is stored, and a null one leaves it alone', () async {
      await _post({
        'rows': [
          {..._row(), 'status': 'Verified'},
        ],
      });

      final response = await _post({
        'rows': [
          {..._row(cpu: 'Kolkata'), 'status': null},
        ],
      });

      final data = (await _json(response))['data'] as Map<String, dynamic>;
      final row = (data['rows'] as List).cast<Map<String, dynamic>>().single;
      expect(row['status'], 'Verified');
      expect(row['cpu'], 'Kolkata');
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
      // One row written, and still one case stored rather than two.
      final data = body['data'] as Map<String, dynamic>;
      expect(data['total'], 1);
      expect(data['updated'], 1);
      expect(data['inserted'], 0);
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
