import 'dart:io';

import 'package:backend/src/api_envelope.dart';
import 'package:backend/src/cases_repository.dart';
import 'package:backend/src/comments_repository.dart';
import 'package:backend/src/role_queue.dart';
import 'package:backend/src/smart_rows.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/get-smartpointer — one user's queue, for the dashboard grid.
///
/// Takes `employeeCode` and `role` as query parameters, both required:
///
/// ```text
/// GET /api/get-smartpointer?employeeCode=OFF807292&role=Maker
/// ```
///
/// The pair is what makes the answer a queue rather than the whole table. The
/// role names the status that side of the handover works, and the employee
/// code narrows it to the records that are this person's — see `queueForRole`.
/// The dashboard therefore renders what it is given rather than filtering
/// again, and no response ever carries a row its reader may not open.
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

  final params = context.request.uri.queryParameters;
  final employeeCode = (params['employeeCode'] ?? '').trim();
  final role = (params['role'] ?? '').trim();

  // Refused rather than guessed at. There is no longer such a thing as an
  // unfiltered read here, so a caller that sent neither is a bug worth saying
  // out loud — answering it with an empty grid would look like a quiet day.
  if (employeeCode.isEmpty || role.isEmpty) {
    return SmartEnvelope.failure(
      'employeeCode and role are required to read a queue.',
    );
  }

  final queue = queueForRole(role);
  // A template this server cannot name is answered with nothing at all. It is
  // the same answer the client gives an unknown role, and the safe one: the
  // alternative is handing somebody else's records to a spelling nobody
  // recognises.
  final stored =
      queue == null
          ? const <Map<String, dynamic>>[]
          : context.read<CasesRepository>().casesForOwner(
            status: queue.status,
            ownerColumn: queue.ownerColumn,
            employeeCode: employeeCode,
          );

  // The two stores are joined here rather than in either of them: a case is a
  // row that every import overwrites, a comment is an event that outlives one,
  // and they share nothing but the database file. Read once for the whole
  // queue — a per-row lookup would be a select per row on every refresh.
  final messages =
      stored.isEmpty
          ? const <String, MessageSummary>{}
          : context.read<CommentsRepository>().summaryByClient();
  final rows = [
    for (final row in stored)
      smartRow(row, messages: messages['${row['client_id']}']),
  ];
  // The live service answers this call with the same text as the upload — it
  // is not shown anywhere, and matching it keeps the two responses diffable.
  return SmartEnvelope.success(
    message: 'Upload Successful',
    data: {'rows': rows},
  );
}
