/// Shared readers for values coming off the wire.
///
/// Responses are read defensively throughout: a missing or differently-typed
/// key yields a default rather than throwing, so a backend rename shows up as
/// a blank cell instead of a crashed page.
library;

/// [value] as an int, or null when it is absent or unparseable.
///
/// Null rather than zero on purpose — a caller that wants to fall back to a
/// computed number cannot tell "the server said 0" from "the server said
/// nothing" if both arrive as 0.
int? asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}');
}

/// [value] as trimmed text, or [fallback] when it is absent or a spreadsheet
/// stand-in for empty.
String asText(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = '$value'.trim();
  // Exports routinely carry these where a cell was blank.
  if (text.isEmpty || text == 'null' || text == 'nan') return fallback;
  return text;
}
