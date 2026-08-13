import '../models/master_data_response.dart';

/// The reference lists the app validates and fills its dropdowns from, as the
/// server last sent them.
///
/// Static and mutable, which is unusual here and deliberate. The lists are read
/// synchronously from inside pure model code — `PendingCase.exceptionValid` and
/// `CaseRow.toPendingCase` are not async and take no masters argument — and
/// validity is re-read on every keystroke in the results table, so correcting a
/// cell moves the row between "ready" and "needs attention" without a round
/// trip. Threading a masters object down to those would mean passing it through
/// every construction site of a case for no gain.
///
/// Filled once per session by `DashboardPage`, which is the shell both the grid
/// and the upload screen render inside. Nothing else writes to it.
class MasterData {
  MasterData._();

  static List<String> cpus = const [];
  static List<String> teams = const [];
  static List<String> exceptionCategories = const [];
  static List<String> healthCheckCategories = const [];
  static List<String> reassignReasons = const [];

  /// Whether a fetch has landed.
  ///
  /// Worth keeping apart from "the lists are empty": before the first call
  /// there is nothing to say, and after a failed one there is — the caller
  /// shows a warning for the second and not the first. It stays false when the
  /// call worked but carried nothing, because five empty lists are an outage
  /// wearing a 200.
  static bool isLoaded = false;

  /// Takes the lists from [response].
  ///
  /// A response carrying nothing is not applied: it would replace whatever is
  /// already loaded with emptiness, so a failed refresh would blank dropdowns
  /// that were working a second ago.
  static void apply(MasterDataResponse response) {
    if (response.isEmpty) return;
    cpus = response.cpus;
    teams = response.teams;
    exceptionCategories = response.exceptionCategories;
    healthCheckCategories = response.healthCheckCategories;
    reassignReasons = response.reassignReasons;
    isLoaded = true;
  }

  /// Empties the cache — for a sign-out, and for tests that need a clean one.
  ///
  /// The next user's master data is fetched fresh rather than inherited: these
  /// lists do not depend on who is signed in today, but nothing about the
  /// contract promises that, and stale reference data is the kind of thing
  /// nobody notices until a row is flagged for no reason.
  static void reset() {
    cpus = const [];
    teams = const [];
    exceptionCategories = const [];
    healthCheckCategories = const [];
    reassignReasons = const [];
    isLoaded = false;
  }
}
