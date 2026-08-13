import '../data/master_data.dart';

/// A row read from an uploaded cases file.
///
/// Every data row becomes one of these — clean or not — so the validation
/// report can show the whole file. The parsed columns are fixed;
/// [healthCheckCategory], [exceptionCategory], [reason], [cpu] and
/// [team] are edited in the results table, so they are mutable and
/// validity is recomputed on read.
///
/// The `…Raw` fields keep whatever the file actually said. A value the master
/// data does not recognise leaves [cpu] / [team] null, and the table
/// needs the original text to show the user what it rejected. The two category
/// fields keep the rejected text in place instead, since they are plain
/// strings rather than nullable ones.
class PendingCase {
  /// 1-based sequence number over the file's data rows, shown in the ID
  /// column. Assigned at parse time so it survives filtering and the
  /// errors-only export, where a row's position in the list no longer matches
  /// its place in the file.
  final int id;

  final String clientId;
  final String customerName;
  final String accountNo;
  final String lineNo;
  final String subCategory;
  final String supportSystem;
  final String coreSystem;
  final String segment;

  /// The facility the exception sits against, and its serial number within the
  /// account — two columns on the wire (`facility`, `sr_no`). Carried through
  /// rather than shown: the import posts them back, and a row that omitted
  /// them would blank what is stored.
  final String facility;
  final String srNo;
  final String maker;
  final String checker;
  final String lsSrmDate;

  final String cpuRaw;
  final String teamRaw;
  final String exceptionCategoryRaw;
  final String healthCheckCategoryRaw;

  String healthCheckCategory;
  String exceptionCategory;
  String reason;
  String? cpu;
  String? team;

  PendingCase({
    required this.clientId,
    required this.customerName,
    required this.accountNo,
    required this.lineNo,
    required this.subCategory,
    required this.supportSystem,
    required this.coreSystem,
    required this.maker,
    required this.checker,
    // Optional columns: carried through and displayed when the file has them.
    this.segment = '',
    this.facility = '',
    this.srNo = '',
    this.lsSrmDate = '',
    this.id = 0,
    this.healthCheckCategory = '',
    this.exceptionCategory = 'Exception',
    this.reason = '',
    this.cpu,
    this.team,
    String? cpuRaw,
    String? teamRaw,
    String? exceptionCategoryRaw,
    String? healthCheckCategoryRaw,
  }) : cpuRaw = cpuRaw ?? cpu ?? '',
       teamRaw = teamRaw ?? team ?? '',
       exceptionCategoryRaw = exceptionCategoryRaw ?? exceptionCategory,
       healthCheckCategoryRaw = healthCheckCategoryRaw ?? healthCheckCategory;

  /// Resolves a free-text value onto one of [options], ignoring case and
  /// punctuation. Returns null when the value isn't recognised, which sends
  /// the row to the confirmation table.
  static String? matchOption(String value, List<String> options) {
    if (value.trim().isEmpty) return null;
    final key = _normalise(value);
    for (final option in options) {
      if (_normalise(option) == key) return option;
    }
    return null;
  }

  static String _normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  // --- Validation ---------------------------------------------------------
  //
  // Checked live rather than frozen at parse time: correcting a cell in the
  // results table has to move the row into "Ready to Import" straight away.

  bool get cpuValid => cpu != null;
  bool get teamValid => team != null;
  bool get exceptionValid =>
      MasterData.exceptionCategories.contains(exceptionCategory);
  bool get healthCheckValid =>
      MasterData.healthCheckCategories.contains(healthCheckCategory);

  bool get hasErrors =>
      !cpuValid || !teamValid || !exceptionValid || !healthCheckValid;

  /// Field labels that failed validation, for the error export.
  List<String> get errorFields => [
    if (!healthCheckValid) 'Health Check Category',
    if (!cpuValid) 'CPU',
    if (!teamValid) 'Actionable Team',
    if (!exceptionValid) 'Exception Category',
  ];

  /// What the file said for a field, falling back to the resolved value.
  String get cpuDisplay => cpu ?? cpuRaw;
  String get teamDisplay => team ?? teamRaw;

  /// The row as the import endpoint expects it.
  ///
  /// Sends the *resolved* CPU and team rather than the raw text, so a value
  /// the user corrected in the results table is what gets stored — and the
  /// master data's spelling is what lands in the database, not the file's.
  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'customer_name': customerName,
    'account_no': accountNo,
    'line_no': lineNo,
    'health_check_category': healthCheckCategory,
    'sub_category': subCategory,
    'support_system': supportSystem,
    'core_system': coreSystem,
    'segment': segment,
    'facility': facility,
    'sr_no': srNo,
    'maker': maker,
    'checker': checker,
    'ls_srm_date': lsSrmDate,
    'exception_category': exceptionCategory,
    'reason': reason,
    'cpu': cpu ?? '',
    'team': team ?? '',
  };
}

/// Outcome of parsing an uploaded cases file: the data rows still in play.
///
/// Not const-constructible on purpose — [rows] is mutated by [removeRow] when
/// the user drops a row from the report, and a const list would refuse.
class UploadOutcome {
  final List<PendingCase> rows;

  /// How many rows the user has removed since the file was parsed, so the
  /// counts on screen still reconcile with the file they uploaded.
  int _removed = 0;

  UploadOutcome({required this.rows});

  /// Rows that validated cleanly and will be imported on submit.
  List<PendingCase> get valid => [
    for (final r in rows)
      if (!r.hasErrors) r,
  ];

  /// Rows still carrying at least one unrecognised value.
  List<PendingCase> get failed => [
    for (final r in rows)
      if (r.hasErrors) r,
  ];

  int get processed => rows.length;
  int get uploaded => valid.length;
  int get removed => _removed;

  /// Drops a row the user chose not to import — it leaves the report entirely,
  /// so it is neither counted nor submitted. Returns where it sat so [restore]
  /// can put it back, or -1 if it was not in the report.
  int removeRow(PendingCase row) {
    final index = rows.indexOf(row);
    if (index < 0) return -1;
    rows.removeAt(index);
    _removed++;
    return index;
  }

  /// Undo for [removeRow]: returns the row to its original position.
  void restore(int index, PendingCase row) {
    if (index < 0) return;
    rows.insert(index.clamp(0, rows.length), row);
    if (_removed > 0) _removed--;
  }
}
