import 'dart:convert';
import 'dart:io';

import 'package:backend/src/cases_repository.dart';
import 'package:backend/src/dummy_cases.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../routes/api/get-smartpointer.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

late CasesRepository _repo;

Map<String, dynamic> _row({String lineNo = '5', String srNo = '1'}) => {
  'client_id': '4943581',
  'customer_name': 'ACME',
  'account_no': '50200031339584',
  'line_no': lineNo,
  'health_check_category': 'CAM Expiry Health Check',
  'sub_category': 'Sub',
  'support_system': 'LMM',
  'core_system': 'FC',
  'segment': 'Retail',
  'facility': 'Cash Credit',
  'sr_no': srNo,
  'maker': 'mk',
  'checker': 'ck',
  'ls_srm_date': '2026-07-21',
  'exception_category': 'Exception',
  'reason': 'Renewal pending',
  'cpu': 'Mumbai',
  'team': 'Cam Renewal Team',
};

Future<Response> _get({HttpMethod method = HttpMethod.get}) {
  final context = _MockRequestContext();
  final uri = Uri.parse('http://localhost/api/get-smartpointer');
  when(() => context.read<CasesRepository>()).thenReturn(_repo);
  when(() => context.request).thenReturn(
    method == HttpMethod.get ? Request.get(uri) : Request.post(uri),
  );
  return route.onRequest(context);
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.body()) as Map<String, dynamic>;

void main() {
  setUp(() => _repo = CasesRepository(':memory:'));
  tearDown(() => _repo.close());

  group('GET /api/get-smartpointer', () {
    test('returns the stored cases under data.rows', () async {
      _repo.importRows([_row(lineNo: '1'), _row(lineNo: '2')]);

      final response = await _get();
      expect(response.statusCode, HttpStatus.ok);

      final body = await _json(response);
      expect(body['code'], 0);
      expect(body['success'], isTrue);

      final data = body['data'] as Map<String, dynamic>;
      expect(data['rows'], hasLength(2));
    });

    test('answers in the envelope the live service uses', () async {
      final body = await _json(await _get());

      expect(
        body.keys,
        containsAllInOrder([
          'code', 'message', 'body', 'success', 'data', 'count', 'userName',
          'userCode', 'branchName', 'branchCode', 'menu', //
        ]),
      );
    });

    test('rows carry the two fields only a stored case has', () async {
      _repo.importRows([_row()]);

      final body = await _json(await _get());
      final data = body['data'] as Map<String, dynamic>;
      final row = (data['rows'] as List).single as Map<String, dynamic>;

      // Where the dashboard reads a case's state from — an upload response
      // has neither, since nothing has been stored at that point.
      expect(row['status'], 'Pending with CPU');
      expect(row['imported_at'], isNotEmpty);
      // The wire shape, same as read-excel's.
      expect(row['sr_no'], 1);
      expect(row['facility'], 'Cash Credit');
    });

    test('a seeded case comes back exactly as the service writes it', () async {
      // The dashboard is developed against the seed, so the seed has to arrive
      // shaped like the live response rather than merely close to it. Checked
      // against a captured row, key by key and in order — this is the contract
      // the client's CaseItem mapping is written to.
      _repo.seedIfEmpty(dummyCases);

      final body = await _json(await _get());
      final data = body['data'] as Map<String, dynamic>;
      final rows = (data['rows'] as List).cast<Map<String, dynamic>>();
      final row = rows.firstWhere((r) => r['client_id'] == '3332125');

      const captured = <String, Object?>{
        'client_id': '3332125',
        'customer_name': 'LEHRY INSTRUMENTATION AND VALVES PVT LTD',
        'account_no': '11424036',
        'line_no': '50301271033004',
        'health_check_category': 'FD Exceptions',
        'sub_category': 'Excess lien marked in Core',
        'support_system': '787920',
        'core_system': '986920',
        'exception_category': 'Exception',
        'reason': 'Fd Lien Amount Mismatch Between Lmm And Core; To Be '
            'Reviewed And Rectified',
        'cpu': 'Chennai',
        'team': 'Disbursement Team',
        'segment': null,
        'facility': null,
        'sr_no': 0,
        'maker': 'OFF550975',
        'checker': 'r14878',
        'ls_srm_date': '0001-01-01',
      };

      for (final entry in captured.entries) {
        expect(row[entry.key], entry.value, reason: 'row.${entry.key}');
      }
      // Same keys in the same order, and the only extras are the two a stored
      // case earns.
      expect(row.keys.take(captured.length), orderedEquals(captured.keys));
      expect(row.keys.skip(captured.length), ['status', 'imported_at']);
      expect(row['status'], 'Pending with CPU');
    });

    test('a stored date comes back date-only, however it was written',
        () async {
      // The client writes a date back as a full ISO stamp; the service sends
      // yyyy-MM-dd, so the time is cut off here rather than left to the client.
      _repo.importRows([
        {..._row(), 'ls_srm_date': '2026-07-21T00:00:00.000'},
      ]);

      final body = await _json(await _get());
      final data = body['data'] as Map<String, dynamic>;
      final row = (data['rows'] as List).single as Map<String, dynamic>;

      expect(row['ls_srm_date'], '2026-07-21');
    });

    test('an empty store is a successful response with no rows', () async {
      final body = await _json(await _get());

      // Not an error: nobody has imported anything yet, and the dashboard has
      // an empty state for exactly this.
      expect(body['success'], isTrue);
      expect((body['data'] as Map<String, dynamic>)['rows'], isEmpty);
    });

    test('refuses anything but GET', () async {
      final response = await _get(method: HttpMethod.post);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect((await _json(response))['success'], isFalse);
    });
  });
}
