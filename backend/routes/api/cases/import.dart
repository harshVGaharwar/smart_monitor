import 'dart:io';

import 'package:backend/src/cases_repository.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/cases/import — persist the rows the user approved.
///
/// This is the end of the upload flow: the file was parsed by
/// `/api/cases/upload`, the user corrected and pruned rows in the results
/// table, and what survived is written here.
///
/// Re-submitting a corrected file updates the cases it already holds rather
/// than duplicating them — a case is identified by client id, account no and
/// line no together.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'message': 'Use POST to import cases.'},
    );
  }

  final dynamic payload;
  try {
    payload = await context.request.json();
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'Expected a JSON body with a "rows" array.'},
    );
  }

  final raw = payload is List
      ? payload
      : (payload is Map ? payload['rows'] : null);
  if (raw is! List) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'Expected a JSON body with a "rows" array.'},
    );
  }

  final rows = <Map<String, dynamic>>[
    for (final item in raw)
      if (item is Map<String, dynamic>) item,
  ];
  if (rows.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'There were no rows to import.'},
    );
  }

  // A row missing its identity cannot be stored without silently colliding
  // with every other such row, so the whole submit is refused rather than
  // partly written.
  final unidentified = rows.where(_missingKey).length;
  if (unidentified > 0) {
    return Response.json(
      statusCode: HttpStatus.unprocessableEntity,
      body: {
        'message': '$unidentified row(s) are missing a client id, account no '
            'or line no, so they cannot be saved.',
      },
    );
  }

  final result = context.read<CasesRepository>().importRows(rows);
  return Response.json(body: result.toJson());
}

bool _missingKey(Map<String, dynamic> row) {
  for (final key in ['client_id', 'account_no', 'line_no']) {
    if ('${row[key] ?? ''}'.trim().isEmpty) return true;
  }
  return false;
}
