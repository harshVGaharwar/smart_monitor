/// One case row, shaped the way the UAT API writes it.
///
/// Both read endpoints answer with `data: {"rows": [...]}` where each row has
/// these keys, in this order. Shaping happens here, at the edge, rather than in
/// the parser or the repository: internally a value is just text, and it is
/// only the wire format that cares that `sr_no` is a number or that a blank
/// cell is null rather than `""`.
///
/// Accepts a row as the parser produces it or as the repository stores it —
/// including the older `facility_sr_no` spelling, so a stored database written
/// before this shape existed still reads.
Map<String, dynamic> smartRow(Map<String, dynamic> row) {
  final status = _text(row['status']);
  final importedAt = _text(row['imported_at']);

  return <String, dynamic>{
    'client_id': _nullable(row['client_id']),
    'customer_name': _nullable(row['customer_name']),
    'account_no': _nullable(row['account_no']),
    'line_no': _nullable(row['line_no']),
    'health_check_category': _nullable(row['health_check_category']),
    'sub_category': _nullable(row['sub_category']),
    'support_system': _nullable(row['support_system']),
    'core_system': _nullable(row['core_system']),
    'exception_category': _nullable(row['exception_category']),
    'reason': _nullable(row['reason']),
    'cpu': _nullable(row['cpu']),
    'team': _nullable(row['team']),
    'segment': _nullable(row['segment']),
    'facility': _nullable(row['facility']),
    // A number on the wire, and 0 rather than null when the file did not
    // number the facility — which is what UAT sends.
    'sr_no': _number(row['sr_no'] ?? row['facility_sr_no']),
    'maker': _nullable(row['maker']),
    'checker': _nullable(row['checker']),
    'ls_srm_date': _date(row['ls_srm_date']),
    // Only stored cases have these two — an upload response carries neither,
    // exactly as UAT's read-excel does not.
    if (status.isNotEmpty) 'status': status,
    if (importedAt.isNotEmpty) 'imported_at': importedAt,
  };
}

/// What the service sends where a date was never set.
const minDate = '0001-01-01';

/// [value] as text, or null when it is blank — UAT sends null, not `""`, for
/// a column the file left empty.
Object? _nullable(Object? value) {
  final text = _text(value);
  return text.isEmpty ? null : text;
}

/// [value] as a date-only string.
///
/// A stored date can carry a time — the client writes one back as a full
/// ISO-8601 stamp — and the service sends `yyyy-MM-dd`, so the time is cut off
/// here rather than left for the client to ignore. Text that is not a date
/// (a spreadsheet's `21-07-2026`, say) is passed through as the file wrote it,
/// which is the rule for every other cell.
String _date(Object? value) {
  final text = _text(value);
  // .NET's DateTime.MinValue, which is how the service writes "no date". The
  // client maps it back to null rather than showing year 1.
  if (text.isEmpty) return minDate;

  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  return '${parsed.year.toString().padLeft(4, '0')}-$month-$day';
}

/// [value] as an integer, [unnumbered] when it is absent or not a number.
///
/// The parser hands over whatever the cell held, so a spreadsheet reader's
/// `3.0` for a cell showing 3 has to come back as 3 rather than as text.
int _number(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return num.tryParse(_text(value))?.toInt() ?? unnumbered;
}

/// What the service sends where a row carries no facility serial number.
/// Serial numbers start at 1, so the client reads this back as blank.
const unnumbered = 0;

String _text(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = '$value'.trim();
  // Exports routinely carry these where a cell was blank.
  if (text.isEmpty || text == 'null' || text == 'nan') return fallback;
  return text;
}
