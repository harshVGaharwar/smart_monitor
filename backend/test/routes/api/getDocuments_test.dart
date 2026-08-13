import 'dart:convert';
import 'dart:io';

import 'package:backend/src/comments_repository.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../routes/api/getDocuments.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

late CommentsRepository _repo;

Future<Response> _get({
  HttpMethod method = HttpMethod.get,
  String? clientId = '1130488',
  String? userId = 'r14878',
  String userKey = 'userID',
}) {
  final context = _MockRequestContext();
  final uri = Uri.parse('http://localhost/api/getDocuments').replace(
    queryParameters: {
      if (clientId != null) 'clientId': clientId,
      if (userId != null) userKey: userId,
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

Future<List<Map<String, dynamic>>> _documents(Response response) async {
  final data = (await _json(response))['data'] as Map<String, dynamic>;
  return (data['documents'] as List).cast<Map<String, dynamic>>();
}

void main() {
  setUp(() => _repo = CommentsRepository(':memory:'));
  tearDown(() => _repo.close());

  group('GET /api/getDocuments', () {
    test('answers with the attachments under data.documents', () async {
      _repo
        ..add(
          clientId: '1130488',
          userId: 'OFF807292',
          role: 'Maker',
          comments: 'Statement attached.',
          supportDocument: 'lien.xlsx',
        )
        ..add(
          clientId: '1130488',
          userId: 'r14878',
          role: 'Checker',
          comments: 'Countersigned.',
          supportDocument: 'proof.pdf',
        );

      final response = await _get();
      expect(response.statusCode, HttpStatus.ok);

      final documents = await _documents(response);
      // Oldest first, as the thread they came off is.
      expect([for (final d in documents) d['fileName']], [
        'lien.xlsx',
        'proof.pdf',
      ]);
      expect(documents.first.keys, [
        'clientId',
        'userID',
        'fileName',
        'uploadedBy',
        'uploadedDate',
      ]);
      expect(documents.first['clientId'], '1130488');
      expect(documents.first['userID'], 'OFF807292');
      expect(documents.first['uploadedBy'], 'Maker');
      expect(documents.first['uploadedDate'], isNotEmpty);
    });

    test('a note that carried no file is not a document', () async {
      // The thread is where documents live, but most of it is just talk.
      _repo
        ..add(
          clientId: '1130488',
          userId: 'mk',
          role: 'Maker',
          comments: 'Nothing attached to this one',
        )
        ..add(
          clientId: '1130488',
          userId: 'mk',
          role: 'Maker',
          comments: 'This one has it',
          supportDocument: 'lien.xlsx',
        );

      final documents = await _documents(await _get());
      expect(documents, hasLength(1));
      expect(documents.single['fileName'], 'lien.xlsx');
    });

    test('reading is not narrowed to whoever uploaded', () async {
      // Whichever side attached a file, the other side has to be able to see
      // it — this endpoint is not gated on a template.
      _repo.add(
        clientId: '1130488',
        userId: 'r14878',
        role: 'Checker',
        comments: 'Countersigned.',
        supportDocument: 'proof.pdf',
      );

      final asMaker = await _documents(await _get(userId: 'OFF807292'));
      expect(asMaker, hasLength(1));
      expect(asMaker.single['userID'], 'r14878');
    });

    test('another case’s attachments are not this one’s', () async {
      _repo
        ..add(
          clientId: '1130488',
          userId: 'mk',
          role: 'Maker',
          comments: 'Ours',
          supportDocument: 'ours.pdf',
        )
        ..add(
          clientId: '9999999',
          userId: 'mk',
          role: 'Maker',
          comments: 'Theirs',
          supportDocument: 'theirs.pdf',
        );

      final documents = await _documents(await _get());
      expect(documents, hasLength(1));
      expect(documents.single['fileName'], 'ours.pdf');
    });

    test('a case with nothing attached answers empty, not absent', () async {
      expect(await _documents(await _get()), isEmpty);
    });

    test('an uploader with no template falls back to their code', () async {
      // An author line is never blank — the rule the comment thread reads by.
      _repo.add(
        clientId: '1130488',
        userId: 'mk',
        role: '',
        comments: 'No template on this one',
        supportDocument: 'lien.xlsx',
      );

      expect((await _documents(await _get())).single['uploadedBy'], 'mk');
    });

    test('the older userId spelling is still read', () async {
      _repo.add(
        clientId: '1130488',
        userId: 'mk',
        role: 'Maker',
        comments: 'Attached',
        supportDocument: 'lien.xlsx',
      );

      final response = await _get(userKey: 'userId');
      expect(response.statusCode, HttpStatus.ok);
      expect(await _documents(response), hasLength(1));
    });

    test('the case and the caller are both required', () async {
      for (final response in [
        await _get(clientId: null),
        await _get(userId: null),
      ]) {
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
