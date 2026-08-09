import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';

/// A failed request — transport error, timeout, or a non-2xx response.
class ApiException implements Exception {
  /// Null when the request never reached the server.
  final int? statusCode;
  final String message;

  /// Decoded response body, when the server sent one.
  final Object? body;

  const ApiException(this.message, {this.statusCode, this.body});

  /// True for the cases a retry might fix.
  bool get isNetworkError => statusCode == null;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}

/// Thin wrapper over `package:http` for this app's REST calls.
///
/// Every method returns the decoded JSON body (a `Map`, `List`, or null for an
/// empty response) and throws [ApiException] on anything that is not a 2xx.
/// Callers therefore only handle one error type.
class ApiClient {
  final http.Client _client;
  final String baseUrl;

  /// Bearer token sent with every request once [setAuthToken] is called.
  String? _authToken;

  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      // Trailing slashes are stripped rather than trusted: every path here
      // starts with one, and `https://host/api/` + `/read-excel` yields a
      // double slash that servers answer with a redirect or a 404 — which
      // then surfaces as an unreadable response rather than a bad URL.
      baseUrl = _trimSlashes(baseUrl ?? AppConstants.apiBaseUrl);

  void setAuthToken(String? token) => _authToken = token;

  /// Whether every request and response is printed to the console.
  ///
  /// On in a debug build and off in release, so a shipped app never logs
  /// customer names — a response here carries them. Settable because the test
  /// suite turns it off (see `test/flutter_test_config.dart`); a run that
  /// wants the traffic can turn it back on from anywhere.
  static bool logRequests = kDebugMode;

  /// Release the underlying connection pool. Call on sign-out or teardown.
  void close() => _client.close();

  // --- Verbs --------------------------------------------------------------

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) {
    return _send('GET', path, query: query);
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) {
    return _send('POST', path, body: body, query: query);
  }

  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) {
    return _send('PUT', path, body: body, query: query);
  }

  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) {
    return _send('DELETE', path, query: query);
  }

  /// Multipart upload. Web has no file paths, so the bytes are passed directly.
  ///
  /// [fields] carries any accompanying form values (ids, flags).
  Future<dynamic> uploadBytes(
    String path, {
    required Uint8List bytes,
    required String filename,
    String field = 'file',
    Map<String, String>? fields,
  }) async {
    final uri = _uri(path);
    final request =
        http.MultipartRequest('POST', uri)
          ..headers.addAll(_headers(json: false))
          ..files.add(
            http.MultipartFile.fromBytes(field, bytes, filename: filename),
          );
    if (fields != null) request.fields.addAll(fields);

    final started = DateTime.now();
    // The bytes are not logged — a workbook is megabytes of nothing readable.
    _logSent('POST', uri, '$filename, ${_size(bytes.lengthInBytes)}');

    try {
      final streamed = await _client
          .send(request)
          .timeout(AppConstants.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      _logReceived('POST', uri, response, started);
      return _decode(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      _logFailed('POST', uri, 'timed out', started);
      throw ApiException('Upload timed out. Check your connection.');
    } on http.ClientException catch (e) {
      // The http package wraps socket/DNS failures in ClientException, so
      // this one catch covers both web and native transports.
      _logFailed('POST', uri, e.message, started);
      throw ApiException('Could not reach the server: ${e.message}');
    }
  }

  // --- Plumbing -----------------------------------------------------------

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final uri = _uri(path, query);
    final headers = _headers(json: body != null);
    final encoded = body == null ? null : jsonEncode(body);
    final started = DateTime.now();
    _logSent(method, uri, encoded);

    try {
      final http.Response response;
      switch (method) {
        case 'GET':
          response = await _client
              .get(uri, headers: headers)
              .timeout(AppConstants.requestTimeout);
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: encoded)
              .timeout(AppConstants.requestTimeout);
        case 'PUT':
          response = await _client
              .put(uri, headers: headers, body: encoded)
              .timeout(AppConstants.requestTimeout);
        case 'DELETE':
          response = await _client
              .delete(uri, headers: headers, body: encoded)
              .timeout(AppConstants.requestTimeout);
        default:
          throw ApiException('Unsupported method $method');
      }
      _logReceived(method, uri, response, started);
      return _decode(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      _logFailed(method, uri, 'timed out', started);
      throw ApiException('The request timed out. Check your connection.');
    } on http.ClientException catch (e) {
      // The http package wraps socket/DNS failures in ClientException, so
      // this one catch covers both web and native transports.
      _logFailed(method, uri, e.message, started);
      throw ApiException('Could not reach the server: ${e.message}');
    }
  }

  // --- Logging ------------------------------------------------------------
  //
  // Printed rather than returned: "did the app actually call this, and what
  // came back?" is the first question on every wiring problem, and the answer
  // is otherwise only reachable through a proxy or a breakpoint. The local
  // server logs its own side (see `backend/routes/_middleware.dart`), so the
  // two lines can be read against each other.

  /// A request going out.
  void _logSent(String method, Uri uri, String? body) {
    if (!logRequests) return;
    debugPrint('→ $method ${_path(uri)}${body == null ? '' : '  $body'}');
  }

  /// The response to it, with how long it took and what it carried.
  void _logReceived(
    String method,
    Uri uri,
    http.Response response,
    DateTime started,
  ) {
    if (!logRequests) return;
    final ms = DateTime.now().difference(started).inMilliseconds;
    final status = response.statusCode;
    final ok = status >= 200 && status < 300;
    debugPrint(
      '${ok ? '←' : '✗'} $status $method ${_path(uri)} (${ms}ms)  '
      '${_body(response.body)}',
    );
  }

  /// A request that never got a response at all.
  void _logFailed(String method, Uri uri, String reason, DateTime started) {
    if (!logRequests) return;
    final ms = DateTime.now().difference(started).inMilliseconds;
    debugPrint('✗ $method ${_path(uri)} (${ms}ms)  $reason');
  }

  /// The path and query, without the host — the host is the same on every
  /// line and only pushes the interesting part off the edge.
  static String _path(Uri uri) =>
      uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;

  /// [text] in one line, cut at [_logBodyLimit].
  ///
  /// A dashboard response runs to hundreds of rows; the head of it is enough
  /// to see the envelope and the first row, which is what these lines are read
  /// for.
  static String _body(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '(empty body)';
    if (trimmed.length <= _logBodyLimit) return trimmed;
    final cut = trimmed.length - _logBodyLimit;
    return '${trimmed.substring(0, _logBodyLimit)}… (+$cut more)';
  }

  /// How much of a response body a log line carries.
  static const _logBodyLimit = 900;

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _trimSlashes(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    if (query == null || query.isEmpty) return uri;
    // Drop nulls so optional filters can be passed through unconditionally.
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        for (final entry in query.entries)
          if (entry.value != null) entry.key: '${entry.value}',
      },
    );
  }

  Map<String, String> _headers({required bool json}) => {
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json; charset=utf-8',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  /// Turns a response into decoded JSON, or throws with the server's message.
  dynamic _decode(http.Response response) {
    final status = response.statusCode;
    final text = response.body;

    dynamic parsed;
    if (text.isNotEmpty) {
      try {
        parsed = jsonDecode(text);
      } on FormatException {
        // Not JSON — keep the raw text so error messages stay useful.
        parsed = text;
      }
    }

    if (status >= 200 && status < 300) return parsed;

    throw ApiException(
      _errorMessage(parsed) ?? _statusText(status),
      statusCode: status,
      body: parsed,
    );
  }

  /// Pulls a human-readable message out of a typical error envelope.
  String? _errorMessage(dynamic body) {
    if (body is String && body.trim().isNotEmpty) return body.trim();
    if (body is Map) {
      for (final key in ['message', 'error', 'detail', 'title']) {
        final value = body[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    }
    return null;
  }

  String _statusText(int status) => switch (status) {
    400 => 'The request was rejected as invalid.',
    401 => 'Your session has expired. Please sign in again.',
    403 => 'You do not have access to this resource.',
    404 => 'Not found.',
    409 => 'This record was changed by someone else. Reload and retry.',
    422 => 'Some fields did not pass validation.',
    >= 500 => 'The server ran into a problem. Try again shortly.',
    _ => 'Request failed with status $status.',
  };
}
