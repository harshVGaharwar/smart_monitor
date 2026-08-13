import 'api_envelope.dart';

/// The body of `POST /reassign` — what the service says about the move.
///
/// A sentence rather than a count: the panel shows it as it arrived, so a
/// service that changes its wording changes the toast without a rebuild.
class ReassignResponse {
  /// What the service said — `Successfully assigned to new user`.
  final String? message;

  /// Why the reassignment failed, or null when it worked. Set from the
  /// envelope, which can report a failure on a 200.
  final String? failure;

  /// How many rows the service moved, when it said. Null when it reported
  /// nothing, which is not a failure — the message is the answer here.
  final int? movedCount;

  const ReassignResponse({this.message, this.failure, this.movedCount});

  factory ReassignResponse.fromBody(Object? body) {
    final envelope = ApiEnvelope(body);
    final data = envelope.data;

    return ReassignResponse(
      message: envelope.message,
      failure: envelope.failure,
      movedCount: data is num ? data.toInt() : int.tryParse('${data ?? ''}'),
    );
  }

  bool get isSuccess => failure == null;

  /// The message, or a sentence of this app's own when the service sent none —
  /// the panel toasts this, and an empty toast reads as nothing having
  /// happened.
  String get toastText {
    final text = message?.trim() ?? '';
    return text.isEmpty ? 'Successfully assigned to new user' : text;
  }
}
