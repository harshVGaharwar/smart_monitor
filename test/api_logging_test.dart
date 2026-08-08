// The request log. Covered because it is the thing people reach for when the
// app and the server disagree, and a log that quietly stops printing — or one
// that keeps printing in a release build — is not noticed until it is needed.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';

/// Everything [debugPrint] was given while [body] ran.
Future<List<String>> _captured(Future<void> Function() body) async {
  final lines = <String>[];
  final original = debugPrint;
  debugPrint = (message, {int? wrapWidth}) => lines.add(message ?? '');
  ApiClient.logRequests = true;
  try {
    await body();
  } finally {
    ApiClient.logRequests = false;
    debugPrint = original;
  }
  return lines;
}

ApiClient _client(http.Response Function(http.Request) answer) =>
    ApiClient(client: MockClient((r) async => answer(r)), baseUrl: 'http://x/api');

void main() {
  test('a call prints the request and what came back', () async {
    final lines = await _captured(() async {
      await _client(
        (_) => http.Response('{"code":0,"success":true}', 200),
      ).get('/get-smartpointer');
    });

    expect(lines, hasLength(2));
    expect(lines.first, '→ GET /api/get-smartpointer');
    // Status, method, path, how long it took, and the body.
    expect(lines.last, startsWith('← 200 GET /api/get-smartpointer ('));
    expect(lines.last, endsWith('{"code":0,"success":true}'));
  });

  test('the query is part of the line, the host is not', () async {
    final lines = await _captured(() async {
      await _client(
        (_) => http.Response('{}', 200),
      ).get('/cases', query: {'search': 'cam', 'page': null});
    });

    // The host is the same on every line and only pushes the interesting part
    // off the edge; a dropped null filter should not show up either.
    expect(lines.first, '→ GET /api/cases?search=cam');
  });

  test('a refused call is marked, not printed as if it worked', () async {
    final lines = await _captured(() async {
      try {
        await _client(
          (_) => http.Response('{"message":"Not authorised"}', 401),
        ).get('/get-smartpointer');
      } on ApiException {
        // The log is what this test is about.
      }
    });

    expect(lines.last, startsWith('✗ 401 GET /api/get-smartpointer ('));
    // The server's own words, so the reason is in the log rather than only in
    // the exception the caller may swallow.
    expect(lines.last, contains('Not authorised'));
  });

  test('a long body is cut rather than filling the console', () async {
    final lines = await _captured(() async {
      await _client(
        (_) => http.Response('{"rows":[${'"x",' * 500}]}', 200),
      ).get('/get-smartpointer');
    });

    expect(lines.last, contains('… (+'));
    expect(lines.last, contains('more)'));
  });

  test('an empty body says so rather than trailing off', () async {
    final lines = await _captured(() async {
      await _client((_) => http.Response('', 200)).get('/get-smartpointer');
    });

    expect(lines.last, endsWith('(empty body)'));
  });

  test('an upload logs the file, never the bytes', () async {
    final lines = await _captured(() async {
      await _client((_) => http.Response('{}', 200)).uploadBytes(
        '/read-excel',
        bytes: Uint8List(2048),
        filename: 'HealthCheck.xlsx',
      );
    });

    expect(lines.first, '→ POST /api/read-excel  HealthCheck.xlsx, 2 KB');
  });

  test('nothing is printed when logging is off', () async {
    final lines = <String>[];
    final original = debugPrint;
    debugPrint = (message, {int? wrapWidth}) => lines.add(message ?? '');
    // The default in a release build, so a shipped app never logs the customer
    // names a response carries.
    ApiClient.logRequests = false;
    try {
      await _client((_) => http.Response('{}', 200)).get('/get-smartpointer');
    } finally {
      debugPrint = original;
    }

    expect(lines, isEmpty);
  });
}
