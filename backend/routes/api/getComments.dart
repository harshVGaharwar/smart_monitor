import 'dart:io';

import 'package:backend/src/api_envelope.dart';
import 'package:backend/src/comment_rows.dart';
import 'package:backend/src/comments_repository.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/getComments — the thread on one case.
///
/// ```text
/// GET /api/getComments?clientId=1130488&userId=r14878
/// ```
///
/// The comments sit under `data.comments`, oldest first, shaped exactly as
/// `/api/addComment` echoes one back.
///
/// `clientId` picks the thread. `userId` is who is asking, and is required
/// rather than optional so the call is attributable — but it does not narrow
/// the answer: a maker has to read what the checker wrote, or the thread is
/// two monologues.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return SmartEnvelope.failure(
      'Use GET to read a comment thread.',
      statusCode: HttpStatus.methodNotAllowed,
    );
  }

  final params = context.request.uri.queryParameters;
  final clientId = (params['clientId'] ?? '').trim();
  final userId = (params['userId'] ?? '').trim();

  if (clientId.isEmpty || userId.isEmpty) {
    return SmartEnvelope.failure('clientId and userId are required.');
  }

  final stored = context.read<CommentsRepository>().forClient(clientId);
  return SmartEnvelope.success(
    message: 'Comments Loaded',
    data: {'comments': [for (final row in stored) commentRow(row)]},
  );
}
