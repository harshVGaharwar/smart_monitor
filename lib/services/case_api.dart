import 'dart:typed_data';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/case_item.dart';

/// REST calls for the cases screens.
///
/// Field names follow the column list the upload screen documents. They are
/// read defensively — a missing or differently-typed key yields a default
/// rather than throwing — so a backend rename shows up as a blank cell instead
/// of a crashed page.
class CaseApi {
  final ApiClient _client;

  CaseApi(this._client);

  /// GET /cases — optionally filtered.
  Future<List<CaseItem>> fetchCases({
    String? search,
    String? status,
    DateTime? from,
    DateTime? to,
    int? page,
    int? pageSize,
  }) async {
    final body = await _client.get(
      ApiEndpoints.cases,
      query: {
        'search': search,
        'status': status,
        'from': from?.toIso8601String(),
        'to': to?.toIso8601String(),
        'page': page,
        'pageSize': pageSize,
      },
    );

    // Accept either a bare array or the common {data: [...]} envelope.
    final rows = body is List
        ? body
        : (body is Map ? body['data'] ?? body['items'] ?? const [] : const []);
    return [
      for (final row in rows as List)
        if (row is Map<String, dynamic>) _caseFromJson(row),
    ];
  }

  /// GET /cases/{id}
  Future<CaseItem> fetchCase(int id) async {
    final body = await _client.get(ApiEndpoints.caseById(id));
    if (body is! Map<String, dynamic>) {
      throw const ApiException('Unexpected response for the case record.');
    }
    return _caseFromJson(body);
  }

  /// POST /cases/{id}/messages
  Future<void> sendMessage(int id, String text) {
    return _client.post(ApiEndpoints.caseMessages(id), body: {'text': text});
  }

  /// PUT /cases/{id}/verify
  Future<void> verifyCase(int id) => _client.put(ApiEndpoints.verifyCase(id));

  /// PUT /cases/{id}/reassign
  Future<void> reassignCase(
    int id, {
    required String cpu,
    required String team,
  }) {
    return _client.put(
      ApiEndpoints.reassignCase(id),
      body: {'cpu': cpu, 'team': team},
    );
  }

  /// POST /cases/{id}/documents — multipart.
  Future<void> uploadDocument(
    int id, {
    required Uint8List bytes,
    required String filename,
  }) {
    return _client.uploadBytes(
      ApiEndpoints.caseDocuments(id),
      bytes: bytes,
      filename: filename,
      field: 'document',
    );
  }

  /// POST /cases/upload — the bulk spreadsheet.
  ///
  /// Returns the raw response so the caller can read the accepted count and
  /// the rows that need routing.
  Future<Map<String, dynamic>> uploadCasesFile({
    required Uint8List bytes,
    required String filename,
  }) async {
    final body = await _client.uploadBytes(
      ApiEndpoints.uploadCases,
      bytes: bytes,
      filename: filename,
      field: 'file',
    );
    return body is Map<String, dynamic> ? body : const {};
  }

  // --- Mapping ------------------------------------------------------------

  CaseItem _caseFromJson(Map<String, dynamic> json) {
    return CaseItem(
      exceptionCode: _str(json['exception_code'] ?? json['id']),
      clientId: _str(json['client_id']),
      customerName: _str(json['customer_name']),
      accountNo: _str(json['account_no']),
      lineNo: _str(json['line_no']),
      healthCheckCategory: _str(
        json['health_check_category'] ?? json['health_check'],
        fallback: 'FD Exceptions',
      ),
      subCategory: _str(json['sub_category']),
      supportSystem: _str(json['support_system']),
      coreSystem: _str(json['core_system']),
      exceptionCategory: _str(
        json['exception_category'],
        fallback: 'Exception',
      ),
      reason: _str(json['reason']),
      segment: _str(json['segment']),
      facilitySrNo: _str(json['facility_sr_no'] ?? json['facility_smo']),
      maker: _str(json['maker']),
      checker: _str(json['checker']),
      lsrmDate: _date(json['lsrm_date']),
      cpu: _str(json['cpu']),
      team: _str(json['team'] ?? json['actionable_team']),
      assignedBy: _str(json['assigned_by']),
      assignedDate: _date(json['assigned_date']),
      priority: _str(json['priority']),
      status: _status(_str(json['status'])),
      lastActivity: _lastActivity(json),
      updatedNote: _str(json['updated_note'] ?? json['last_message']),
      updatedBy: _str(json['updated_by']),
      updatedAt: _date(json['updated_at']),
      comments: _list(json['comments'] ?? json['messages'])
          .map(
            (m) => CaseComment(
              author: _str(m['author']),
              text: _str(m['text'] ?? m['message']),
              at: _date(m['sent_at'] ?? m['created_at']) ?? DateTime.now(),
            ),
          )
          .toList(),
      documents: _list(json['documents'])
          .map(
            (d) => CaseDocument(
              name: _str(d['name'] ?? d['filename']),
              uploadedBy: _str(d['uploaded_by']),
              uploadedAt:
                  _date(d['uploaded_at'] ?? d['created_at']) ?? DateTime.now(),
              version: _str(d['version'], fallback: 'v1.0'),
            ),
          )
          .toList(),
      activity: _list(json['activity'])
          .map(
            (a) => CaseActivity(
              type: _activityType(_str(a['type'])),
              actor: _str(a['actor'] ?? a['user']),
              at: _date(a['at'] ?? a['created_at']) ?? DateTime.now(),
              comment: _str(a['comment']),
            ),
          )
          .toList(),
    );
  }

  /// The grid's Activity column. Falls back to the newest audit entry when the
  /// response does not carry a dedicated summary.
  static ActivityEntry? _lastActivity(Map<String, dynamic> json) {
    final raw = json['last_activity'];
    if (raw is Map<String, dynamic>) {
      return ActivityEntry(
        type: _activityType(_str(raw['type'])),
        at: _date(raw['at']) ?? DateTime.now(),
      );
    }
    final entries = _list(json['activity']);
    if (entries.isEmpty) return null;
    final last = entries.last;
    return ActivityEntry(
      type: _activityType(_str(last['type'])),
      at: _date(last['at'] ?? last['created_at']) ?? DateTime.now(),
    );
  }

  /// Unrecognised activity names fall back to a comment rather than dropping
  /// the entry from the timeline.
  static ActivityType _activityType(String raw) {
    final key = _normalise(raw);
    for (final type in ActivityType.values) {
      if (_normalise(type.label) == key || type.name.toLowerCase() == key) {
        return type;
      }
    }
    return ActivityType.commentAdded;
  }

  static String _str(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = '$value'.trim();
    // Spreadsheet exports routinely carry these as stand-ins for empty.
    if (text.isEmpty || text == 'null' || text == 'nan') return fallback;
    return text;
  }

  /// Lowercase, punctuation stripped — used to match labels sent in any
  /// casing or spacing.
  static String _normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse('$value');
  }

  static List<Map<String, dynamic>> _list(Object? value) => [
    if (value is List)
      for (final item in value)
        if (item is Map<String, dynamic>) item,
  ];

  /// Maps the server's status text onto the enum, defaulting to pending so an
  /// unrecognised value never drops the row.
  static CaseStatus _status(String raw) {
    final key = _normalise(raw);
    for (final status in CaseStatus.values) {
      if (_normalise(status.label) == key) return status;
    }
    return switch (key) {
      'closed' || 'done' => CaseStatus.completed,
      'review' || 'undereview' => CaseStatus.inReview,
      'escalated' || 'clarification' => CaseStatus.needClarification,
      'approved' => CaseStatus.verified,
      _ => CaseStatus.pending,
    };
  }
}
