import 'dart:io';

import 'package:backend/src/api_envelope.dart';
import 'package:backend/src/cases_repository.dart';
import 'package:backend/src/comments_repository.dart';
import 'package:backend/src/form_body.dart';
import 'package:backend/src/role_queue.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/verify — a record moving along the handover.
///
/// Body:
///
/// ```json
/// {
///   "clientId": "2287410",
///   "userId": "OFF807292",
///   "role": "Maker",
///   "comments": "Lien released, checked in core.",
///   "isVerified": "yes",
///   "status": null
/// }
/// ```
///
/// A note carrying evidence is sent as multipart instead, the same values as
/// form fields and the file under `supportDocument`. Only its name is stored —
/// this stub has nowhere to serve bytes back from.
///
/// Not a case: the client has no business restating columns it never edited,
/// and `clientId` is enough for the server to find the row it holds.
///
/// Two fields carry the two halves of the handover the queues describe, and
/// each belongs to one side of it:
///
/// ```text
/// Pending with CPU  --status: Approved--> Pending with Health Checker
///   (the checker's)                             (the maker's)
///                                          --isVerified: yes--> Verified
///                                                               (nobody's)
/// ```
///
/// `status` is the CPU side's decision — `Approved` or `Reject` — and is null
/// from anyone else, who has none to make. `Reject` keeps the record where it
/// is; the note is what the call was for.
///
/// A record only ever moves out of the queue it is in, so an approval cannot
/// drag a finished case back into the maker's grid.
///
/// Anything but an affirmative — the other side's field, an absent one, a word
/// this server does not read — leaves the case where it is: the reviewer
/// looked and had something to say, which is a note rather than a decision.
/// The same rule the sign-in menu reads its `isActive` by. A yes may be
/// spelled `yes`, `y`,
/// `true` or `1`, in any casing.
///
/// Who may say what is the server's to decide, whatever a screen offers: a
/// maker may verify and not approve, and a checker the reverse. Saying *no* on
/// the other side's flag is not refused — a client that always sends both keys
/// is stating a fact rather than asking for anything.
///
/// A call carrying no yes at all is a note, and a note is anyone's. Every
/// template may comment on a record, so the gate sits on the flags, which is
/// where the authority actually matters, rather than on the door.
///
/// The comment, when there is one, is written to the same thread
/// `/api/addComment` writes to, under the same `userId` and `role`. Acting on a
/// record and saying why are one act, and whoever opens it next reads the note
/// where every other one on the case already is.
///
/// Answers with the number of rows moved under `data`, as
/// `/api/update-smartpointer` does. Older spellings of two keys are still
/// read: `verificationComment` for `comments`, `isVerify` for `isVerified`,
/// and `isApproved: yes` for `status: Approved`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return SmartEnvelope.failure(
      'Use POST to verify a record.',
      statusCode: HttpStatus.methodNotAllowed,
    );
  }

  final posted = await readPostedBody(context.request);
  if (posted == null) {
    return SmartEnvelope.failure('Expected a JSON body or an uploaded form.');
  }

  // Both spellings of each id are read, the way the sign-in route takes `Name`
  // beside `name`, so a hand-rolled curl works whichever it sends.
  final map = posted.fields;
  final clientId = '${map['clientId'] ?? map['clientID'] ?? ''}'.trim();
  final userId = '${map['userId'] ?? map['userID'] ?? ''}'.trim();
  final role = '${map['role'] ?? ''}'.trim();
  final comment =
      '${map['comments'] ?? map['verificationComment'] ?? ''}'.trim();
  final verifying = _isYes(map['isVerified'] ?? map['isVerify']);
  // `Approved` is the word; a `Reject` — or nothing at all — is not one.
  final approving =
      '${map['status'] ?? ''}'.trim().toLowerCase() == 'approved' ||
      _isYes(map['isApproved']);

  // The comment is not required: a reviewer with nothing to add should not
  // have to type something to get past this.
  if (clientId.isEmpty || userId.isEmpty) {
    return SmartEnvelope.failure('clientId and userId are required.');
  }

  final maker = isMakerRole(role);
  final checker = isCheckerRole(role);
  // Each flag belongs to one side. Refused rather than ignored: a screen that
  // wires the wrong one has to hear about it, and silently doing nothing looks
  // like the record moving on to whoever pressed the button.
  //
  // A template that is neither side falls through both of these when it says
  // no to both, which is the note every template may leave.
  if (!maker && !checker && (verifying || approving)) {
    return SmartEnvelope.failure(
      'Only the health check and CPU sides can act on a record.',
      statusCode: HttpStatus.forbidden,
    );
  }
  if (maker && approving) {
    return SmartEnvelope.failure(
      'The health check side verifies a record; it does not approve one.',
      statusCode: HttpStatus.forbidden,
    );
  }
  if (checker && verifying) {
    return SmartEnvelope.failure(
      'The CPU side approves a record; verifying it is the health check side.',
      statusCode: HttpStatus.forbidden,
    );
  }

  // Only a yes moves the record, and only out of the queue its side owns.
  // Without one this call is the note and nothing else.
  final cases = context.read<CasesRepository>();
  final updated = switch ((verifying, approving)) {
    (true, _) => cases.setStatusForClient(
      clientId: clientId,
      status: _verified,
      from: _withHealthChecker,
    ),
    (_, true) => cases.setStatusForClient(
      clientId: clientId,
      status: _withHealthChecker,
      from: _withCpu,
    ),
    _ => 0,
  };

  if (comment.isNotEmpty) {
    context.read<CommentsRepository>().add(
      clientId: clientId,
      userId: userId,
      role: role,
      comments: comment,
      supportDocument: posted.supportDocument,
    );
  }

  return SmartEnvelope.success(
    // Verbatim from the live service, as the import answers with.
    message: 'Updated Successfully',
    data: updated,
    count: updated,
  );
}

/// Whether [value] says yes.
///
/// Anything it does not recognise is a no, an absent flag included — the rule
/// `MenuPermission.isEnabled` reads the client's flags by. A word this server
/// cannot read must not sign a record off by accident.
bool _isYes(Object? value) => const {
  'yes',
  'y',
  'true',
  '1',
}.contains('${value ?? ''}'.trim().toLowerCase());

/// Where a signed-off record lands. Not a queue: neither template reads it,
/// which is what makes the work finished rather than handed on.
const _verified = 'Verified';

/// The two queues, spelled as the store holds them.
const _withHealthChecker = 'Pending with Health Checker';
const _withCpu = 'Pending with CPU';
