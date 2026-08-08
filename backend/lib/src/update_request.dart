/// The body of `POST /api/update-smartpointer` — the rows to persist.
///
/// The server side of `lib/models/update_request.dart`: same field names, same
/// JSON keys. Parsing through it rather than passing the raw map on means the
/// endpoint accepts exactly one shape, and the same model shapes the rows it
/// echoes back.
class UpdateRequestModel {
  /// Creates a request carrying [rows].
  UpdateRequestModel({
    required this.rows,
  });

  /// Reads a posted body. A missing or malformed `rows` reads as no rows,
  /// which the endpoint refuses with a message rather than a crash.
  factory UpdateRequestModel.fromJson(Map<String, dynamic> json) {
    return UpdateRequestModel(
      rows: (json['rows'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(UpdateRequestRow.fromJson)
          .toList(),
    );
  }

  /// The cases to write.
  final List<UpdateRequestRow> rows;

  /// The body as it goes on the wire.
  Map<String, dynamic> toJson() {
    return {
      'rows': rows.map((e) => e.toJson()).toList(),
    };
  }
}

/// One case on the wire.
///
/// Every field is a nullable string: the store holds all of them as text, and
/// a null is meaningfully different from a blank — a row that states no status
/// leaves a stored case's status alone.
class UpdateRequestRow {
  /// Creates a row. Every field is optional; [hasIdentity] reports whether the
  /// result can actually be stored.
  UpdateRequestRow({
    this.clientId,
    this.customerName,
    this.accountNo,
    this.lineNo,
    this.healthCheckCategory,
    this.subCategory,
    this.supportSystem,
    this.coreSystem,
    this.exceptionCategory,
    this.reason,
    this.cpu,
    this.team,
    this.segment,
    this.facility,
    this.srNo,
    this.maker,
    this.checker,
    this.lsSrmDate,
    this.status,
  });

  /// Reads a posted row.
  ///
  /// [srNo] and [team] fall back to the spellings this app used before the
  /// UAT service's names were known — the same aliases `CasesRepository` and
  /// `CasesFileParser` accept — so a client that has not been rebuilt keeps
  /// working rather than silently blanking those columns.
  factory UpdateRequestRow.fromJson(Map<String, dynamic> json) {
    return UpdateRequestRow(
      clientId: json['client_id']?.toString(),
      customerName: json['customer_name']?.toString(),
      accountNo: json['account_no']?.toString(),
      lineNo: json['line_no']?.toString(),
      healthCheckCategory: json['health_check_category']?.toString(),
      subCategory: json['sub_category']?.toString(),
      supportSystem: json['support_system']?.toString(),
      coreSystem: json['core_system']?.toString(),
      exceptionCategory: json['exception_category']?.toString(),
      reason: json['reason']?.toString(),
      cpu: json['cpu']?.toString(),
      team: (json['team'] ?? json['actionable_team'])?.toString(),
      segment: json['segment']?.toString(),
      facility: json['facility']?.toString(),
      srNo: (json['sr_no'] ?? json['facility_sr_no'] ?? json['facility_smo'])
          ?.toString(),
      maker: json['maker']?.toString(),
      checker: json['checker']?.toString(),
      lsSrmDate: json['ls_srm_date']?.toString(),
      status: json['status']?.toString(),
    );
  }

  /// The client the case belongs to. Part of the identity triple.
  final String? clientId;

  /// The client's name, as the source system spells it.
  final String? customerName;

  /// The account the exception was raised against. Part of the identity
  /// triple.
  final String? accountNo;

  /// The line within the account. Part of the identity triple.
  final String? lineNo;

  /// The check that raised the case, e.g. `FD Exceptions`.
  final String? healthCheckCategory;

  /// What specifically failed.
  final String? subCategory;

  /// The system the supporting record sits in.
  final String? supportSystem;

  /// The system the core record sits in.
  final String? coreSystem;

  /// Whether the case is an exception or a deviation.
  final String? exceptionCategory;

  /// The free text explaining the case.
  final String? reason;

  /// The processing unit the case is assigned to.
  final String? cpu;

  /// The team expected to act on it.
  final String? team;

  /// The business segment the client falls under.
  final String? segment;

  /// The facility the exception sits against.
  final String? facility;

  /// The facility's serial number within the account.
  final String? srNo;

  /// Who raised the underlying record.
  final String? maker;

  /// Who checked it.
  final String? checker;

  /// The LS/SRM date, as a date-only string.
  final String? lsSrmDate;

  /// Where the case sits in the review. Null on an upload, which states none —
  /// and so must not overwrite the status a stored case already has.
  final String? status;

  /// The row as it goes on the wire, every key present.
  Map<String, dynamic> toJson() {
    return {
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
      'segment': segment,
      'facility': facility,
      'sr_no': srNo,
      'maker': maker,
      'checker': checker,
      'ls_srm_date': lsSrmDate,
      'status': status,
    };
  }

  /// True when the row states the triple that identifies a case.
  ///
  /// A row missing any of them cannot be stored without colliding with every
  /// other such row, so the endpoint refuses the whole submit.
  bool get hasIdentity => ![clientId, accountNo, lineNo]
      .any((value) => (value ?? '').trim().isEmpty);
}
