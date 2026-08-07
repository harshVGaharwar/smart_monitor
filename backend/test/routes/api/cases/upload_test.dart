import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../../routes/api/cases/upload.dart' as route;

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
      Uri.parse('http://localhost/api/cases/upload'),
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
  group('POST /api/cases/upload', () {
    test('returns the parsed rows for a readable file', () async {
      final response = await _post(_multipart(_csv, filename: 'cases.csv'));

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      final rows = body['rows'] as List;
      expect(body['count'], 1);
      expect(rows, hasLength(1));

      final row = rows.single as Map<String, dynamic>;
      expect(row['client_id'], '4943581');
      expect(row['cpu'], 'Mumbai');
      // The client keys off these exact names when mapping the response.
      expect(row['team'], 'Cam Renewal Team');
      expect(row['health_check_category'], 'CAM Expiry Health Check');
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
      final response = await _post(
        _multipart(_csv, filename: 'cases.pdf', fileType: 'pdf'),
      );

      expect(response.statusCode, HttpStatus.unprocessableEntity);
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['message'], contains('Unsupported file type: .pdf'));
    });

    test('rejects a file the user has to fix with 422 and a reason', () async {
      final response = await _post(
        _multipart('Client id,Customer name\n1,ACME', filename: 'cases.csv'),
      );

      expect(response.statusCode, HttpStatus.unprocessableEntity);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      // This message is shown verbatim on the upload card.
      expect(body['message'], contains('missing required column'));
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
          Uri.parse('http://localhost/api/cases/upload'),
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
        Request.get(Uri.parse('http://localhost/api/cases/upload')),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
