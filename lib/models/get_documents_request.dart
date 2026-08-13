/// The query of `GET /getDocuments` — whose case, read by whom.
///
/// [clientId] picks the case. [userId] is the caller, sent so the read is
/// attributable; it does not narrow the answer. Documents are nobody's in
/// particular: whichever side attached one, the other side has to be able to
/// open it, so this call is not gated on a template the way the verify is.
///
/// The key casing is the service's, as in [GetCommentsRequest] — mirrored
/// rather than tidied, because the server matches on it. Note that this
/// endpoint spells the caller `userID` where the comment thread spells it
/// `userId`; that inconsistency is the service's, and copying it is what makes
/// the call work.
class GetDocumentsRequest {
  final String clientId;
  final String userId;

  const GetDocumentsRequest({required this.clientId, required this.userId});

  /// The query string. Not `toJson` — these ride on the URL.
  Map<String, dynamic> toQuery() => {'clientId': clientId, 'userID': userId};
}
