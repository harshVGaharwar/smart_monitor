import 'dart:convert';
import 'dart:io';

import 'package:backend/src/dummy_excel_rows.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../routes/api/read-excel.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

const _boundary = 'test-boundary';

/// A multipart body carrying [content] as the named part, shaped the way
/// `package:http`'s MultipartRequest sends it from the Flutter client.
///
/// [fileType] adds the companion field the client sends beside the file.
String _multipart(
  String content, {
  String field = 'file',
  String? filename,
  String? fileType,
}) {
  final disposition = filename == null
      ? 'form-data; name="$field"'
      : 'form-data; name="$field"; filename="$filename"';
  final buffer = StringBuffer();
  if (fileType != null) {
    buffer
      ..write('--$_boundary\r\n')
      ..write('content-disposition: form-data; name="fileType"\r\n')
      ..write('\r\n')
      ..write('$fileType\r\n');
  }
  buffer
    ..write('--$_boundary\r\n')
    ..write('content-disposition: $disposition\r\n')
    ..write('\r\n')
    ..write('$content\r\n')
    ..write('--$_boundary--\r\n');
  return buffer.toString();
}

Future<Response> _post(String body) {
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(
    Request.post(
      Uri.parse('http://localhost/api/read-excel'),
      body: body,
      headers: {
        HttpHeaders.contentTypeHeader:
            'multipart/form-data; boundary=$_boundary',
      },
    ),
  );
  return route.onRequest(context);
}

final _csv = [
  [
    'Client id', 'Customer name', 'Account no', 'Line no',
    'Health Check Category', 'Sub category', 'Support system', 'Core system',
    'Exception category', 'Reason', 'CPU', 'Actionable Team', 'Maker',
    'Checker', //
  ].join(','),
  [
    '4943581', 'ACME', '50200031339584', '5', 'CAM Expiry Health Check', 'Sub',
    'LMM', 'FC', 'Exception', 'Renewal pending', 'Mumbai', 'Cam Renewal Team',
    'mk', 'ck', //
  ].join(','),
].join('\n');

void main() {
  group('POST /api/read-excel', () {
    // Every test below states which it is exercising, so neither path depends
    // on what the environment happened to be when the suite started.
    tearDown(() => route.readExcelFallback = true);

    test('returns the parsed rows for a readable file', () async {
      final response = await _post(_multipart(_csv, filename: 'cases.csv'));

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['code'], 0);
      expect(body['success'], isTrue);
      expect(body['message'], 'Upload Successful');

      final data = body['data'] as Map<String, dynamic>;
      final rows = data['rows'] as List;
      expect(rows, hasLength(1));

      final row = rows.single as Map<String, dynamic>;
      expect(row['client_id'], '4943581');
      expect(row['cpu'], 'Mumbai');
      // The client keys off these exact names when mapping the response.
      expect(row['team'], 'Cam Renewal Team');
      expect(row['health_check_category'], 'CAM Expiry Health Check');
    });

    test('answers in the envelope the live service uses', () async {
      final response = await _post(_multipart(_csv, filename: 'cases.csv'));

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      // Every field UAT sends, present even where this server has nothing to
      // put in it — a client written against UAT expects the keys to exist.
      expect(
        body.keys,
        containsAllInOrder([
          'code', 'message', 'body', 'success', 'data', 'count', 'userName',
          'userCode', 'branchName', 'branchCode', 'menu', //
        ]),
      );
      expect(body['body'], isNull);
      expect(body['userName'], isNull);
      expect(body['menu'], isNull);
    });

    test('shapes the row the way the live service writes it', () async {
      final response = await _post(_multipart(_csv, filename: 'cases.csv'));

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>;
      final row = (data['rows'] as List).single as Map<String, dynamic>;

      // A column the file left out is null, not "".
      expect(row['segment'], isNull);
      expect(row['facility'], isNull);
      // A number rather than text, and 0 where the file did not number it.
      expect(row['sr_no'], 0);
      // What .NET writes for a date that was never set.
      expect(row['ls_srm_date'], '0001-01-01');
      // Only a stored case carries these; a parsed upload does not.
      expect(row.containsKey('status'), isFalse);
      expect(row.containsKey('imported_at'), isFalse);
    });

    test('reports a rejected file in the envelope as well as the status',
        () async {
      route.readExcelFallback = false;
      final response = await _post(
        _multipart('Client id,Customer name\n1,ACME', filename: 'cases.csv'),
      );

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      // A client that only reads `success` has to see the failure too.
      expect(body['success'], isFalse);
      expect(body['code'], isNot(0));
      expect(body['data'], isNull);
    });

    test('takes the type from the fileType field', () async {
      // The filename says .pdf; the declared type is what should be believed.
      final response = await _post(
        _multipart(_csv, filename: 'cases.pdf', fileType: 'csv'),
      );

      expect(response.statusCode, HttpStatus.ok);
    });

    test('accepts a fileType written with a leading dot', () async {
      final response = await _post(
        _multipart(_csv, filename: 'cases.csv', fileType: '.CSV'),
      );

      expect(response.statusCode, HttpStatus.ok);
    });

    test('falls back to the filename when fileType is absent', () async {
      final response = await _post(_multipart(_csv, filename: 'cases.csv'));

      expect(response.statusCode, HttpStatus.ok);
    });

    test('rejects a type it cannot read', () async {
      route.readExcelFallback = false;
      final response = await _post(
        _multipart(_csv, filename: 'cases.pdf', fileType: 'pdf'),
      );

      expect(response.statusCode, HttpStatus.unprocessableEntity);
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['message'], contains('Unsupported file type: .pdf'));
    });

    test('rejects a file the user has to fix with 422 and a reason', () async {
      route.readExcelFallback = false;
      final response = await _post(
        _multipart('Client id,Customer name\n1,ACME', filename: 'cases.csv'),
      );

      expect(response.statusCode, HttpStatus.unprocessableEntity);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      // This message is shown verbatim on the upload card.
      expect(body['message'], contains('missing required column'));
    });

    group('sample fallback', () {
      test('answers an unreadable file with the sample rows', () async {
        final response = await _post(
          _multipart('Client id,Customer name\n1,ACME', filename: 'cases.csv'),
        );

        expect(response.statusCode, HttpStatus.ok);

        final body = jsonDecode(await response.body()) as Map<String, dynamic>;
        expect(body['success'], isTrue);
        expect(body['message'], 'Upload Successful');

        final data = body['data'] as Map<String, dynamic>;
        final rows = data['rows'] as List;
        expect(rows, hasLength(dummyExcelRows.length));

        // The row UAT returns verbatim, so the client sees the same payload it
        // would get from the live service.
        final first = rows.first as Map<String, dynamic>;
        expect(first['client_id'], '3332125');
        expect(first['customer_name'], 'LEHRY INSTRUMENTATION AND VALVES '
            'PVT LTD');
        expect(first['cpu'], 'Chennai');
        expect(first['team'], 'Disbursement Team');
        // Shaped like any other read: blanks are null, sr_no a number, an
        // unset date .NET's minimum — and no stored-case fields.
        expect(first['segment'], isNull);
        expect(first['sr_no'], 0);
        expect(first['ls_srm_date'], '0001-01-01');
        expect(first.containsKey('status'), isFalse);
      });

      test('the sample carries rows the master data will flag', () async {
        // Otherwise the validation report is uniformly green and the red,
        // editable cells — the point of that screen — never show.
        final response = await _post(
          _multipart('nothing usable here', filename: 'cases.csv'),
        );

        final body = jsonDecode(await response.body()) as Map<String, dynamic>;
        final rows = ((body['data'] as Map<String, dynamic>)['rows'] as List)
            .cast<Map<String, dynamic>>();

        expect(rows.any((r) => r['cpu'] == 'Hyderabad'), isTrue);
        expect(rows.any((r) => r['exception_category'] == 'Deviation'), isTrue);
      });

      test('a readable file is still parsed rather than replaced', () async {
        final response = await _post(_multipart(_csv, filename: 'cases.csv'));

        final body = jsonDecode(await response.body()) as Map<String, dynamic>;
        final rows = (body['data'] as Map<String, dynamic>)['rows'] as List;
        expect(rows, hasLength(1));
        expect((rows.single as Map<String, dynamic>)['client_id'], '4943581');
      });

      test('a request with no file is refused, fallback or not', () async {
        // The fallback is for a file that could not be read, not for a call
        // that never sent one — that is a broken client, not a bad workbook.
        final response = await _post(_multipart('nope', field: 'notafile'));

        expect(response.statusCode, HttpStatus.badRequest);
      });
    });

    test('rejects a request with no file part', () async {
      final response = await _post(_multipart('nope', field: 'notafile'));

      expect(response.statusCode, HttpStatus.badRequest);
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['message'], contains('No file was attached'));
    });

    test('rejects a body that is not multipart at all', () async {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/api/read-excel'),
          body: '{"not":"multipart"}',
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        ),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('refuses anything but POST', () async {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(
        Request.get(Uri.parse('http://localhost/api/read-excel')),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
