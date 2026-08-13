import 'dart:typed_data';

/// The body of `POST /addComment` — one note on a case's thread.
///
/// The key casing is the service's, as in [LoginRequest]: `clientId`, `userId`
/// and a plural `comments` for what is one comment.
///
/// Goes up as JSON, or as multipart when [supportDocument] is set — the file
/// cannot ride in a JSON body, and [toFields] is the same four values as
/// [toJson] with everything stringified for the form.
class AddCommentRequest {
  /// Which case the note belongs to.
  final String clientId;

  /// Who is writing it — the signed-in user's employee code, the same identity
  /// their queue is read with.
  final String userId;

  /// The note itself.
  final String comments;

  /// Which side of the handover they were on when they wrote it. Stored with
  /// the comment rather than looked up later: a user's template can change,
  /// and the thread is a record of what was said at the time.
  final String role;

  /// The evidence behind the note, or null when there is none.
  ///
  /// One file, not a list: the key is singular on the wire, and a note that
  /// needs two documents is two things worth saying separately.
  final CommentAttachment? supportDocument;

  const AddCommentRequest({
    required this.clientId,
    required this.userId,
    required this.comments,
    required this.role,
    this.supportDocument,
  });

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'userId': userId,
    'comments': comments,
    'role': role,
  };

  /// The same values as form fields, for the multipart the file rides in.
  Map<String, String> toFields() => {
    'clientId': clientId,
    'userId': userId,
    'comments': comments,
    'role': role,
  };
}

/// A file attached to a comment, held in memory.
///
/// Bytes rather than a path: on the web there is no file system to point the
/// upload at, which is the same reason `ApiClient.uploadBytes` takes them.
class CommentAttachment {
  final String filename;
  final Uint8List bytes;

  const CommentAttachment({required this.filename, required this.bytes});
}
