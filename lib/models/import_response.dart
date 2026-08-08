import 'api_envelope.dart';
import 'update_request.dart';

/// The body of `POST /update-smartpointer` — what the submit persisted.
///
/// `data` carries the rows as they were stored, alongside the counts:
/// `{rows, inserted, updated, total}`. A server that only answers with a plain
/// integer — which is what the live service does — is still read, and leaves
/// [rows] empty; [total] is what the screen shows either way.
class UpdatedCasesResponse {
  /// The count the server reported, or null when it reported nothing.
  ///
  /// Null rather than zero on purpose: "the server said 0" and "the server
  /// said nothing" call for different fallbacks, and only one of them means
  /// the submit wrote nothing.
  final int? updatedCount;

  /// What the client posted, used when the server reports no count: the rows
  /// were still written, so claiming zero would be worse than trusting what
  /// went out.
  final int sentCount;

  /// What the envelope said — `Updated Successfully` on a submit that worked.
  final String? message;

  /// Why the submit failed, or null when it succeeded. Set from the envelope's
  /// `success` / `code`, which can report a failure on a 200.
  final String? failure;

  /// The rows as the server stored them, echoed back in the same model the
  /// request was built from. Empty when the server reports only a count.
  final List<UpdateRequestRow> rows;

  const UpdatedCasesResponse({
    required this.sentCount,
    this.updatedCount,
    this.message,
    this.failure,
    this.rows = const [],
  });

  /// Reads the response body.
  ///
  /// [sentCount] is how many rows the client posted. `data` is normally an
  /// object carrying the stored rows and the counts; a plain integer — what a
  /// server that has not been updated returns — is still read, so the app
  /// keeps working against one.
  factory UpdatedCasesResponse.fromJson(
    Object? body, {
    required int sentCount,
  }) {
    final envelope = ApiEnvelope(body);
    final data = envelope.data;

    final int? reported;
    var rows = const <UpdateRequestRow>[];
    if (data is num || data is String) {
      reported = _int(data);
    } else if (data is Map) {
      // Prefer the stated total, then the split summed, so neither spelling
      // reads as "nothing was imported".
      final total = _int(data['total']);
      final inserted = _int(data['inserted']);
      final updated = _int(data['updated']);
      reported =
          total ??
          (inserted == null && updated == null
              ? null
              : (inserted ?? 0) + (updated ?? 0));
      if (data['rows'] is List) {
        rows =
            UpdateRequestModel.fromJson(Map<String, dynamic>.from(data)).rows;
      }
    } else {
      reported = null;
    }

    return UpdatedCasesResponse(
      sentCount: sentCount,
      updatedCount: reported,
      message: envelope.message,
      failure: envelope.failure,
      rows: rows,
    );
  }

  /// [value] as an int, or null when it is absent or unparseable.
  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  /// True when the submit worked.
  bool get isSuccess => failure == null;

  /// True when the server echoed the rows it stored.
  bool get hasRows => rows.isNotEmpty;

  /// Everything the submit wrote, however the server phrased it.
  int get total => updatedCount ?? sentCount;

  /// One line describing the outcome, as the upload screen reports it.
  ///
  /// [unresolved] is what the client left behind in the report — rows that
  /// never went out — so the numbers on screen reconcile with the file.
  String summary({int unresolved = 0}) => [
    '$total case(s) imported',
    if (unresolved > 0) '$unresolved left unresolved',
  ].join(' · ');
}
