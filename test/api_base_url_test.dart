// Pointing the app at a different backend is a --dart-define away, and the
// URL that arrives is whatever someone typed. These pin how it is joined to
// the endpoint paths, since a malformed one fails as an unreadable response
// rather than as an obviously bad address.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_monitor/core/api_client.dart';

/// The URL the client actually requested for [ApiClient.get] of `/cases`.
Future<Uri> _requestedUri(String baseUrl) async {
  late Uri seen;
  final client = ApiClient(
    baseUrl: baseUrl,
    client: MockClient((request) async {
      seen = request.url;
      return http.Response(jsonEncode({'rows': <dynamic>[]}), 200);
    }),
  );
  await client.get('/cases');
  return seen;
}

void main() {
  test('a plain base url is joined as written', () async {
    final uri = await _requestedUri('https://smart.internal/api');

    expect(uri.toString(), 'https://smart.internal/api/cases');
  });

  test('a trailing slash does not produce a double slash', () async {
    final uri = await _requestedUri('https://smart.internal/api/');

    // Regression: this used to request /api//cases, which a real server
    // answers with a redirect or a 404 rather than the resource.
    expect(uri.path, '/api/cases');
    expect(uri.toString(), isNot(contains('//cases')));
  });

  test('several trailing slashes are all trimmed', () async {
    final uri = await _requestedUri('https://smart.internal/api///');

    expect(uri.path, '/api/cases');
  });

  test('surrounding whitespace is ignored', () async {
    final uri = await _requestedUri('  https://smart.internal/api  ');

    expect(uri.toString(), 'https://smart.internal/api/cases');
  });

  test('a host with no path still works', () async {
    final uri = await _requestedUri('https://smart.internal');

    expect(uri.toString(), 'https://smart.internal/cases');
  });

  test('the exposed baseUrl is the normalised one', () {
    final client = ApiClient(baseUrl: 'https://smart.internal/api/');

    expect(client.baseUrl, 'https://smart.internal/api');
    client.close();
  });
}
