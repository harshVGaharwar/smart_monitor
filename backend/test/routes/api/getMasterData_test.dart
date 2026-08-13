import 'dart:convert';
import 'dart:io';

import 'package:backend/src/master_data.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../routes/api/getMasterData.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

Future<Response> _get({HttpMethod method = HttpMethod.get}) {
  final context = _MockRequestContext();
  final uri = Uri.parse('http://localhost/api/getMasterData');
  when(() => context.request).thenReturn(
    method == HttpMethod.get ? Request.get(uri) : Request.post(uri),
  );
  return route.onRequest(context);
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.body()) as Map<String, dynamic>;

Future<Map<String, dynamic>> _data(Response response) async =>
    (await _json(response))['data'] as Map<String, dynamic>;

/// The five the client reads. Named here rather than derived from the source,
/// so dropping one is a failing test rather than a quietly shorter response.
const _lists = [
  'cpus',
  'teams',
  'exceptionCategories',
  'healthCheckCategories',
  'reassignReasons',
];

void main() {
  group('GET /api/getMasterData', () {
    test('answers with all five lists under data', () async {
      final response = await _get();
      expect(response.statusCode, HttpStatus.ok);

      final data = await _data(response);
      expect(data.keys, _lists);

      for (final key in _lists) {
        final list = data[key];
        expect(list, isA<List<dynamic>>(), reason: '$key should be a list');
        // Empty is what the client shows when the call failed, so an empty
        // list served on a success would be indistinguishable from an outage.
        expect(list, isNotEmpty, reason: '$key should not be empty');
        expect(
          (list! as List).every((v) => v is String && v.trim().isNotEmpty),
          isTrue,
          reason: '$key should be non-blank strings',
        );
      }
    });

    test('serves the lists as declared, in order', () async {
      final data = await _data(await _get());
      for (final key in _lists) {
        expect(data[key], masterData[key], reason: key);
      }
    });

    test('takes no parameters — the lists are the same for everyone', () async {
      // Whoever is asking, the answer is identical. Nothing here is narrowed
      // by employee code or role the way a queue read is.
      final anonymous = await _data(await _get());
      final again = await _data(await _get());
      expect(anonymous, again);
    });

    test('envelope carries the fields UAT sends, in that order', () async {
      final body = await _json(await _get());
      expect(body.keys, [
        'code',
        'message',
        'body',
        'success',
        'data',
        'count',
        'userName',
        'userCode',
        'branchName',
        'branchCode',
        'menu',
      ]);
      expect(body['code'], 0);
      expect(body['success'], isTrue);
      expect(body['message'], 'Master Data Loaded');
    });

    test('refuses a non-GET', () async {
      final response = await _get(method: HttpMethod.post);
      expect(response.statusCode, HttpStatus.methodNotAllowed);

      final body = await _json(response);
      expect(body['success'], isFalse);
      expect(body['code'], 1);
      expect(body['data'], isNull);
      expect(body['message'], 'Use GET to read master data.');
    });
  });
}
