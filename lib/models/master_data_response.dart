import 'api_envelope.dart';

/// The body of `GET /getMasterData` — the reference lists every screen works
/// against.
///
/// Five lists in one response, because they are read together: the reassign
/// panel needs CPUs, teams and reasons at once, and the upload screen
/// validates against all three category sets in the same pass. Five calls
/// would mean four empty dropdowns while the fifth was still in flight.
///
/// Plain strings rather than `{code, name}` pairs, because a stored case names
/// its CPU and team by the name — see `CaseRow.toPendingCase`, which resolves
/// an uploaded value onto one of these and writes the canonical spelling back.
/// An id alongside would be a second identity for something already keyed by
/// name.
///
/// Every list defaults to empty and a missing key yields empty rather than
/// throwing, the rule every model here follows. What an empty list *means* is
/// the caller's to decide — see `MasterData.isLoaded`.
class MasterDataResponse {
  final String? message;

  /// Why the read failed, or null when it worked. Set from the envelope, which
  /// can report a failure on a 200.
  final String? failure;

  /// Processing units a case can be reassigned to, and what an uploaded CPU is
  /// checked against.
  final List<String> cpus;

  /// Destination teams offered in the reassign dialog, and what an uploaded
  /// team is checked against.
  final List<String> teams;

  final List<String> exceptionCategories;
  final List<String> healthCheckCategories;

  /// Offered in the detail panel's Reassign tab.
  final List<String> reassignReasons;

  const MasterDataResponse({
    this.message,
    this.failure,
    this.cpus = const [],
    this.teams = const [],
    this.exceptionCategories = const [],
    this.healthCheckCategories = const [],
    this.reassignReasons = const [],
  });

  factory MasterDataResponse.fromBody(Object? body) {
    final envelope = ApiEnvelope(body);
    final data = envelope.data;

    return MasterDataResponse(
      message: envelope.message,
      failure: envelope.failure,
      cpus: _strings(data, 'cpus'),
      teams: _strings(data, 'teams'),
      exceptionCategories: _strings(data, 'exceptionCategories'),
      healthCheckCategories: _strings(data, 'healthCheckCategories'),
      reassignReasons: _strings(data, 'reassignReasons'),
    );
  }

  bool get isSuccess => failure == null;

  /// True when the response carried nothing at all.
  ///
  /// A success answering with five empty lists is not a working call: every
  /// dropdown would be empty and every uploaded row flagged. It reads as an
  /// outage because that is what it is.
  bool get isEmpty =>
      cpus.isEmpty &&
      teams.isEmpty &&
      exceptionCategories.isEmpty &&
      healthCheckCategories.isEmpty &&
      reassignReasons.isEmpty;
}

/// The strings under [key] of [data].
///
/// Blanks are dropped rather than carried: a null or an empty cell in a master
/// list is a hole in the data, and an empty entry in a dropdown is something a
/// user can pick by accident.
List<String> _strings(Object? data, String key) {
  final raw = data is Map ? data[key] : null;
  return [
    if (raw is List)
      for (final item in raw)
        if (item != null && '$item'.trim().isNotEmpty) '$item'.trim(),
  ];
}
