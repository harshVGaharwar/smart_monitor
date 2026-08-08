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

  static const String appName = 'SMART';

  /// Root of the REST API, without a trailing slash.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api',
  );

  /// How long a single request may take before it is abandoned.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Upload ceilings, enforced client-side before bytes leave the browser.
  static const int maxDocumentBytes = 10 * 1024 * 1024; // 10 MB
  static const int maxCaseFileBytes = 25 * 1024 * 1024; // 25 MB
  static const int maxImageBytes = 5 * 1024 * 1024; // 5 MB

  /// Accepted file types per upload surface.
  static const List<String> caseFileExtensions = ['xlsx', 'csv'];
  static const List<String> documentExtensions = ['pdf', 'jpg', 'jpeg', 'png'];
  static const List<String> imageExtensions = ['jpg', 'jpeg', 'png'];
}

/// Paths appended to [AppConstants.apiBaseUrl].
///
/// Kept as a flat list so a backend rename is a one-line change here rather
/// than a search across call sites.
class ApiEndpoints {
  ApiEndpoints._();

  // Auth
  static const String login = '/auth/login';
  static const String logout = '/auth/logout';
  // Cases
  static const String cases = '/cases';

  /// Every stored case, for the dashboard grid.
  static const String smartPointer = '/get-smartpointer';

  /// Parses an uploaded workbook and hands the rows back — it stores nothing.
  static const String uploadCases = '/read-excel';

  /// Writes the rows the user approved. The write side of [smartPointer].
  static const String upddateCase = '/update-smartpointer';
  static String caseById(int id) => '/cases/$id';
  
  static String caseMessages(int id) => '/cases/$id/messages';
  static String caseDocuments(int id) => '/cases/$id/documents';
  static String verifyCase(int id) => '/cases/$id/verify';
  static String reassignCase(int id) => '/cases/$id/reassign';

  // MIS register
  static const String misReports = '/mis-reports';
  static const String misSubmit = '/mis-reports/submit';

  // Reference data for the reassign dialog
  static const String cpus = '/reference/cpus';
  static const String teams = '/reference/teams';
}
