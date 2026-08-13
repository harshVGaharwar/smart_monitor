import 'dart:convert';
import 'dart:io';

import 'package:backend/src/comments_repository.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../routes/api/addComment.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

late CommentsRepository _repo;

Future<Response> _post(
  Object? body, {
  HttpMethod method = HttpMethod.post,
}) {
  final context = _MockRequestContext();
  final uri = Uri.parse('http://localhost/api/addComment');
  when(() => context.read<CommentsRepository>()).thenReturn(_repo);
  when(() => context.request).thenReturn(
    method == HttpMethod.post
        ? Request.post(uri, body: body is String ? body : jsonEncode(body))
        : Request.get(uri),
  );
  return route.onRequest(context);
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.body()) as Map<String, dynamic>;

Future<Map<String, dynamic>> _comment(Response response) async {
  final data = (await _json(response))['data'] as Map<String, dynamic>;
  return data['comment'] as Map<String, dynamic>;
}

void main() {
  setUp(() => _repo = CommentsRepository(':memory:'));
  tearDown(() => _repo.close());

  group('POST /api/addComment', () {
    test('stores the comment and echoes it back', () async {
      final response = await _post({
        'clientId': '1130488',
        'userId': 'r14878',
        'comments': 'Checked in core, lien released.',
        'role': 'Checker',
      });

      expect(response.statusCode, HttpStatus.ok);
      expect((await _json(response))['success'], isTrue);

      final comment = await _comment(response);
      // The stored comment, not the posted one: the stamp is the server's,
      // and the caller shows what is stored.
      expect(comment['clientId'], '1130488');
      expect(comment['userId'], 'r14878');
      expect(comment['role'], 'Checker');
      expect(comment['comments'], 'Checked in core, lien released.');
      expect(comment['createdAt'], isNotEmpty);
      // The table's key stays in the table. Nothing addresses a note by it,
      // so the wire does not carry it.
      expect(comment.containsKey('id'), isFalse);

      expect(_repo.forClient('1130488'), hasLength(1));
    });

    test('a comment with no template still lands', () async {
      // The role is a label on the note, not permission to leave one.
      final response = await _post({
        'clientId': '1',
        'userId': 'mk',
        'comments': 'No template on this one',
      });

      expect((await _comment(response))['role'], '');
    });

    test('the case and the author are both required', () async {
      for (final body in [
        {'userId': 'mk', 'comments': 'Orphan'},
        {'clientId': '1', 'comments': 'Anonymous'},
        {'clientId': ' ', 'userId': 'mk', 'comments': 'Blank'},
      ]) {
        final response = await _post(body);

        expect(response.statusCode, HttpStatus.badRequest);
        expect((await _json(response))['success'], isFalse);
      }
      expect(_repo.count(), 0);
    });

    test('an empty comment is refused on its own terms', () async {
      final response = await _post({
        'clientId': '1',
        'userId': 'mk',
        'comments': '   ',
      });

      // Told apart from a malformed request: this one the user can fix by
      // typing something.
      expect(response.statusCode, HttpStatus.badRequest);
      expect((await _json(response))['message'], contains('cannot be empty'));
      expect(_repo.count(), 0);
    });

    test('a body that is not JSON is refused, not stored', () async {
      final response = await _post('<html>gateway</html>');

      expect(response.statusCode, HttpStatus.badRequest);
      expect(_repo.count(), 0);
    });

    test('refuses anything but POST', () async {
      final response = await _post(null, method: HttpMethod.get);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
