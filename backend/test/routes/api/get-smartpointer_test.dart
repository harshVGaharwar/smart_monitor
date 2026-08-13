import 'dart:convert';
import 'dart:io';

import 'package:backend/src/cases_repository.dart';
import 'package:backend/src/comments_repository.dart';
import 'package:backend/src/dummy_cases.dart';
import 'package:backend/src/smart_rows.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../routes/api/get-smartpointer.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

late CasesRepository _repo;

/// The thread store the route joins against for the message columns.
late CommentsRepository _comments;

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

/// A read of one queue. The defaults are the checker's pair, which is what
/// [_row] stores: no status of its own, so the repository files it under
/// `Pending with CPU`, under the checker `ck`.
Future<Response> _get({
  HttpMethod method = HttpMethod.get,
  String? employeeCode = 'ck',
  String? role = 'Checker',
}) {
  final context = _MockRequestContext();
  final uri = Uri.parse('http://localhost/api/get-smartpointer').replace(
    queryParameters: {
      if (employeeCode != null) 'employeeCode': employeeCode,
      if (role != null) 'role': role,
    },
  );
  when(() => context.read<CasesRepository>()).thenReturn(_repo);
  when(() => context.read<CommentsRepository>()).thenReturn(_comments);
  when(() => context.request).thenReturn(
    method == HttpMethod.get ? Request.get(uri) : Request.post(uri),
  );
  return route.onRequest(context);
}

/// The rows of a successful response.
Future<List<Map<String, dynamic>>> _rows(Response response) async {
  final body = await _json(response);
  final data = body['data'] as Map<String, dynamic>;
  return (data['rows'] as List).cast<Map<String, dynamic>>();
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.body()) as Map<String, dynamic>;

void main() {
  setUp(() {
    _repo = CasesRepository(':memory:');
    _comments = CommentsRepository(':memory:');
  });
  tearDown(() {
    _repo.close();
    _comments.close();
  });

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

      final body = await _json(await _get(employeeCode: 'r14878'));
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
      // Same keys in the same order, and the only extras are the ones the file
      // never carried: the handover the server records, the priority an upload
      // may state, what the thread amounts to, and the two a stored case earns.
      expect(row.keys.take(captured.length), orderedEquals(captured.keys));
      expect(row.keys.skip(captured.length), [
        'assigned_by',
        'assigned_date',
        'priority',
        'message_count',
        'last_message',
        'status',
        'imported_at',
      ]);
      expect(row['status'], 'Pending with CPU');
      // Nobody has routed this record or written on it, so every one of those
      // says so rather than being left off.
      expect(row['assigned_by'], isNull);
      expect(row['assigned_date'], minDate);
      expect(row['priority'], isNull);
      expect(row['message_count'], 0);
      expect(row['last_message'], isNull);
    });

    test('the thread a case has collected rides on its row', () async {
      // The grid draws a message count and the last note without opening a
      // case, so the queue read has to carry both — one join for the whole
      // queue, not a lookup per row.
      _repo.importRows([_row()]);
      _comments
        ..add(
          clientId: '4943581',
          userId: 'mk',
          role: 'Maker',
          comments: 'Raised with the team',
        )
        ..add(
          clientId: '4943581',
          userId: 'ck',
          role: 'Checker',
          comments: 'Documents in order',
        );

      final row = (await _rows(await _get())).single;
      expect(row['message_count'], 2);
      // The last one written, not the first — the thread reads downwards.
      expect(row['last_message'], 'Documents in order');
    });

    test('a case nobody has written on says so, and says it as 0', () async {
      // Absent from the summary is not a missing key: the column would read
      // blank instead of "No Messages".
      _repo.importRows([_row()]);

      final row = (await _rows(await _get())).single;
      expect(row['message_count'], 0);
      expect(row['last_message'], isNull);
    });

    test('another case’s thread is not counted onto this row', () async {
      _repo.importRows([_row()]);
      _comments.add(
        clientId: '9999999',
        userId: 'mk',
        role: 'Maker',
        comments: 'Somebody else’s case',
      );

      expect((await _rows(await _get())).single['message_count'], 0);
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

    test('a maker reads what is waiting on the health check', () async {
      const waiting = 'Pending with Health Checker';
      _repo.importRows([
        {..._row(lineNo: '1'), 'maker': 'mk', 'status': waiting},
        // Same maker, but already handed on — the other half of the queue.
        {..._row(lineNo: '2'), 'maker': 'mk', 'status': 'Pending with CPU'},
        // Waiting on the health check, but somebody else's record.
        {..._row(lineNo: '3'), 'maker': 'other', 'status': waiting},
      ]);

      final rows = await _rows(await _get(employeeCode: 'mk', role: 'Maker'));

      expect(rows, hasLength(1));
      expect(rows.single['line_no'], '1');
    });

    test('a checker reads what is waiting on the CPU', () async {
      _repo.importRows([
        {..._row(lineNo: '1'), 'checker': 'ck'},
        {..._row(lineNo: '2'), 'checker': 'other'},
      ]);

      // The default pair is the checker's: `ck`, whom `_row` files these
      // under, reading the status a stored row starts life in.
      final rows = await _rows(await _get());

      expect(rows, hasLength(1));
      expect(rows.single['line_no'], '1');
    });

    test("the employee code is read against the role's own column", () async {
      // `ck` checks this record and `mk` made it. Reading as a maker with the
      // checker's code must not match: the two columns are different people.
      _repo.importRows([
        {
          ..._row(),
          'maker': 'mk',
          'checker': 'ck2',
          'status': 'Pending with Health Checker',
        },
      ]);

      expect(
        await _rows(await _get(employeeCode: 'ck2', role: 'Maker')),
        isEmpty,
      );
      expect(
        await _rows(await _get(employeeCode: 'mk', role: 'Maker')),
        hasLength(1),
      );
    });

    test('casing decides nothing', () async {
      // The role text and the employee code both come from services this one
      // does not control.
      _repo.importRows([
        {..._row(), 'checker': 'CK2'},
      ]);

      final rows = await _rows(
        await _get(employeeCode: 'ck2', role: 'checker'),
      );

      expect(rows, hasLength(1));
    });

    test('a template this build cannot name is given no rows', () async {
      _repo.importRows([_row()]);

      final response = await _get(role: 'Regional Supervisor');

      // Successful, and empty. Falling through to every stored case would hand
      // an unrecognised spelling somebody else's records.
      expect(response.statusCode, HttpStatus.ok);
      expect((await _json(response))['success'], isTrue);
      expect(await _rows(response), isEmpty);
    });

    test('a queue nobody named is refused, not guessed at', () async {
      _repo.importRows([_row()]);

      for (final response in [
        await _get(role: null),
        await _get(employeeCode: null),
        await _get(role: ''),
        await _get(employeeCode: ' '),
        await _get(employeeCode: null, role: null),
      ]) {
        // An empty grid would read as a quiet day rather than as the caller
        // having forgotten half the request.
        expect(response.statusCode, HttpStatus.badRequest);
        expect((await _json(response))['success'], isFalse);
      }
    });

    test('refuses anything but GET', () async {
      final response = await _get(method: HttpMethod.post);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect((await _json(response))['success'], isFalse);
    });
  });
}
