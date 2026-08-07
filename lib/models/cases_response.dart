import 'case_item.dart';
import 'json.dart';

/// The body of `GET /get-smartpointer` — the stored cases the dashboard grid
/// shows.
///
/// The rows arrive shaped exactly as the upload endpoint returns them, so the
/// two screens share one row contract; only the mapping target differs, since
/// the dashboard works in [CaseItem] rather than editable upload rows.
class CasesResponse {
  /// The cases, in the order the server listed them.
  final List<CaseItem> cases;

  /// What the server said it holds. Falls back to [cases] when the response
  /// omits it, so callers never have to decide which number to trust.
  final int count;

  const CasesResponse({required this.cases, required this.count});

  /// Reads the response body.
  ///
  /// Accepts a bare array as well as the `rows` / `data` / `items` envelopes,
  /// so a backend that returns the list directly still works.
  factory CasesResponse.fromJson(Object? body) {
    final raw = body is List
        ? body
        : (body is Map
              ? body['rows'] ?? body['data'] ?? body['items'] ?? const []
              : const []);

    final cases = <CaseItem>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        cases.add(CaseItem.fromJson(item));
      }
    }

    return CasesResponse(
      cases: cases,
      count: body is Map ? asInt(body['count']) ?? cases.length : cases.length,
    );
  }

  /// True when the server holds no cases yet — the grid's empty state, which
  /// is not an error.
  bool get isEmpty => cases.isEmpty;
}
