import 'dart:convert';
import 'dart:io';

import 'package:backend/src/comments_repository.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../routes/api/getComments.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

late CommentsRepository _repo;

Future<Response> _get({
  HttpMethod method = HttpMethod.get,
  String? clientId = '1130488',
  String? userId = 'r14878',
}) {
  final context = _MockRequestContext();
  final uri = Uri.parse('http://localhost/api/getComments').replace(
    queryParameters: {
      if (clientId != null) 'clientId': clientId,
      if (userId != null) 'userId': userId,
    },
  );
  when(() => context.read<CommentsRepository>()).thenReturn(_repo);
  when(() => context.request).thenReturn(
    method == HttpMethod.get ? Request.get(uri) : Request.post(uri),
  );
  return route.onRequest(context);
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.body()) as Map<String, dynamic>;

Future<List<Map<String, dynamic>>> _comments(Response response) async {
  final data = (await _json(response))['data'] as Map<String, dynamic>;
  return (data['comments'] as List).cast<Map<String, dynamic>>();
}

void main() {
  setUp(() => _repo = CommentsRepository(':memory:'));
  tearDown(() => _repo.close());

  group('GET /api/getComments', () {
    test('answers with the thread under data.comments', () async {
      _repo
        ..add(
          clientId: '1130488',
          userId: 'mk',
          role: 'Maker',
          comments: 'Raised',
        )
        ..add(
          clientId: '1130488',
          userId: 'r14878',
          role: 'Checker',
          comments: 'Cleared',
        );

      final response = await _get();
      expect(response.statusCode, HttpStatus.ok);

      final comments = await _comments(response);
      // Oldest first, and shaped as addComment echoes one back.
      expect([for (final c in comments) c['comments']], ['Raised', 'Cleared']);
      expect(comments.first.keys, [
        'clientId',
        'userId',
        'role',
        'comments',
        'supportDocument',
        'reason',
        'createdAt',
      ]);
    });

    test('reading is not narrowed to what the reader wrote', () async {
      // A maker asking has to see the checker's note, or the endpoint answers
      // a different question than the panel asks.
      _repo.add(
        clientId: '1130488',
        userId: 'r14878',
        role: 'Checker',
        comments: 'Cleared',
      );

      expect(await _comments(await _get(userId: 'OFF807292')), hasLength(1));
    });

    test("another case's thread is not this one", () async {
      _repo.add(
        clientId: 'somewhere-else',
        userId: 'mk',
        role: 'Maker',
        comments: 'Not yours',
      );

      expect(await _comments(await _get()), isEmpty);
    });

    test('a case nobody has commented on is empty, not an error', () async {
      final response = await _get();

      expect((await _json(response))['success'], isTrue);
      expect(await _comments(response), isEmpty);
    });

    test('the case and the caller are both required', () async {
      for (final response in [
        await _get(clientId: null),
        await _get(userId: null),
        await _get(clientId: ''),
        await _get(userId: ' '),
      ]) {
        expect(response.statusCode, HttpStatus.badRequest);
        expect((await _json(response))['success'], isFalse);
      }
    });

    test('refuses anything but GET', () async {
      final response = await _get(method: HttpMethod.post);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
