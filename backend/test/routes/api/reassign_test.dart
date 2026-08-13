import 'dart:convert';
import 'dart:io';

import 'package:backend/src/cases_repository.dart';
import 'package:backend/src/comments_repository.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../routes/api/reassign.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

late CasesRepository _cases;
late CommentsRepository _comments;

Map<String, dynamic> _row({String lineNo = '5'}) => {
  'client_id': '2287410',
  'customer_name': 'NORTHGATE LOGISTICS LIMITED',
  'account_no': '11930442',
  'line_no': lineNo,
  'maker': 'OFF807292',
  'checker': 'r14878',
  'cpu': 'Mumbai',
  'team': 'Cam Renewal Team',
  'status': 'Pending with Health Checker',
};

/// A reassignment as the panel sends it.
Map<String, dynamic> _body({
  String? clientId = '2287410',
  String? userId = 'OFF807292',
  String role = 'Maker',
  String? cpu = 'Chennai',
  String? team = 'Disbursement Team',
  String reason = '',
  String comments = '',
}) => {
  if (clientId != null) 'clientId': clientId,
  if (userId != null) 'userId': userId,
  'role': role,
  if (cpu != null) 'cpu': cpu,
  if (team != null) 'team': team,
  'reason': reason,
  'comments': comments,
};

Future<Response> _post(
  Object? body, {
  HttpMethod method = HttpMethod.post,
}) {
  final context = _MockRequestContext();
  final uri = Uri.parse('http://localhost/api/reassign');
  when(() => context.read<CasesRepository>()).thenReturn(_cases);
  when(() => context.read<CommentsRepository>()).thenReturn(_comments);
  when(() => context.request).thenReturn(
    method == HttpMethod.post
        ? Request.post(uri, body: body is String ? body : jsonEncode(body))
        : Request.get(uri),
  );
  return route.onRequest(context);
}

/// The same call as multipart, the way one carrying a file arrives.
Future<Response> _postForm(
  Map<String, String> fields, {
  String? filename,
}) {
  const boundary = 'X-SMART-BOUNDARY';
  final body = StringBuffer();
  for (final entry in fields.entries) {
    body
      ..write('--$boundary\r\n')
      ..write('Content-Disposition: form-data; name="${entry.key}"\r\n\r\n')
      ..write('${entry.value}\r\n');
  }
  if (filename != null) {
    body
      ..write('--$boundary\r\n')
      ..write(
        'Content-Disposition: form-data; name="document"; '
        'filename="$filename"\r\n',
      )
      ..write('Content-Type: application/octet-stream\r\n\r\n')
      ..write('not really a document\r\n');
  }
  body.write('--$boundary--\r\n');

  final context = _MockRequestContext();
  when(() => context.read<CasesRepository>()).thenReturn(_cases);
  when(() => context.read<CommentsRepository>()).thenReturn(_comments);
  when(() => context.request).thenReturn(
    Request.post(
      Uri.parse('http://localhost/api/reassign'),
      body: body.toString(),
      headers: {'content-type': 'multipart/form-data; boundary=$boundary'},
    ),
  );
  return route.onRequest(context);
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.body()) as Map<String, dynamic>;

Map<String, dynamic> _stored() =>
    _cases.allCases().firstWhere((row) => row['client_id'] == '2287410');

void main() {
  setUp(() {
    _cases = CasesRepository(':memory:');
    _comments = CommentsRepository(':memory:');
  });
  tearDown(() {
    _cases.close();
    _comments.close();
  });

  group('POST /api/reassign', () {
    test('the record changes hands and goes back to the CPU side', () async {
      _cases.importRows([_row()]);

      final response = await _post(
        _body(
          reason: 'Incorrect CPU mapping',
          comments: 'Wrong team, sending this back.',
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await _json(response);
      expect(body['success'], isTrue);
      expect(body['message'], 'Successfully assigned to new user');
      expect(body['data'], 1);

      // All three together: a case that changed hands but kept its status
      // would sit in the wrong queue under the right team.
      final stored = _stored();
      expect(stored['cpu'], 'Chennai');
      expect(stored['team'], 'Disbursement Team');
      expect(stored['status'], 'Pending with CPU');
    });

    test('the record remembers who handed it over, and when', () async {
      // The CPU side opening the case should see who sent it without reading
      // down the thread for a name. The stamp is the server's, as every other
      // stamp on a handover is.
      _cases.importRows([_row()]);

      await _post({
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': 'Maker',
        'cpu': 'Chennai',
        'team': 'Disbursement Team',
      });

      final stored = _cases.allCases().single;
      expect(stored['assigned_by'], 'OFF807292');
      expect(
        DateTime.parse(stored['assigned_date']! as String).isUtc,
        isTrue,
      );
    });

    test('a re-import does not erase the handover', () async {
      // An upload file carries neither column, and a blank cell must not wipe
      // what the server wrote — the rule the status has always had.
      _cases.importRows([_row()]);
      await _post({
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': 'Maker',
        'cpu': 'Chennai',
        'team': 'Disbursement Team',
      });

      _cases.importRows([_row()]);

      expect(_cases.allCases().single['assigned_by'], 'OFF807292');
    });

    test('the note and the reason land on the thread, apart', () async {
      _cases.importRows([_row()]);

      await _post(
        _body(
          reason: 'Incorrect CPU mapping',
          comments: 'Wrong team, sending this back.',
        ),
      );

      final note = _comments.forClient('2287410').single;
      // Kept apart rather than welded together: one is a chosen value, the
      // other is prose, and the CPU side reads them differently.
      expect(note['comments'], 'Wrong team, sending this back.');
      expect(note['reason'], 'Incorrect CPU mapping');
      expect(note['user_id'], 'OFF807292');
      expect(note['role'], 'Maker');
    });

    test('a reassignment with nothing to say leaves no note', () async {
      _cases.importRows([_row()]);

      final response = await _post(_body());

      // Honest: nothing was said, so the thread has nothing to show.
      expect((await _json(response))['data'], 1);
      expect(_stored()['cpu'], 'Chennai');
      expect(_comments.count(), 0);
    });

    test('a document arrives as multipart, under its own key', () async {
      _cases.importRows([_row()]);

      final response = await _postForm(
        {
          'clientId': '2287410',
          'userId': 'OFF807292',
          'role': 'Maker',
          'cpu': 'Chennai',
          'team': 'Disbursement Team',
          'reason': 'Incorrect CPU mapping',
          'comments': 'Handover attached.',
        },
        filename: 'handover.pdf',
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(_stored()['cpu'], 'Chennai');
      expect(
        _comments.forClient('2287410').single['support_document'],
        'handover.pdf',
      );
    });

    test('a reassignment needs somewhere to go', () async {
      _cases.importRows([_row()]);

      for (final body in [_body(cpu: null), _body(team: null)]) {
        final response = await _post(body);

        expect(response.statusCode, HttpStatus.badRequest);
        expect(
          (await _json(response))['message'],
          contains('both a CPU and a team'),
        );
      }
      expect(_stored()['status'], 'Pending with Health Checker');
    });

    test('the record and the reviewer are both required', () async {
      _cases.importRows([_row()]);

      for (final body in [_body(clientId: null), _body(userId: null)]) {
        expect((await _post(body)).statusCode, HttpStatus.badRequest);
      }
      expect(_stored()['cpu'], 'Mumbai');
    });

    test('only the health check side may reassign', () async {
      _cases.importRows([_row()]);

      for (final role in ['Checker', 'Regional Supervisor', '']) {
        final response = await _post(
          _body(role: role, comments: 'Routing this myself'),
        );

        expect(response.statusCode, HttpStatus.forbidden, reason: role);
      }
      // Nothing moved, and nothing said on the way past.
      expect(_stored()['cpu'], 'Mumbai');
      expect(_comments.count(), 0);
    });

    test('a record is only routed out of the queue it is in', () async {
      _cases.importRows([
        {..._row(), 'status': 'Verified'},
      ]);

      final response = await _post(_body());

      expect((await _json(response))['data'], 0);
      expect(_stored()['status'], 'Verified');
      expect(_stored()['cpu'], 'Mumbai');
    });

    test('a body that is not JSON is refused, not acted on', () async {
      _cases.importRows([_row()]);

      expect(
        (await _post('<html>gateway</html>')).statusCode,
        HttpStatus.badRequest,
      );
      expect(_stored()['cpu'], 'Mumbai');
    });

    test('refuses anything but POST', () async {
      final response = await _post(null, method: HttpMethod.get);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
