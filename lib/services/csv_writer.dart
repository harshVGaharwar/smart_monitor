
/// Minimal RFC 4180 CSV writer.
///
/// Hand-rolled rather than pulled from a package because the app only ever
/// writes CSV — the reading side is the server's job — and the published csv
/// packages that expose a writer either require a much newer Dart SDK than the
/// build machines run, or change their API between majors. Ten lines of
/// quoting is cheaper than that constraint.
class CsvWriter {
  CsvWriter._();

  /// Encodes [rows] with CRLF line endings, which is what Excel expects.
  static String encode(List<List<String>> rows, {String eol = '\r\n'}) {
    return rows.map((row) => row.map(_field).join(',')).join(eol);
  }

  /// Quotes a field only when it needs it, doubling any embedded quotes.
  static String _field(String value) {
    final needsQuotes =
        value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}
