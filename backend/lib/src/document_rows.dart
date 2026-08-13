/// One attached document, shaped the way the client reads it.
///
/// Shaping happens here, at the edge, for the same reason `commentRow` does it:
/// the table stores snake_case text and the wire speaks camelCase.
///
/// A document is not a row of its own — it arrives attached to a note or a
/// reassignment, and the thread row is where its name lives. So the two ids
/// here are that note's: `userID` is the employee code of whoever posted it,
/// and `uploadedBy` is the template they posted it under, which is the same
/// pair the comment thread shows above every note.
Map<String, dynamic> documentRow(Map<String, dynamic> row) =>
    <String, dynamic>{
      'clientId': _text(row['client_id']),
      'userID': _text(row['user_id']),
      'fileName': _text(row['support_document']),
      // The template, falling back to the code — an uploader line is never
      // blank, the rule `RemoteComment.author` reads by on the client.
      'uploadedBy': _text(row['role'], fallback: _text(row['user_id'])),
      'uploadedDate': _text(row['created_at']),
    };

String _text(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = '$value'.trim();
  return text.isEmpty ? fallback : text;
}
