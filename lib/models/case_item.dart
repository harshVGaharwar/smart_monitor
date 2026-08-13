import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Where a record sits in the review workflow.
///
/// The first two are what a reviewer can set from the Verify tab, and what
/// the server stores. The rest predate that and are kept so a case carrying
/// one still renders rather than being silently rewritten.
enum CaseStatus {
  pendingWithCpu('Pending with CPU'),
  pendingWithHealthChecker('Pending with Health Checker'),
  inReview('In Review'),
  verified('Verified'),
  completed('Completed'),
  needClarification('Need Clarification');

  final String label;
  const CaseStatus(this.label);

  /// The statuses the Verify tab offers. Everything else is legacy.
  static const assignable = [pendingWithCpu, pendingWithHealthChecker];
}

/// What happened to a record. Carries its own presentation so the dashboard's
/// Activity cell and the detail panel's audit timeline stay in step.
enum ActivityType {
  created('Record Created', Icons.circle, AppColors.textSecondary),
  assigned('Assigned', Icons.arrow_forward_rounded, AppColors.primaryLight),
  reassigned('Reassigned', Icons.swap_horiz_rounded, AppColors.warning),
  commentAdded(
    'Comment Added',
    Icons.chat_bubble_outline_rounded,
    Color(0xFF7C3AED),
  ),
  documentUploaded(
    'Document Uploaded',
    Icons.attach_file_rounded,
    AppColors.textSecondary,
  ),
  verified('Verified', Icons.check_rounded, AppColors.success);

  final String label;
  final IconData icon;
  final Color color;
  const ActivityType(this.label, this.icon, this.color);
}

/// The most recent thing that happened, shown in the grid's Activity column.
class ActivityEntry {
  final ActivityType type;
  final DateTime at;

  const ActivityEntry({required this.type, required this.at});
}

/// One entry in the audit history.
class CaseActivity {
  final ActivityType type;
  final String actor;
  final DateTime at;

  /// Quoted under the heading for [ActivityType.commentAdded].
  final String comment;

  const CaseActivity({
    required this.type,
    required this.actor,
    required this.at,
    this.comment = '',
  });
}

/// A note on the record's discussion thread.
class CaseComment {
  final String author;
  final String text;
  final DateTime at;

  /// Why the record was routed on, when this note came with a reassignment.
  /// Shown beside the author; empty on every other comment.
  final String reason;

  const CaseComment({
    required this.author,
    required this.text,
    required this.at,
    this.reason = '',
  });

  /// Up to two initials for the avatar, derived rather than stored.
  String get initials =>
      author
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .take(2)
          .map((w) => w[0].toUpperCase())
          .join();

  /// A stable colour per author, so the same person keeps the same avatar.
  Color get avatarColor {
    const palette = [
      Color(0xFF0F9D8C),
      Color(0xFF7C3AED),
      Color(0xFF2E5AA0),
      Color(0xFFC2410C),
      Color(0xFFBE185D),
      Color(0xFF15803D),
    ];
    return palette[author.hashCode.abs() % palette.length];
  }
}

/// A file attached to a record.
class CaseDocument {
  final String name;
  final String uploadedBy;
  final DateTime uploadedAt;
  final String version;

  const CaseDocument({
    required this.name,
    required this.uploadedBy,
    required this.uploadedAt,
    this.version = 'v1.0',
  });
}

/// A single health-check exception record.
class CaseItem {
  /// Business reference shown in the detail header, e.g. `EXC-02009`.
  final String exceptionCode;

  final String clientId;
  final String customerName;
  final String accountNo;
  final String lineNo;

  /// The check that raised the record, e.g. `FD Exceptions`.
  final String healthCheckCategory;

  /// What specifically failed, e.g. `Excess lien marked in Core`.
  final String subCategory;

  final String supportSystem;
  final String coreSystem;
  final String exceptionCategory;
  final String reason;
  final String segment;

  /// The facility the exception sits against, and its serial number within the
  /// account — two columns on the wire (`facility`, `sr_no`). Carried through
  /// rather than shown: an update posts them back, and a row that omitted them
  /// would blank what is stored.
  final String facility;
  final String srNo;
  final String maker;
  final String checker;
  final DateTime? lsrmDate;

  // Assignment
  final String cpu;
  final String team;
  final String assignedBy;
  final DateTime? assignedDate;
  final String priority;

  final CaseStatus status;

  /// Latest event, for the grid's Activity column.
  final ActivityEntry? lastActivity;

  /// How many notes the case has collected, for the grid's Message column.
  ///
  /// Carried on the row rather than counted off [comments]: a grid row is read
  /// from the queue endpoint, which does not send the thread — counting there
  /// would report every case as having none.
  final int messageCount;

  /// Latest note, for the grid's Updated column.
  final String updatedNote;
  final String updatedBy;
  final DateTime? updatedAt;

  final List<CaseComment> comments;
  final List<CaseActivity> activity;

  const CaseItem({
    required this.exceptionCode,
    required this.clientId,
    required this.customerName,
    required this.accountNo,
    required this.status,
    this.lineNo = '',
    this.healthCheckCategory = 'FD Exceptions',
    this.subCategory = '',
    this.supportSystem = '',
    this.coreSystem = '',
    this.exceptionCategory = 'Exception',
    this.reason = '',
    this.segment = '',
    this.facility = '',
    this.srNo = '',
    this.maker = '',
    this.checker = '',
    this.lsrmDate,
    this.cpu = '',
    this.team = '',
    this.assignedBy = '',
    this.assignedDate,
    this.priority = '',
    this.lastActivity,
    this.messageCount = 0,
    this.updatedNote = '',
    this.updatedBy = '',
    this.updatedAt,
    this.comments = const [],
    this.activity = const [],
  });

  /// The case as the import endpoint expects it.
  ///
  /// Keyed on client id / account no / line no, which is how the server finds
  /// the stored row again — so posting this updates that case rather than
  /// adding a second one.
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
    'ls_srm_date': lsrmDate?.toIso8601String(),
    'exception_category': exceptionCategory,
    'reason': reason,
    'cpu': cpu,
    'team': team,
    'status': status.label,
  };

  /// Maps the server's status text onto the enum.
  ///
  /// An unrecognised value lands on the status the server itself gives a case
  /// nobody has reviewed yet, so the row still reaches the grid — and does so
  /// in a bucket the STATUS filter actually offers.
  static CaseStatus statusFrom(String raw) {
    final key = _normalise(raw);
    for (final status in CaseStatus.values) {
      if (_normalise(status.label) == key) return status;
    }
    return switch (key) {
      'closed' || 'done' => CaseStatus.completed,
      'review' || 'underreview' => CaseStatus.inReview,
      'escalated' || 'clarification' => CaseStatus.needClarification,
      'approved' => CaseStatus.verified,
      _ => CaseStatus.pendingWithCpu,
    };
  }

  static String _normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Numeric part of [exceptionCode], used as a stable sort/identity key.
  int get id =>
      int.tryParse(exceptionCode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  CaseItem copyWith({
    CaseStatus? status,
    String? cpu,
    String? team,
    String? assignedBy,
    DateTime? assignedDate,
    String? priority,
    List<CaseComment>? comments,
    List<CaseActivity>? activity,
    ActivityEntry? lastActivity,
    int? messageCount,
    String? updatedNote,
    String? updatedBy,
    DateTime? updatedAt,
  }) {
    return CaseItem(
      exceptionCode: exceptionCode,
      clientId: clientId,
      customerName: customerName,
      accountNo: accountNo,
      status: status ?? this.status,
      lineNo: lineNo,
      healthCheckCategory: healthCheckCategory,
      subCategory: subCategory,
      supportSystem: supportSystem,
      coreSystem: coreSystem,
      exceptionCategory: exceptionCategory,
      reason: reason,
      segment: segment,
      facility: facility,
      srNo: srNo,
      maker: maker,
      checker: checker,
      lsrmDate: lsrmDate,
      cpu: cpu ?? this.cpu,
      team: team ?? this.team,
      assignedBy: assignedBy ?? this.assignedBy,
      assignedDate: assignedDate ?? this.assignedDate,
      priority: priority ?? this.priority,
      lastActivity: lastActivity ?? this.lastActivity,
      messageCount: messageCount ?? this.messageCount,
      updatedNote: updatedNote ?? this.updatedNote,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      comments: comments ?? this.comments,
      activity: activity ?? this.activity,
    );
  }
}
