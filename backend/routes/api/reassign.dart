import 'dart:io';

import 'package:backend/src/api_envelope.dart';
import 'package:backend/src/cases_repository.dart';
import 'package:backend/src/comments_repository.dart';
import 'package:backend/src/form_body.dart';
import 'package:backend/src/role_queue.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/reassign — routing a record to another CPU and team.
///
/// Body:
///
/// ```json
/// {
///   "clientId": "2287410",
///   "userId": "OFF807292",
///   "role": "Maker",
///   "cpu": "Chennai",
///   "team": "Disbursement Team",
///   "reason": "Incorrect CPU mapping",
///   "comments": "Wrong team, sending this back.",
///   "document": null
/// }
/// ```
///
/// A reassignment carrying evidence is sent as multipart instead, the same
/// values as form fields and the file under `document`. Only its name is
/// stored — this stub has nowhere to serve bytes back from.
///
/// The record goes back to `Pending with CPU`, the CPU side's bucket, carrying
/// its new `cpu` and `team`. All three move together: a case that changed
/// hands but kept its status would sit in the wrong queue under the right
/// team.
///
/// The health check side only. Routing a record onward is their call, and a
/// screen that offers the button to anyone else is not the last word on it.
///
/// `reason` and `comments` are two different things and are kept apart: the
/// note is what the reviewer typed, the reason is which of the workflow's own
/// answers they picked. Both land on the record's comment thread, where the
/// CPU side reads them when the case arrives.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return SmartEnvelope.failure(
      'Use POST to reassign a record.',
      statusCode: HttpStatus.methodNotAllowed,
    );
  }

  final posted = await readPostedBody(context.request, fileField: 'document');
  if (posted == null) {
    return SmartEnvelope.failure('Expected a JSON body or an uploaded form.');
  }

  // Both spellings of each id are read, the way the sign-in route takes `Name`
  // beside `name`, so a hand-rolled curl works whichever it sends.
  final map = posted.fields;
  final clientId = '${map['clientId'] ?? map['clientID'] ?? ''}'.trim();
  final userId = '${map['userId'] ?? map['userID'] ?? ''}'.trim();
  final role = '${map['role'] ?? ''}'.trim();
  final cpu = '${map['cpu'] ?? ''}'.trim();
  final team = '${map['team'] ?? ''}'.trim();
  final reason = '${map['reason'] ?? ''}'.trim();
  final comment = '${map['comments'] ?? ''}'.trim();

  if (clientId.isEmpty || userId.isEmpty) {
    return SmartEnvelope.failure('clientId and userId are required.');
  }
  // Told apart from the missing ids: this one the user can fix by picking
  // from the two dropdowns in front of them.
  if (cpu.isEmpty || team.isEmpty) {
    return SmartEnvelope.failure(
      'A reassignment needs both a CPU and a team.',
    );
  }
  if (!isMakerRole(role)) {
    return SmartEnvelope.failure(
      'Only the health check side can reassign a record.',
      statusCode: HttpStatus.forbidden,
    );
  }

  final moved = context.read<CasesRepository>().reassignForClient(
    clientId: clientId,
    cpu: cpu,
    team: team,
    status: _withCpu,
    // Who handed it over. The record carries it so the CPU side opening the
    // case can see who sent it without reading down the thread for a name.
    assignedBy: userId,
    from: _withHealthChecker,
  );

  // Written whenever there is anything to read: a reassignment with neither a
  // note nor a reason leaves no thread entry, which is honest — nothing was
  // said.
  if (comment.isNotEmpty || reason.isNotEmpty || posted.supportDocument != '') {
    context.read<CommentsRepository>().add(
      clientId: clientId,
      userId: userId,
      role: role,
      comments: comment,
      reason: reason,
      supportDocument: posted.supportDocument,
    );
  }

  return SmartEnvelope.success(
    message: 'Successfully assigned to new user',
    data: moved,
    count: moved,
  );
}

/// The two queues, spelled as the store holds them.
const _withCpu = 'Pending with CPU';
const _withHealthChecker = 'Pending with Health Checker';
