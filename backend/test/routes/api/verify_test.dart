import 'dart:convert';
import 'dart:io';

import 'package:backend/src/cases_repository.dart';
import 'package:backend/src/comments_repository.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../routes/api/verify.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

late CasesRepository _cases;
late CommentsRepository _comments;

Map<String, dynamic> _row({
  String lineNo = '5',
  String clientId = '2287410',
  String status = 'Pending with Health Checker',
}) => {
  'client_id': clientId,
  'customer_name': 'NORTHGATE LOGISTICS LIMITED',
  'account_no': '11930442',
  'line_no': lineNo,
  'health_check_category': 'CAM Expiry Health Check',
  'sub_category': 'Sub',
  'maker': 'OFF807292',
  'checker': 'r22104',
  'cpu': 'Mumbai',
  'team': 'Cam Renewal Team',
  'status': status,
};

Future<Response> _post(
  Object? body, {
  HttpMethod method = HttpMethod.post,
}) {
  final context = _MockRequestContext();
  final uri = Uri.parse('http://localhost/api/verify');
  when(() => context.read<CasesRepository>()).thenReturn(_cases);
  when(() => context.read<CommentsRepository>()).thenReturn(_comments);
  when(() => context.request).thenReturn(
    method == HttpMethod.post
        ? Request.post(uri, body: body is String ? body : jsonEncode(body))
        : Request.get(uri),
  );
  return route.onRequest(context);
}

/// The same call as multipart, the way a note carrying a file arrives.
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
        'Content-Disposition: form-data; name="supportDocument"; '
        'filename="$filename"\r\n',
      )
      ..write('Content-Type: application/octet-stream\r\n\r\n')
      ..write('not really a spreadsheet\r\n');
  }
  body.write('--$boundary--\r\n');

  final context = _MockRequestContext();
  when(() => context.read<CasesRepository>()).thenReturn(_cases);
  when(() => context.read<CommentsRepository>()).thenReturn(_comments);
  when(() => context.request).thenReturn(
    Request.post(
      Uri.parse('http://localhost/api/verify'),
      body: body.toString(),
      headers: {
        'content-type': 'multipart/form-data; boundary=$boundary',
      },
    ),
  );
  return route.onRequest(context);
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.body()) as Map<String, dynamic>;

String _statusOf(String clientId) =>
    _cases
            .allCases()
            .firstWhere((row) => row['client_id'] == clientId)['status']
        as String;

void main() {
  setUp(() {
    _cases = CasesRepository(':memory:');
    _comments = CommentsRepository(':memory:');
  });
  tearDown(() {
    _cases.close();
    _comments.close();
  });

  group('POST /api/verify', () {
    test('the record is signed off and the note lands on its thread', () async {
      _cases.importRows([_row()]);

      final response = await _post({
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': 'Maker',
        'comments': 'Lien released, checked in core.',
        'isVerified': 'yes',
      });

      expect(response.statusCode, HttpStatus.ok);
      final body = await _json(response);
      expect(body['success'], isTrue);
      // A plain count, as the import answers with.
      expect(body['data'], 1);
      expect(body['count'], 1);
      expect(body['message'], 'Updated Successfully');

      // Neither queue: the work is finished rather than handed on.
      expect(_statusOf('2287410'), 'Verified');

      // Verifying and saying why are one act, so the note is on the record's
      // own thread under whoever verified it.
      final thread = _comments.forClient('2287410');
      expect(thread, hasLength(1));
      expect(thread.single['comments'], 'Lien released, checked in core.');
      expect(thread.single['user_id'], 'OFF807292');
      expect(thread.single['role'], 'Maker');
    });

    test('a reviewer with nothing to add still verifies', () async {
      _cases.importRows([_row()]);

      final response = await _post({
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': 'Maker',
        'comments': '   ',
        'isVerified': 'yes',
      });

      expect((await _json(response))['data'], 1);
      expect(_statusOf('2287410'), 'Verified');
      // No empty note on the thread to read past.
      expect(_comments.count(), 0);
    });

    test('every case on the client is signed off, and counted', () async {
      // A client id is all the body carries, so it is what the server acts on.
      _cases.importRows([
        _row(lineNo: '1'),
        _row(lineNo: '2'),
        _row(clientId: 'someone-else'),
      ]);

      final response = await _post({
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': 'Maker',
        'isVerified': 'yes',
      });

      expect((await _json(response))['data'], 2);
      expect(_statusOf('someone-else'), 'Pending with Health Checker');
    });

    test('the other spelling of each id is read', () async {
      // A hand-rolled curl sends whichever casing it was written with.
      _cases.importRows([_row()]);

      final response = await _post({
        'clientID': '2287410',
        'userID': 'OFF807292',
        'role': 'Maker',
        'isVerified': 'yes',
      });

      expect((await _json(response))['data'], 1);
      expect(_statusOf('2287410'), 'Verified');
    });

    test('a client nobody stored writes nothing and says so', () async {
      final response = await _post({
        'clientId': 'not-here',
        'userId': 'OFF807292',
        'role': 'Maker',
        'comments': 'Into the void',
        'isVerified': 'yes',
      });

      // Not an error: the count is the answer.
      expect(response.statusCode, HttpStatus.ok);
      expect((await _json(response))['data'], 0);
    });

    test('the record and the verifier are both required', () async {
      _cases.importRows([_row()]);

      for (final body in [
        {'userId': 'OFF807292', 'role': 'Maker', 'isVerified': 'yes'},
        {'clientId': '2287410', 'role': 'Maker', 'isVerified': 'yes'},
        {'clientId': ' ', 'userId': 'OFF807292', 'role': 'Maker'},
      ]) {
        final response = await _post(body);

        expect(response.statusCode, HttpStatus.badRequest);
        expect((await _json(response))['success'], isFalse);
      }
      // Nothing signed off on the way past.
      expect(_statusOf('2287410'), 'Pending with Health Checker');
    });

    test('without a sign-off only the note is written', () async {
      _cases.importRows([_row()]);

      final response = await _post({
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': 'Maker',
        'comments': 'Waiting on the branch.',
        'isVerified': 'no',
      });

      // The maker looked and had something to say, which is not a decision:
      // the record stays in the queue it was already in.
      expect((await _json(response))['success'], isTrue);
      expect((await _json(response))['data'], 0);
      expect(_statusOf('2287410'), 'Pending with Health Checker');
      expect(_comments.forClient('2287410'), hasLength(1));
    });

    test('a word this server cannot read is a no, absent too', () async {
      _cases.importRows([_row()]);

      for (final flag in [null, '', 'no', 'nahi', 'maybe', '0']) {
        await _post({
          'clientId': '2287410',
          'userId': 'OFF807292',
          'role': 'Maker',
          if (flag != null) 'isVerified': flag,
        });

        // The same rule the sign-in menu reads its `isActive` by: anything
        // unrecognised must not sign a record off by accident.
        expect(
          _statusOf('2287410'),
          'Pending with Health Checker',
          reason: 'isVerified: $flag',
        );
      }
    });

    test('the word or the letter, in any casing, signs it off', () async {
      for (final flag in ['yes', 'YES', ' y ', 'true', '1']) {
        _cases.importRows([_row()]);

        await _post({
          'clientId': '2287410',
          'userId': 'OFF807292',
          'role': 'Maker',
          'isVerified': flag,
        });

        expect(_statusOf('2287410'), 'Verified', reason: 'isVerified: $flag');
      }
    });

    test('the older isVerify spelling is still read', () async {
      // A caller written against the first shape of this endpoint keeps
      // working; the answer does not depend on which word it learned.
      _cases.importRows([_row()]);

      await _post({
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': 'Maker',
        'isVerify': 'Y',
      });

      expect(_statusOf('2287410'), 'Verified');
    });

    test('a template this build cannot name may do neither', () async {
      _cases.importRows([_row()]);

      for (final role in ['Regional Supervisor', 'CPU User', '']) {
        final response = await _post({
          'clientId': '2287410',
          'userId': 'r14878',
          'role': role,
          'comments': 'Signing this off myself',
          'isVerified': 'yes',
        });

        // Every template has addComment for saying something about a record.
        // Moving one along the handover is the two sides' alone, and a client
        // that offers the button to anyone else is not the last word on it.
        expect(response.statusCode, HttpStatus.forbidden, reason: role);
        expect((await _json(response))['success'], isFalse, reason: role);
      }
      expect(_statusOf('2287410'), 'Pending with Health Checker');
      // Not even the note: the whole call was refused.
      expect(_comments.count(), 0);
    });

    test('the template is read as forgivingly as everywhere else', () async {
      _cases.importRows([_row()]);

      final response = await _post({
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': '  maker  ',
        'isVerified': 'yes',
      });

      expect(response.statusCode, HttpStatus.ok);
      expect(_statusOf('2287410'), 'Verified');
    });

    test('the CPU side approves a record on to the health check', () async {
      _cases.importRows([
        {..._row(), 'status': 'Pending with CPU', 'checker': 'r14878'},
      ]);

      final response = await _post({
        'clientId': '2287410',
        'userId': 'r14878',
        'role': 'Checker',
        'comments': 'Documents in order.',
        'status': 'Approved',
      });

      expect((await _json(response))['data'], 1);
      // The other half of the handover: out of the CPU queue and into the
      // health check's, which is the only thing that ever refills it.
      expect(_statusOf('2287410'), 'Pending with Health Checker');
      expect(_comments.forClient('2287410').single['role'], 'Checker');
    });

    test('neither side may send the other\u2019s flag', () async {
      _cases.importRows([_row()]);

      final approvingMaker = await _post({
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': 'Maker',
        'status': 'Approved',
      });
      final verifyingChecker = await _post({
        'clientId': '2287410',
        'userId': 'r14878',
        'role': 'Checker',
        'isVerified': 'yes',
      });

      // A screen that wires the wrong flag has to hear about it; doing
      // nothing quietly would look like the record moving on.
      expect(approvingMaker.statusCode, HttpStatus.forbidden);
      expect(verifyingChecker.statusCode, HttpStatus.forbidden);
      expect(_statusOf('2287410'), 'Pending with Health Checker');
      expect(_comments.count(), 0);
    });

    test('saying no on the other side\u2019s flag is not refused', () async {
      // A client that always sends both keys is stating a fact rather than
      // asking for anything.
      _cases.importRows([_row()]);

      final response = await _post({
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': 'Maker',
        'isVerified': 'yes',
        'status': 'Reject',
      });

      expect(response.statusCode, HttpStatus.ok);
      expect(_statusOf('2287410'), 'Verified');
    });

    test('a record only moves out of the queue it is in', () async {
      // Already signed off. An approval must not drag it back into the
      // maker's grid.
      _cases.importRows([
        {..._row(), 'status': 'Verified'},
      ]);

      final response = await _post({
        'clientId': '2287410',
        'userId': 'r14878',
        'role': 'Checker',
        'status': 'Approved',
      });

      expect((await _json(response))['data'], 0);
      expect(_statusOf('2287410'), 'Verified');
    });

    test('the older comment key is still read', () async {
      _cases.importRows([_row()]);

      await _post({
        'clientId': '2287410',
        'userId': 'OFF807292',
        'role': 'Maker',
        'verificationComment': 'Written against the first shape.',
        'isVerified': 'yes',
      });

      expect(
        _comments.forClient('2287410').single['comments'],
        'Written against the first shape.',
      );
    });

    test('a note carrying a file arrives as multipart', () async {
      _cases.importRows([_row()]);

      final response = await _postForm(
        {
          'clientId': '2287410',
          'userId': 'OFF807292',
          'role': 'Maker',
          'comments': 'Statement attached.',
          'isVerified': 'yes',
        },
        filename: 'lien.xlsx',
      );

      expect(response.statusCode, HttpStatus.ok);
      expect((await _json(response))['data'], 1);
      expect(_statusOf('2287410'), 'Verified');

      // Only the name: this stub has nowhere to serve bytes back from.
      final stored = _comments.forClient('2287410').single;
      expect(stored['comments'], 'Statement attached.');
      expect(stored['support_document'], 'lien.xlsx');
    });

    test('a spelled-out null on a form is the side that had no say', () async {
      // A form field is text or it is nothing, so the client spells its nulls
      // out — see `VerifyRequest.toFields`. The word must move a record exactly
      // as far as an absent flag does, which is nowhere: read as a value, it
      // would be a checker verifying and a maker approving in the same breath.
      _cases
        ..importRows([_row()])
        ..importRows([
          _row(clientId: '1130488', status: 'Pending with CPU'),
        ]);

      // The maker's half: a note with a file, and no decision on it.
      final note = await _postForm(
        {
          'clientId': '2287410',
          'userId': 'OFF807292',
          'role': 'Maker',
          'comments': 'Statement attached, still reading it.',
          'isVerified': 'null',
          'status': 'null',
        },
        filename: 'lien.xlsx',
      );
      expect(note.statusCode, HttpStatus.ok);
      expect((await _json(note))['data'], 0);
      expect(_statusOf('2287410'), 'Pending with Health Checker');

      // The checker's half: the null flag is not theirs to set, so it is not
      // refused either — the approval beside it still lands.
      final approval = await _postForm(
        {
          'clientId': '1130488',
          'userId': 'r14878',
          'role': 'Checker',
          'comments': 'Documents in order.',
          'isVerified': 'null',
          'status': 'Approved',
        },
        filename: 'proof.pdf',
      );
      expect(approval.statusCode, HttpStatus.ok);
      expect((await _json(approval))['data'], 1);
      expect(_statusOf('1130488'), 'Pending with Health Checker');
    });

    test('a note is anyone\u2019s, whatever their template', () async {
      // Every template may comment on a record, and the comment box posts
      // through here now — so the gate is on the flags, not on the door.
      _cases.importRows([_row()]);

      final response = await _post({
        'clientId': '2287410',
        'userId': 'someone',
        'role': 'Regional Supervisor',
        'comments': 'Passing through.',
        'isVerified': 'no',
        'status': null,
      });

      expect(response.statusCode, HttpStatus.ok);
      expect(_comments.forClient('2287410'), hasLength(1));
      // Nothing moved: a note decides nothing, whoever left it.
      expect((await _json(response))['data'], 0);
      expect(_statusOf('2287410'), 'Pending with Health Checker');
    });

    test('a rejection is a note, not a move', () async {
      _cases.importRows([
        {..._row(), 'status': 'Pending with CPU'},
      ]);

      final response = await _post({
        'clientId': '2287410',
        'userId': 'r14878',
        'role': 'Checker',
        'comments': 'Missing the statement.',
        'status': 'Reject',
      });

      expect(response.statusCode, HttpStatus.ok);
      expect((await _json(response))['data'], 0);
      // Still theirs to chase: rejecting is what the note was for.
      expect(_statusOf('2287410'), 'Pending with CPU');
      expect(_comments.forClient('2287410'), hasLength(1));
    });

    test('a status this server does not read moves nothing', () async {
      _cases.importRows([
        {..._row(), 'status': 'Pending with CPU'},
      ]);

      for (final decision in [null, '', 'maybe', 'approve later']) {
        await _post({
          'clientId': '2287410',
          'userId': 'r14878',
          'role': 'Checker',
          if (decision != null) 'status': decision,
        });

        expect(
          _statusOf('2287410'),
          'Pending with CPU',
          reason: 'status: $decision',
        );
      }
    });

    test('the older isApproved spelling is still read', () async {
      _cases.importRows([
        {..._row(), 'status': 'Pending with CPU'},
      ]);

      await _post({
        'clientId': '2287410',
        'userId': 'r14878',
        'role': 'Checker',
        'isApproved': 'yes',
      });

      expect(_statusOf('2287410'), 'Pending with Health Checker');
    });

    test('a body that is not JSON is refused, not acted on', () async {
      _cases.importRows([_row()]);

      final response = await _post('<html>gateway</html>');

      expect(response.statusCode, HttpStatus.badRequest);
      expect(_statusOf('2287410'), 'Pending with Health Checker');
    });

    test('refuses anything but POST', () async {
      final response = await _post(null, method: HttpMethod.get);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
