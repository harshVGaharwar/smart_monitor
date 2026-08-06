import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
      baseUrl = baseUrl ?? AppConstants.apiBaseUrl;

  void setAuthToken(String? token) => _authToken = token;

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
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers(json: false))
      ..files.add(
        http.MultipartFile.fromBytes(field, bytes, filename: filename),
      );
    if (fields != null) request.fields.addAll(fields);

    try {
      final streamed = await _client
          .send(request)
          .timeout(AppConstants.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Upload timed out. Check your connection.');
    } on http.ClientException catch (e) {
      // The http package wraps socket/DNS failures in ClientException, so
      // this one catch covers both web and native transports.
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
      return _decode(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('The request timed out. Check your connection.');
    } on http.ClientException catch (e) {
      // The http package wraps socket/DNS failures in ClientException, so
      // this one catch covers both web and native transports.
      throw ApiException('Could not reach the server: ${e.message}');
    }
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
