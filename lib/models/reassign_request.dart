import 'add_comment_request.dart';

/// The body of `POST /reassign` — routing a record to another CPU and team.
///
/// Not a case: [clientId] says which record, and the rest is the routing and
/// why. The columns the reviewer never touched stay where they are, on the
/// server.
///
/// A reassignment carrying evidence goes up as multipart, the file under
/// [document]; one without stays a plain JSON post.
///
/// The key casing is the service's, as in [VerifyRequest].
class ReassignRequest {
  /// Which record. All the server needs to find the row it holds.
  final String clientId;

  /// Who is routing it — the signed-in user's employee code.
  final String userId;

  /// The template they are routing it under. Not decoration: the server
  /// refuses a reassignment from anyone but the health check side.
  final String role;

  /// Where it is going.
  final String cpu;
  final String team;

  /// Which of the workflow's own answers they picked, kept apart from
  /// [comments] rather than folded into it — one is a chosen value and the
  /// other is prose, and telling them apart later is worth the second field.
  final String reason;

  /// What they had to say about it, in their words. Optional.
  final String comments;

  /// The evidence behind the move, or null when there is none. One file: the
  /// key is singular on the wire.
  final CommentAttachment? document;

  const ReassignRequest({
    required this.clientId,
    required this.userId,
    required this.role,
    required this.cpu,
    required this.team,
    this.reason = '',
    this.comments = '',
    this.document,
  });

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'userId': userId,
    'role': role,
    'cpu': cpu,
    'team': team,
    'reason': reason,
    'comments': comments,
    // The name is all the wire carries here; the bytes ride as the multipart
    // file when there is one.
    'document': document?.filename,
  };

  /// The same values as form fields, for the multipart the file rides in.
  Map<String, String> toFields() => {
    'clientId': clientId,
    'userId': userId,
    'role': role,
    'cpu': cpu,
    'team': team,
    'reason': reason,
    'comments': comments,
  };
}
