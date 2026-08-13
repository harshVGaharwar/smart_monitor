/// The query of `GET /getComments` — whose thread, read by whom.
///
/// [clientId] picks the thread. [userId] is the caller, sent so the read is
/// attributable; it does not narrow the answer, because the point of a thread
/// is that the other side of the handover reads it.
class GetCommentsRequest {
  final String clientId;
  final String userId;

  const GetCommentsRequest({required this.clientId, required this.userId});

  /// The query string. Not `toJson` — these ride on the URL.
  Map<String, dynamic> toQuery() => {'clientId': clientId, 'userId': userId};
}
