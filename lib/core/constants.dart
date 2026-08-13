/// App-wide configuration and fixed values.
///
/// Anything environment-specific comes from `--dart-define` so the same build
/// artefact can point at different backends:
///
/// ```
/// flutter run -d chrome --dart-define=API_BASE_URL=https://smart.uat.internal/api
/// ```
class AppConstants {
  AppConstants._();

  /// Root of the REST API, without a trailing slash.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api',
  );

  /// How long a single request may take before it is abandoned.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Ceiling on a supporting document, enforced client-side before the bytes
  /// leave the browser.
  ///
  /// The case-file upload keeps its own ceiling and its own list of types, in
  /// `UploadCasesView` — that screen accepts a wider set on a drop than it
  /// offers in the picker, which is a distinction only it makes.
  static const int maxDocumentBytes = 10 * 1024 * 1024; // 10 MB

  /// File types a supporting document may be.
  static const List<String> documentExtensions = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'xlsx',
    'xls',
  ];
}

/// Paths appended to [AppConstants.apiBaseUrl].
///
/// Kept as a flat list so a backend rename is a one-line change here rather
/// than a search across call sites.
class ApiEndpoints {
  ApiEndpoints._();

  // Auth
  /// Signs in and hands back the session and this user's menu permissions.
  static const String login = '/login';

  // Cases
  /// Every stored case, for the dashboard grid.
  static const String smartPointer = '/get-smartpointer';

  /// Parses an uploaded workbook and hands the rows back — it stores nothing.
  static const String uploadCases = '/read-excel';

  /// Writes the rows the user approved. The write side of [smartPointer].
  static const String upddateCase = '/update-smartpointer';

  /// Signs one record off. Takes the record's client id and who is verifying
  /// it — not the case, which the server already holds.
  static const String verify = '/verify';

  /// Routes one record to another CPU and team, back to the CPU side.
  static const String reassign = '/reassign';

  // Comments
  /// One case's discussion thread, read before it is added to.
  static const String getComments = '/getComments';

  /// Adds one comment to that thread. The write side of [getComments].
  static const String addComment = '/addComment';

  // Documents
  /// The files attached to one case. Read by everyone — whichever side
  /// attached a file, the other side has to be able to see it.
  static const String getDocuments = '/getDocuments';

  // Master data
  /// The reference lists every screen validates and its dropdowns against —
  /// CPUs, teams, and the three category sets. One call for all of them.
  static const String masterData = '/getMasterData';
}
