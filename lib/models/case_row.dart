import '../data/mock_data.dart';
import 'case_item.dart';
import 'pending_case.dart';

/// One case row exactly as the service writes it.
///
/// A wire model: one field per JSON key, in the order the response lists them,
/// every value a string. It is deliberately dumb — it says what arrived and
/// nothing about what it means. [toCaseItem] is where the reading happens, so
/// there is one place that decides what `"0"` or `0001-01-01` stand for.
///
/// Both read endpoints return this shape, so it serves the dashboard and the
/// upload alike; `status` and [importedAt] are the two only a stored case has.
///
/// Values are read through [_text] rather than cast, so a null or a missing key
/// yields a blank cell rather than throwing — one odd row must not take the
/// whole grid down.
class CaseRow {
  final String clientId;
  final String customerName;
  final String accountNo;
  final String lineNo;
  final String healthCheckCategory;
  final String subCategory;
  final String supportSystem;
  final String coreSystem;
  final String exceptionCategory;
  final String reason;
  final String cpu;
  final String team;

  /// Null where the file left the column empty — which is what the service
  /// sends, rather than `""`.
  final String? segment;
  final String? facility;

  /// The facility's serial number. A number on the wire, 0 where the row was
  /// never numbered; a server writing it as text still reads.
  final int? srNo;

  final String maker;
  final String checker;

  /// `0001-01-01` where no date was ever set — .NET's `DateTime.MinValue`.
  final String? lsSrmDate;

  /// Where the case sits in the review workflow. Only a stored case has one,
  /// so it is blank on an upload response.
  final String status;

  /// When the case was last written to the store. Stored cases only, and the
  /// one date the dashboard grid can sort a row by.
  final String? importedAt;

  /// The service's own reference for the case, when it states one. It does not
  /// on the read endpoints — a case is identified by client id / account no /
  /// line no — so [toCaseItem] falls back to that triple.
  final String? exceptionCode;

  const CaseRow({
    required this.clientId,
    required this.customerName,
    required this.accountNo,
    required this.lineNo,
    required this.healthCheckCategory,
    required this.subCategory,
    required this.supportSystem,
    required this.coreSystem,
    required this.exceptionCategory,
    required this.reason,
    required this.cpu,
    required this.team,
    this.segment,
    this.facility,
    this.srNo,
    required this.maker,
    required this.checker,
    this.lsSrmDate,
    this.status = '',
    this.importedAt,
    this.exceptionCode,
  });

  factory CaseRow.fromJson(Map<String, dynamic> json) {
    return CaseRow(
      clientId: _text(json['client_id']),
      customerName: _text(json['customer_name']),
      accountNo: _text(json['account_no']),
      lineNo: _text(json['line_no']),
      // The older spellings are still read, so a response from a server that
      // has not been updated still fills the row.
      healthCheckCategory: _text(
        json['health_check_category'] ?? json['health_check'],
      ),
      subCategory: _text(json['sub_category']),
      supportSystem: _text(json['support_system']),
      coreSystem: _text(json['core_system']),
      exceptionCategory: _text(json['exception_category']),
      reason: _text(json['reason']),
      cpu: _text(json['cpu'] ?? json['unit']),
      team: _text(json['team'] ?? json['actionable_team']),
      segment: _nullable(json['segment']),
      facility: _nullable(json['facility']),
      srNo: _number(
        json['sr_no'] ?? json['facility_sr_no'] ?? json['facility_smo'],
      ),
      maker: _text(json['maker']),
      checker: _text(json['checker']),
      lsSrmDate: _nullable(json['ls_srm_date'] ?? json['lsrm_date']),
      status: _text(json['status']),
      importedAt: _nullable(json['imported_at'] ?? json['updated_at']),
      exceptionCode: _nullable(json['exception_code'] ?? json['id']),
    );
  }

  /// The row as the write endpoint expects it back.
  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'customer_name': customerName,
    'account_no': accountNo,
    'line_no': lineNo,
    'health_check_category': healthCheckCategory,
    'sub_category': subCategory,
    'support_system': supportSystem,
    'core_system': coreSystem,
    'exception_category': exceptionCategory,
    'reason': reason,
    'cpu': cpu,
    'team': team,
    'segment': segment ?? '',
    'facility': facility ?? '',
    'sr_no': srNo ?? 0,
    'maker': maker,
    'checker': checker,
    'ls_srm_date': lsSrmDate ?? '',
    'status': status,
  };

  /// The row read into the model the screens work in.
  ///
  /// Everything the wire leaves implicit is resolved here, and only here:
  /// the workflow status onto its enum, the two stand-ins the service uses for
  /// "unset" onto null, and the reference the UI identifies a case by.
  CaseItem toCaseItem() {
    return CaseItem(
      // The read endpoints return no id — a case is identified by client id /
      // account no / line no — so that triple is the reference the detail
      // header shows and the dashboard matches an edited row against.
      exceptionCode:
          exceptionCode ??
          [clientId, accountNo, lineNo].where((p) => p.isNotEmpty).join('-'),
      clientId: clientId,
      customerName: customerName,
      accountNo: accountNo,
      lineNo: lineNo,
      healthCheckCategory:
          healthCheckCategory.isEmpty ? 'FD Exceptions' : healthCheckCategory,
      subCategory: subCategory,
      supportSystem: supportSystem,
      coreSystem: coreSystem,
      exceptionCategory:
          exceptionCategory.isEmpty ? 'Exception' : exceptionCategory,
      reason: reason,
      segment: segment ?? '',
      facility: facility ?? '',
      srNo: _serial(srNo),
      maker: maker,
      checker: checker,
      lsrmDate: _date(lsSrmDate),
      cpu: cpu,
      team: team,
      status: CaseItem.statusFrom(status),
      updatedAt: _date(importedAt),
    );
  }

  /// The row read into the editable model the upload screen works in.
  ///
  /// [sequence] is the row's 1-based position in the file, and the only source
  /// of the ID column: the response carries no id, since a case is identified
  /// by client id / account no / line no everywhere it matters.
  ///
  /// Validity is resolved here rather than trusted from the response. The
  /// results table lets the user correct a CPU / team / category cell, and each
  /// edit has to move the row between "ready" and "needs attention" without
  /// another round trip — so the master-data lookup is the client's, and a
  /// value it does not recognise is kept as the file wrote it, for the table to
  /// show back.
  PendingCase toPendingCase({required int sequence}) {
    return PendingCase(
      id: sequence,
      clientId: clientId,
      customerName: customerName,
      accountNo: accountNo,
      lineNo: lineNo,
      subCategory: subCategory,
      supportSystem: supportSystem,
      coreSystem: coreSystem,
      segment: segment ?? '',
      facility: facility ?? '',
      srNo: _serial(srNo),
      maker: maker,
      checker: checker,
      lsSrmDate: lsSrmDate ?? '',
      healthCheckCategory:
          PendingCase.matchOption(
            healthCheckCategory,
            MockData.healthCheckCategories,
          ) ??
          healthCheckCategory,
      healthCheckCategoryRaw: healthCheckCategory,
      exceptionCategory:
          PendingCase.matchOption(
            exceptionCategory,
            MockData.exceptionCategories,
          ) ??
          exceptionCategory,
      exceptionCategoryRaw: exceptionCategory,
      reason: reason,
      cpu: PendingCase.matchOption(cpu, MockData.cpus),
      cpuRaw: cpu,
      team: PendingCase.matchOption(team, MockData.teams),
      teamRaw: team,
    );
  }

  /// [value] as trimmed text, or [fallback] when it is absent or one of the
  /// stand-ins an export writes where a cell was blank.
  static String _text(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null' || text == 'nan') return fallback;
    return text;
  }

  /// The same, but keeping the service's null where a column was empty.
  static String? _nullable(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  /// [value] as a serial number, or null when the column is empty.
  ///
  /// A number arrives as one, but the same field written as text still reads —
  /// this server sent `"0"` for a while, and a spreadsheet reader will hand
  /// over `3.0` for a cell showing 3.
  static int? _number(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = _text(value);
    return text.isEmpty ? null : num.tryParse(text)?.toInt();
  }

  /// A serial number as text, with the service's stand-in for "unset" read as
  /// blank — serial numbers start at 1, so a literal 0 would put a meaningless
  /// value in the column.
  static String _serial(int? value) =>
      value == null || value == 0 ? '' : '$value';

  /// [value] as a date, or null when it is absent or unparseable.
  ///
  /// `0001-01-01` reads as null: the service is .NET-backed and writes
  /// `DateTime.MinValue` where a date was never set, so taking it literally
  /// would put the year 1 in front of the user instead of a blank cell.
  static DateTime? _date(String? value) {
    if (value == null) return null;
    final date = DateTime.tryParse(value);
    if (date == null || date.year <= 1) return null;
    return date;
  }
}
