import 'dart:io';

import 'package:backend/src/cases_repository.dart';
import 'package:dart_frog/dart_frog.dart';

/// Opened once for the process rather than per request — SQLite handles are
/// cheap to reuse and reopening the file on every call would serialise them
/// behind each other.
final _repository = CasesRepository(
  Platform.environment['CASES_DB'] ?? 'cases.db',
);

Handler middleware(Handler handler) {
  return handler
      .use(_requestLog)
      .use(_cors)
      .use(provider<CasesRepository>((_) => _repository));
}

/// One line per request, so "did the app actually call this?" is answerable
/// without a proxy. The production build has no request log of its own.
Middleware get _requestLog {
  return (handler) {
    return (context) async {
      final started = DateTime.now();
      final request = context.request;
      final response = await handler(context);
      final ms = DateTime.now().difference(started).inMilliseconds;
      // ignore: avoid_print
      print(
        '${request.method.value.toUpperCase()} ${request.uri.path} '
        '→ ${response.statusCode} (${ms}ms)',
      );
      return response;
    };
  };
}

/// Browser clients are served from the Flutter dev server on a different port,
/// so every response needs CORS headers and the preflight has to be answered
/// here — a multipart POST carrying Authorization always triggers one, and
/// without this the request fails before any route runs.
Middleware get _cors {
  return (handler) {
    return (context) async {
      if (context.request.method == HttpMethod.options) {
        return Response(statusCode: HttpStatus.noContent, headers: _headers);
      }
      final response = await handler(context);
      return response.copyWith(headers: {...response.headers, ..._headers});
    };
  };
}

const _headers = <String, String>{
  // Tighten to the deployed origin before this leaves development.
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
  'Access-Control-Max-Age': '86400',
};
