import 'dart:io';

import 'package:backend/src/api_envelope.dart';
import 'package:backend/src/comments_repository.dart';
import 'package:backend/src/document_rows.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/getDocuments — the files attached to one case.
///
/// ```text
/// GET /api/getDocuments?clientId=1130488&userID=r14878
/// ```
///
/// The documents sit under `data.documents`, oldest first.
///
/// `clientId` picks the case. `userID` is who is asking, and is required rather
/// than optional so the call is attributable — but it does not narrow the
/// answer. Documents are nobody's in particular: whichever side attached one,
/// the other side has to be able to open it, so this endpoint is not gated on a
/// template the way `/api/verify` is.
///
/// There is no document store behind this. A file only ever arrives attached to
/// a note or a reassignment, so the answer is that thread filtered down to the
/// rows that carried one — see `CommentsRepository.documentsForClient`. Only
/// names are held: this stub has nowhere to serve bytes back from.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return SmartEnvelope.failure(
      'Use GET to read a case’s documents.',
      statusCode: HttpStatus.methodNotAllowed,
    );
  }

  final params = context.request.uri.queryParameters;
  final clientId = (params['clientId'] ?? '').trim();
  // Both spellings are read, as the case endpoints read theirs, so a
  // hand-rolled curl works whichever it sends.
  final userId = (params['userID'] ?? params['userId'] ?? '').trim();

  if (clientId.isEmpty || userId.isEmpty) {
    return SmartEnvelope.failure('clientId and userID are required.');
  }

  final stored = context.read<CommentsRepository>().documentsForClient(
    clientId,
  );
  return SmartEnvelope.success(
    message: 'Documents Loaded',
    data: {'documents': [for (final row in stored) documentRow(row)]},
  );
}
