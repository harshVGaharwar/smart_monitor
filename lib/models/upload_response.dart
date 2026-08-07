import 'json.dart';
import 'pending_case.dart';

/// The body of `POST /cases/upload` — the workbook as the server read it.
///
/// Owning the parsing here rather than in the API client keeps one place to
/// look when the contract moves, and lets the upload screen depend on a typed
/// response instead of a decoded map.
class UploadCasesResponse {
  /// Every data row in the file, clean or not, in file order.
  final List<PendingCase> rows;

  /// What the server said it read. Falls back to [rows] when the response
  /// omits it, so callers never have to decide which number to trust.
  final int count;

  const UploadCasesResponse({required this.rows, required this.count});

  /// Reads the response body.
  ///
  /// Accepts a bare array as well as the `rows` / `data` / `items` envelopes,
  /// so a backend that returns the list directly still works.
  factory UploadCasesResponse.fromJson(Object? body) {
    final raw = body is List
        ? body
        : (body is Map
              ? body['rows'] ?? body['data'] ?? body['items'] ?? const []
              : const []);

    final rows = <PendingCase>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        // Sequence backfills the ID column when the server does not number
        // the rows, so it still reads 1, 2, 3 … in the validation report.
        rows.add(PendingCase.fromJson(item, sequence: rows.length + 1));
      }
    }

    return UploadCasesResponse(
      rows: rows,
      count: body is Map ? asInt(body['count']) ?? rows.length : rows.length,
    );
  }

  /// True when the server returned nothing the report could show.
  bool get isEmpty => rows.isEmpty;

  /// The editable review state for these rows.
  ///
  /// A fresh outcome each call: it is mutable, and the screen owns the copy it
  /// is showing.
  UploadOutcome toOutcome() => UploadOutcome(rows: rows);
}
