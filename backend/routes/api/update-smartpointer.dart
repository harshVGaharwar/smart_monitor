import 'dart:io';

import 'package:backend/src/api_envelope.dart';
import 'package:backend/src/cases_repository.dart';
import 'package:backend/src/update_request.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/update-smartpointer — persist the rows the user approved.
///
/// This is the end of the upload flow: the file was parsed by
/// `/api/read-excel`, the user corrected and pruned rows in the results
/// table, and what survived is written here. The write side of
/// `/api/get-smartpointer`, which serves the same rows back.
///
/// Re-submitting a corrected file updates the cases it already holds rather
/// than duplicating them — a case is identified by client id, account no and
/// line no together.
///
/// The body is an [UpdateRequestModel]: a `rows` array of cases, each field a
/// string. `data` answers with the rows as they were stored, in that same
/// shape, alongside the counts — so the client can show what the submit
/// actually wrote rather than what it hoped it did.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return SmartEnvelope.failure(
      'Use POST to import cases.',
      statusCode: HttpStatus.methodNotAllowed,
    );
  }

  final dynamic payload;
  try {
    payload = await context.request.json();
  } catch (_) {
    return SmartEnvelope.failure(
      'Expected a JSON body with a "rows" array.',
    );
  }

  // A bare array is accepted as the rows themselves: the endpoint has always
  // taken one, and a client posting that shape predates the model.
  final raw = payload is List
      ? payload
      : (payload is Map ? payload['rows'] : null);
  if (raw is! List) {
    return SmartEnvelope.failure(
      'Expected a JSON body with a "rows" array.',
    );
  }

  final request = UpdateRequestModel.fromJson({'rows': raw});
  if (request.rows.isEmpty) {
    return SmartEnvelope.failure('There were no rows to import.');
  }

  // A row missing its identity cannot be stored without silently colliding
  // with every other such row, so the whole submit is refused rather than
  // partly written.
  final unidentified = request.rows.where((row) => !row.hasIdentity).length;
  if (unidentified > 0) {
    return SmartEnvelope.failure(
      '$unidentified row(s) are missing a client id, account no or line no, '
      'so they cannot be saved.',
      statusCode: HttpStatus.unprocessableEntity,
    );
  }

  final result = context.read<CasesRepository>().importRows([
    for (final row in request.rows) row.toJson(),
  ]);
  return SmartEnvelope.success(
    // Verbatim from the live service: the import toast shows it.
    message: 'Updated Successfully',
    data: {
      'rows': [
        for (final row in result.rows) UpdateRequestRow.fromJson(row).toJson(),
      ],
      'inserted': result.inserted,
      'updated': result.updated,
      'total': result.total,
    },
    count: result.total,
  );
}
