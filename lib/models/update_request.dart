import 'case_item.dart';
import 'pending_case.dart';

/// The body of `POST /update-smartpointer` — the rows to persist.
///
/// One typed contract for the only write endpoint the app has, mirrored by
/// `backend/lib/src/update_request.dart`. Both writers go through it: the bulk
/// submit at the end of the upload review, and the Verify tab saving a single
/// case. The server echoes the rows it stored back in the same shape, so
/// [UpdateRequestRow] reads as well as writes.
class UpdateRequestModel {
  final List<UpdateRequestRow> rows;

  UpdateRequestModel({required this.rows});

  factory UpdateRequestModel.fromJson(Map<String, dynamic> json) {
    return UpdateRequestModel(
      rows:
          (json['rows'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(UpdateRequestRow.fromJson)
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'rows': rows.map((e) => e.toJson()).toList()};
  }
}

/// One case on the wire.
///
/// Every field is a nullable string and every key is emitted, nulls included:
/// the store holds all of them as text, and a field the client has nothing for
/// is meaningfully absent rather than blank. A null [status] in particular
/// leaves a stored case's status alone, which is what an upload — which never
/// carries one — needs.
class UpdateRequestRow {
  final String? clientId;
  final String? customerName;
  final String? accountNo;
  final String? lineNo;
  final String? healthCheckCategory;
  final String? subCategory;
  final String? supportSystem;
  final String? coreSystem;
  final String? exceptionCategory;
  final String? reason;
  final String? cpu;
  final String? team;
  final String? segment;
  final String? facility;
  final String? srNo;
  final String? maker;
  final String? checker;
  final String? lsSrmDate;
  final String? status;

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
      team: json['team']?.toString(),
      segment: json['segment']?.toString(),
      facility: json['facility']?.toString(),
      srNo: json['sr_no']?.toString(),
      maker: json['maker']?.toString(),
      checker: json['checker']?.toString(),
      lsSrmDate: json['ls_srm_date']?.toString(),
      status: json['status']?.toString(),
    );
  }

  /// A reviewed upload row, as the bulk submit posts it.
  ///
  /// [PendingCase.cpu] and [PendingCase.actionableTeam] are null until the row
  /// resolves against the master data; only valid rows are submitted, so the
  /// raw text is not a useful fallback here. No status: an uploaded file never
  /// states one, and sending a blank would risk resetting a case a reviewer
  /// has already moved on.
  factory UpdateRequestRow.fromPendingCase(PendingCase row) {
    return UpdateRequestRow(
      clientId: row.clientId,
      customerName: row.customerName,
      accountNo: row.accountNo,
      lineNo: row.lineNo,
      healthCheckCategory: row.healthCheckCategory,
      subCategory: row.subCategory,
      supportSystem: row.supportSystem,
      coreSystem: row.coreSystem,
      exceptionCategory: row.exceptionCategory,
      reason: row.reason,
      cpu: row.cpu ?? '',
      team: row.actionableTeam ?? '',
      segment: row.segment,
      facility: row.facility,
      srNo: row.facilitySrNo,
      maker: row.maker,
      checker: row.checker,
      lsSrmDate: row.lsSrmDate,
    );
  }

  /// A stored case, as the Verify tab writes it back.
  ///
  /// Carries the status — changing it is the whole point of that save — and
  /// the fields the screen never shows, so posting one case does not blank
  /// what is stored against it.
  factory UpdateRequestRow.fromCaseItem(CaseItem item) {
    return UpdateRequestRow(
      clientId: item.clientId,
      customerName: item.customerName,
      accountNo: item.accountNo,
      lineNo: item.lineNo,
      healthCheckCategory: item.healthCheckCategory,
      subCategory: item.subCategory,
      supportSystem: item.supportSystem,
      coreSystem: item.coreSystem,
      exceptionCategory: item.exceptionCategory,
      reason: item.reason,
      cpu: item.cpu,
      team: item.team,
      segment: item.segment,
      facility: item.facility,
      srNo: item.srNo,
      maker: item.maker,
      checker: item.checker,
      lsSrmDate: item.lsrmDate?.toIso8601String() ?? '',
      status: item.status.label,
    );
  }

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

  UpdateRequestRow copyWith({
    String? clientId,
    String? customerName,
    String? accountNo,
    String? lineNo,
    String? healthCheckCategory,
    String? subCategory,
    String? supportSystem,
    String? coreSystem,
    String? exceptionCategory,
    String? reason,
    String? cpu,
    String? team,
    String? segment,
    String? facility,
    String? srNo,
    String? maker,
    String? checker,
    String? lsSrmDate,
    String? status,
  }) {
    return UpdateRequestRow(
      clientId: clientId ?? this.clientId,
      customerName: customerName ?? this.customerName,
      accountNo: accountNo ?? this.accountNo,
      lineNo: lineNo ?? this.lineNo,
      healthCheckCategory: healthCheckCategory ?? this.healthCheckCategory,
      subCategory: subCategory ?? this.subCategory,
      supportSystem: supportSystem ?? this.supportSystem,
      coreSystem: coreSystem ?? this.coreSystem,
      exceptionCategory: exceptionCategory ?? this.exceptionCategory,
      reason: reason ?? this.reason,
      cpu: cpu ?? this.cpu,
      team: team ?? this.team,
      segment: segment ?? this.segment,
      facility: facility ?? this.facility,
      srNo: srNo ?? this.srNo,
      maker: maker ?? this.maker,
      checker: checker ?? this.checker,
      lsSrmDate: lsSrmDate ?? this.lsSrmDate,
      status: status ?? this.status,
    );
  }
}
