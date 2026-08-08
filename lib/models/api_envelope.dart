/// The wrapper every endpoint answers with, read into something typed.
///
/// The service sends the same envelope for all three calls — `code`,
/// `message`, `success`, `data`, `count`, and session fields this app does not
/// use — and the payload a caller wants is always under `data`.
///
/// Reading it is a model's job rather than a bag of loose functions: the rules
/// for what counts as a failure, and where the rows sit, belong in one place
/// that the response models compose.
class ApiEnvelope {
  /// The decoded body exactly as it arrived, envelope or not.
  final Object? body;

  const ApiEnvelope(this.body);

  /// True when [body] is an envelope rather than a bare payload.
  ///
  /// Both keys are required: `data` alone is a common enough field name that a
  /// payload could carry it innocently.
  bool get isEnvelope =>
      body is Map &&
      (body! as Map).containsKey('data') &&
      (body! as Map).containsKey('success');

  /// The payload. A body that is not an envelope is its own payload, so a
  /// plain `{"rows": [...]}` from an older build of the server still reads.
  Object? get data => isEnvelope ? (body! as Map)['data'] : body;

  /// What the envelope said, or null when it carries no message.
  String? get message {
    if (body is! Map) return null;
    final text = _text((body! as Map)['message']);
    return text.isEmpty ? null : text;
  }

  /// Why the call failed, or null when it succeeded.
  ///
  /// A failure can arrive with a 200 — the envelope reports it in `success`
  /// and `code`, not in the status line — so this, not the HTTP status, is
  /// what decides whether a response is usable.
  String? get failure {
    // Anything that is not JSON structure never came from this API — a
    // gateway's error page, a proxy's plain text, an empty body. Reported as a
    // failure rather than read as zero rows, which would put an empty grid in
    // front of the user with nothing to say why.
    if (body is String) {
      final text = _text(body);
      return text.isEmpty ? 'The server sent an empty response.' : text;
    }
    if (body == null) return 'The server sent an empty response.';
    if (body is! Map) return null;

    // An explicit `success` is the authority. `code` only decides when the
    // response omits `success` — a gateway that answers `success: true` with
    // an HTTP-style code of 200 is reporting success, not failure, and reading
    // the code alone would throw away a perfectly good payload.
    final success = (body! as Map)['success'];
    final failed = success is bool
        ? !success
        : (_int((body! as Map)['code']) ?? 0) != 0;
    if (!failed) return null;
    return message ?? 'The server rejected the request.';
  }

  /// True when the call worked, whatever it returned.
  bool get isSuccess => failure == null;

  /// The rows in the payload, however it wrapped them.
  ///
  /// Reads `data.rows` — the current contract — and still accepts a bare array
  /// or a `data` / `items` key, so the app works against a server that has not
  /// been updated as well as the live one.
  List<Map<String, dynamic>> get rows {
    final payload = data;
    final raw = payload is List
        ? payload
        : (payload is Map
              ? payload['rows'] ?? payload['data'] ?? payload['items']
              : null);

    return [
      if (raw is List)
        for (final item in raw)
          if (item is Map<String, dynamic>) item,
    ];
  }

  /// The row count the server reported, falling back to [parsed].
  ///
  /// `count` is 0 on responses that plainly carry rows — it counts something
  /// else — so it is only read when it says something, and never above what
  /// actually arrived, or the footer would claim records the grid cannot show.
  int countOr(int parsed) {
    if (body is! Map) return parsed;
    final stated = _int((body! as Map)['count']) ?? 0;
    return stated > 0 && stated <= parsed ? stated : parsed;
  }

  /// [value] as an int, or null when it is absent or unparseable.
  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  static String _text(Object? value) {
    if (value == null) return '';
    final text = '$value'.trim();
    return text == 'null' || text == 'nan' ? '' : text;
  }
}
