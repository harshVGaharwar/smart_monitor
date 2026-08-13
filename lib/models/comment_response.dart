import 'api_envelope.dart';
import 'case_item.dart';

/// One comment as the service stores it.
///
/// Both comment endpoints answer with this shape — `/getComments` as a list
/// under `data.comments`, `/addComment` as the single one it just wrote under
/// `data.comment` — so the read and the write are mapped once.
///
/// Read defensively, the same rule the case models follow: a missing key
/// yields a default rather than throwing.
class RemoteComment {
  final String clientId;

  /// Who wrote it, as an employee code.
  final String userId;

  /// The template they wrote it under — `Maker`, `Checker`.
  final String role;

  /// The note.
  final String comments;

  /// The filename the note went up with, empty when it went up on its own.
  /// The name only — the bytes live wherever the service put them.
  final String supportDocument;

  /// Why the record was routed on, when the note came with a reassignment.
  /// Empty on every other comment.
  final String reason;

  /// When the server stored it. Null when the stamp was missing or unreadable,
  /// which is why the thread falls back to the order it arrived in.
  final DateTime? createdAt;

  const RemoteComment({
    this.clientId = '',
    this.userId = '',
    this.role = '',
    this.comments = '',
    this.supportDocument = '',
    this.reason = '',
    this.createdAt,
  });

  factory RemoteComment.fromJson(Map<String, dynamic> json) => RemoteComment(
    clientId: '${json['clientId'] ?? ''}',
    userId: '${json['userId'] ?? ''}',
    role: '${json['role'] ?? ''}',
    comments: '${json['comments'] ?? ''}',
    supportDocument: '${json['supportDocument'] ?? ''}',
    reason: '${json['reason'] ?? ''}',
    createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}')?.toLocal(),
  );

  /// Who the thread shows as the author.
  ///
  /// The template, because that is what the reader on the other side needs to
  /// know — a note from the CPU side reads differently from one from the
  /// health check. The employee code stands in when the comment carries no
  /// template, so an author line is never blank.
  String get author => role.isEmpty ? userId : role;

  /// The comment in the shape the panel draws, which brings the avatar colour
  /// and initials with it.
  CaseComment toCaseComment() => CaseComment(
    author: author,
    reason: reason,
    text: comments,
    at: createdAt ?? DateTime.now(),
  );
}

/// The body of `GET /getComments` — the thread, oldest first.
class CommentsResponse {
  final String? message;

  /// Why the read failed, or null when it worked. Set from the envelope, which
  /// can report a failure on a 200.
  final String? failure;

  final List<RemoteComment> comments;

  const CommentsResponse({
    this.message,
    this.failure,
    this.comments = const [],
  });

  factory CommentsResponse.fromBody(Object? body) {
    final envelope = ApiEnvelope(body);
    return CommentsResponse(
      message: envelope.message,
      failure: envelope.failure,
      comments: _listFrom(envelope.data, 'comments'),
    );
  }

  bool get isSuccess => failure == null;
}

/// The body of `POST /addComment` — the comment as it was stored.
///
/// [comment] is null when the server acknowledged the write without echoing
/// it. That is not a failure: the note landed, and the thread is re-read after
/// a post anyway.
class AddCommentResponse {
  final String? message;
  final String? failure;
  final RemoteComment? comment;

  const AddCommentResponse({this.message, this.failure, this.comment});

  factory AddCommentResponse.fromBody(Object? body) {
    final envelope = ApiEnvelope(body);
    final data = envelope.data;
    final single = data is Map ? data['comment'] : null;

    return AddCommentResponse(
      message: envelope.message,
      failure: envelope.failure,
      comment:
          single is Map<String, dynamic>
              ? RemoteComment.fromJson(single)
              // Some servers echo the whole thread instead; the last of it is
              // the one just written.
              : _listFrom(data, 'comments').lastOrNull,
    );
  }

  bool get isSuccess => failure == null;
}

/// The comments under [key] of [data], however the payload wrapped them.
List<RemoteComment> _listFrom(Object? data, String key) {
  final raw = data is List ? data : (data is Map ? data[key] : null);
  return [
    if (raw is List)
      for (final item in raw)
        if (item is Map<String, dynamic>) RemoteComment.fromJson(item),
  ];
}
