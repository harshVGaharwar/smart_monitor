import 'add_comment_request.dart';

/// The body of `POST /verify` — a record moving along the handover.
///
/// Not a case: the columns are the server's already, and the only field that
/// identifies anything here is [clientId]. Nothing the reviewer did not touch
/// is restated, so a save can no longer blank a column by echoing a stale copy
/// of it.
///
/// The two flags are the two halves of the handover, one to each side of it:
///
/// ```text
/// Pending with CPU  --isApproved--> Pending with Health Checker
///   (the checker's)                        (the maker's)
///                                            --isVerified--> Verified
///                                                            (nobody's)
/// ```
///
/// A note carrying evidence goes up as multipart, the file under
/// [supportDocument]; one without stays a plain JSON post.
///
/// The key casing is the service's, as in [AddCommentRequest].
class VerifyRequest {
  /// Which record. All the server needs to find the row it holds.
  final String clientId;

  /// Who acted on it — the signed-in user's employee code, the same identity
  /// their queue is read with.
  final String userId;

  /// The template they acted under. Not decoration: the server refuses a flag
  /// the role does not own.
  final String role;

  /// Why, in their words. Optional — a reviewer with nothing to add should not
  /// have to invent something — and lands on the record's comment thread when
  /// there is one.
  final String comments;

  /// The health check side signing the record off. Moves the record to
  /// `Verified` and out of every queue.
  ///
  /// Null when the caller is not the health check side, for the same reason
  /// [status] is null for everyone but the CPU side: a decision nobody made is
  /// not a no, and saying no would claim they considered it.
  final bool? isVerified;

  /// What the CPU side decided about the record, or null when the caller is
  /// not the CPU side — the health check side has no such decision to make
  /// from the comment box, and sending one either way would be inventing it.
  final ApprovalStatus? status;

  /// The evidence behind the note, or null when there is none.
  ///
  /// One file, not a list: the key is singular on the wire, and a note that
  /// needs two documents is two things worth saying separately.
  final CommentAttachment? supportDocument;

  const VerifyRequest({
    required this.clientId,
    required this.userId,
    required this.role,
    this.comments = '',
    this.isVerified,
    this.status,
    this.supportDocument,
  });

  /// Both flags go out on every request, as the word rather than a JSON
  /// boolean — the body carries the whole contract, and "I am not approving"
  /// is a statement rather than a missing field.
  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'userId': userId,
    'role': role,
    'comments': comments,
    // Null rather than absent, both of them: the keys are part of the contract
    // whoever is signed in, and "this side had no say" is worth saying out
    // loud rather than leaving to be inferred from a missing field.
    'isVerified': _yesNo(isVerified),
    'status': status?.label,
  };

  /// The same values as form fields, for the multipart the file rides in.
  ///
  /// Every key that [toJson] carries is carried here too, so the body has one
  /// shape whether or not a file rode along — a reader of the two side by side
  /// should not have to work out which fields the file dropped.
  ///
  /// A form field is text or it is nothing, so a decision nobody made goes as
  /// the word [_null] — the nearest a multipart body gets to the JSON null
  /// [toJson] carries. Empty would have read as a value the reviewer left
  /// blank; this reads as the side that had no say, which is what it is.
  ///
  /// Nothing on the server turns on the spelling: an unrecognised flag is a
  /// no, so `null` moves a record exactly as far as an absent one does — which
  /// is nowhere.
  Map<String, String> toFields() => {
    'clientId': clientId,
    'userId': userId,
    'role': role,
    'comments': comments,
    'isVerified': _yesNo(isVerified) ?? _null,
    'status': status?.label ?? _null,
  };

  static String? _yesNo(bool? value) =>
      value == null ? null : (value ? 'yes' : 'no');

  /// How a null is spelled on a form, where every value is text.
  static const _null = 'null';
}

/// What the CPU side decided about a record.
///
/// [label] is the word the service reads; the dropdown shows [action], which
/// is what the reader is about to do rather than what the record becomes.
enum ApprovalStatus {
  approved('Approved', 'Approve'),
  reject('Reject', 'Reject');

  final String label;
  final String action;
  const ApprovalStatus(this.label, this.action);
}
