import 'dart:io';

import 'package:backend/src/api_envelope.dart';
import 'package:backend/src/comment_rows.dart';
import 'package:backend/src/comments_repository.dart';
import 'package:backend/src/form_body.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/addComment — adds one comment to a case's thread.
///
/// Body:
///
/// ```json
/// {
///   "clientId": "1130488",
///   "userId": "r14878",
///   "comments": "Checked in core, lien released.",
///   "role": "Checker"
/// }
/// ```
///
/// A note carrying evidence is sent as multipart instead, the same four
/// values as form fields and the file under `supportDocument`. Only its name
/// is stored — this stub has nowhere to serve bytes back from.
///
/// `clientId` says which case, `userId` who wrote it, and `role` which side of
/// the handover they were on when they did — kept on the comment rather than
/// looked up later, because a user's template can change and the thread is a
/// record of what was said at the time.
///
/// Answers with the stored comment under `data.comment`, stamped and given the
/// id it was written with, so the caller shows what is stored rather than what
/// it hoped would be.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return SmartEnvelope.failure(
      'Use POST to add a comment.',
      statusCode: HttpStatus.methodNotAllowed,
    );
  }

  final posted = await readPostedBody(context.request);
  if (posted == null) {
    return SmartEnvelope.failure('Expected a JSON body or an uploaded form.');
  }
  final map = posted.fields;

  final clientId = '${map['clientId'] ?? ''}'.trim();
  final userId = '${map['userId'] ?? ''}'.trim();
  final comments = '${map['comments'] ?? ''}'.trim();
  // Not required: a comment with no template on it still belongs on the
  // thread, and refusing one would lose the note over a label.
  final role = '${map['role'] ?? ''}'.trim();

  // Text last, so "you forgot the case" and "you posted nothing" are told
  // apart — the second is the one a user can act on.
  if (clientId.isEmpty || userId.isEmpty) {
    return SmartEnvelope.failure('clientId and userId are required.');
  }
  if (comments.isEmpty) {
    return SmartEnvelope.failure('A comment cannot be empty.');
  }

  final stored = context.read<CommentsRepository>().add(
        clientId: clientId,
        userId: userId,
        role: role,
        comments: comments,
        supportDocument: posted.supportDocument,
      );

  return SmartEnvelope.success(
    message: 'Comment Added',
    data: {'comment': commentRow(stored)},
  );
}
