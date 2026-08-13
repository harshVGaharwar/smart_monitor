/// One comment, shaped the way the client reads it.
///
/// Shaping happens here, at the edge, for the same reason `smartRow` does it:
/// the table stores snake_case text and the wire speaks the camelCase the
/// request body arrived in. Both comment endpoints answer with this shape, so
/// one mapping on the client serves the read and the write.
///
/// The row's own `id` is deliberately not carried. It is the table's key, not
/// the comment's identity on the wire: nothing addresses a note by it — there
/// is no endpoint to edit or delete one — and a thread is read whole by client
/// id. Sending it would publish a storage detail the client has no use for.
Map<String, dynamic> commentRow(Map<String, dynamic> row) => <String, dynamic>{
      'clientId': _text(row['client_id']),
      'userId': _text(row['user_id']),
      'role': _text(row['role']),
      'comments': _text(row['comments']),
      // The filename the note went up with, empty when it went up on its own.
      'supportDocument': _text(row['support_document']),
      // Why the record was routed on. Only a reassignment carries one.
      'reason': _text(row['reason']),
      'createdAt': _text(row['created_at']),
    };

String _text(Object? value) => value == null ? '' : '$value';
