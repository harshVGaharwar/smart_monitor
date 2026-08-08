import 'dart:io';

import 'package:backend/src/api_envelope.dart';
import 'package:backend/src/cases_repository.dart';
import 'package:backend/src/smart_rows.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/get-smartpointer — every stored case, for the dashboard grid.
///
/// The rows sit under `data.rows` and are shaped exactly as
/// `/api/read-excel` returns them, so one mapping on the client serves both
/// screens. Two fields are added that only exist once a case has been stored:
/// `status` and `imported_at`.
///
/// A database with nothing in it is seeded on startup (see
/// `routes/_middleware.dart`), so this answers with rows on a fresh checkout
/// rather than sending the dashboard to its empty state.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return SmartEnvelope.failure(
      'Use GET to read the stored cases.',
      statusCode: HttpStatus.methodNotAllowed,
    );
  }

  final stored = context.read<CasesRepository>().allCases();
  final rows = [for (final row in stored) smartRow(row)];
  // The live service answers this call with the same text as the upload — it
  // is not shown anywhere, and matching it keeps the two responses diffable.
  return SmartEnvelope.success(
    message: 'Upload Successful',
    data: {'rows': rows},
  );
}
