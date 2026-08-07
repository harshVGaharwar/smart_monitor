import 'json.dart';

/// The body of `POST /cases/import` — what the submit actually persisted.
class ImportCasesResponse {
  /// Cases that were not stored before.
  final int inserted;

  /// Cases that already existed under the same client / account / line and
  /// were overwritten by this submit.
  final int updated;

  /// Everything written, however it landed.
  final int total;

  ImportCasesResponse({
    required this.inserted,
    required this.updated,
    int? total,
  }) : total = total ?? inserted + updated;

  /// Reads the response body.
  ///
  /// [sentCount] is what the client posted, used when the server reports
  /// nothing: the rows were still written, so claiming zero would be worse
  /// than trusting what went out.
  factory ImportCasesResponse.fromJson(Object? body, {required int sentCount}) {
    if (body is! Map) {
      return ImportCasesResponse(inserted: sentCount, updated: 0);
    }
    return ImportCasesResponse(
      inserted: asInt(body['inserted']) ?? 0,
      updated: asInt(body['updated']) ?? 0,
      // Absent rather than zero, so a server reporting only the split still
      // gets a total summed from it instead of one claiming nothing landed.
      total: asInt(body['total']),
    );
  }

  /// True when the submit overwrote cases as well as adding them — the case
  /// worth calling out, since a re-upload silently replacing records is the
  /// surprising outcome.
  bool get hasUpdates => updated > 0;

  /// One line describing the outcome, as the upload screen reports it.
  String summary({int unresolved = 0}) => [
    '$total case(s) imported',
    if (hasUpdates) '$updated updated',
    if (unresolved > 0) '$unresolved left unresolved',
  ].join(' · ');
}
