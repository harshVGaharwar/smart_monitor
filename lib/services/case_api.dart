import 'dart:typed_data';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/case_item.dart';
import '../models/case_row.dart';
import '../models/cases_response.dart';
import '../models/import_response.dart';
import '../models/pending_case.dart';
import '../models/update_request.dart';
import '../models/upload_response.dart';

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
    final rows =
        body is List
            ? body
            : (body is Map
                ? body['data'] ?? body['items'] ?? const []
                : const []);
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

  /// GET /get-smartpointer — every stored case, for the dashboard grid.
  ///
  /// Returns the rows shaped as the upload endpoint returns them, so the two
  /// screens share one row contract.
  Future<CasesResponse> fetchSmartPointer() async {
    final body = await _client.get(ApiEndpoints.smartPointer);
    final response = CasesResponse.fromBody(body);

    // The envelope reports a refused call in `success` / `code` rather than in
    // the status line, so a 200 can still be a failure. Raised as the same
    // exception a transport error raises, so the dashboard's error banner
    // handles both without knowing the difference.
    if (!response.isSuccess) throw ApiException(response.failure!);
    return response;
  }

  /// POST /read-excel — the bulk spreadsheet.
  ///
  /// The server reads the workbook and returns the parsed rows; the app no
  /// longer opens .xlsx/.csv itself. Validity is still decided here rather
  /// than trusted from the response, because the results table lets the user
  /// correct CPU / team / category cells and each edit has to move the row
  /// between "ready" and "needs attention" straight away.
  Future<UploadResponse> uploadCasesFile({
    required Uint8List bytes,
    required String filename,
  }) async {
    final body = await _client.uploadBytes(
      ApiEndpoints.uploadCases,
      bytes: bytes,
      filename: filename,
      field: 'file',
      // Stated alongside the part rather than left to be re-derived: a browser
      // upload can arrive with a filename the server cannot rely on.
      fields: {'fileType': fileExtension(filename)},
    );

    final response = UploadResponse.fromBody(body);
    // A failure the envelope reports on a 200 — the message is the one the
    // upload card shows, so it is passed through as it arrived.
    if (!response.isSuccess) throw ApiException(response.failure!);
    if (response.isEmpty) {
      // A 2xx with nothing usable in it means the response was not the shape
      // this app expects — a different backend, a proxy's page, an empty
      // body. Say which, because "no rows" alone sends people looking at
      // their spreadsheet when the problem is the endpoint.
      throw ApiException(
        body == null
            ? 'The server accepted the file but sent no response body.'
            : 'The server accepted the file but returned no rows. '
                'It answered with ${_describe(body)}.',
      );
    }
    return response;
  }

  /// POST /update-smartpointer — persist the rows the user approved.
  ///
  /// The end of the upload flow: only rows that passed validation and were
  /// not removed in the review are sent. Re-submitting a corrected file
  /// updates the cases already stored rather than duplicating them.
  Future<UpdatedCasesResponse> importCases(List<PendingCase> rows) async {
    if (rows.isEmpty) {
      throw const ApiException('There were no rows to import.');
    }

    final body = await _client.post(
      ApiEndpoints.upddateCase,
      body:
          UpdateRequestModel(
            rows: [
              for (final row in rows) UpdateRequestRow.fromPendingCase(row),
            ],
          ).toJson(),
    );
    final response = UpdatedCasesResponse.fromJson(
      body,
      sentCount: rows.length,
    );
    // Nothing was written when the envelope says so, whatever the status line
    // said — reporting "imported" here would be a lie the user acts on.
    if (!response.isSuccess) throw ApiException(response.failure!);
    return response;
  }

  /// Writes one case back, through the same import endpoint the bulk submit
  /// uses.
  ///
  /// It upserts on client id / account no / line no, so posting a single case
  /// updates the stored row rather than adding another — which is what the
  /// Verify tab needs when it changes a status.
  Future<UpdatedCasesResponse> updateCase(CaseItem item) async {
    final body = await _client.post(
      ApiEndpoints.upddateCase,
      body:
          UpdateRequestModel(
            rows: [UpdateRequestRow.fromCaseItem(item)],
          ).toJson(),
    );
    final response = UpdatedCasesResponse.fromJson(body, sentCount: 1);
    if (!response.isSuccess) throw ApiException(response.failure!);
    return response;
  }

  /// A short, safe description of a response body, for an error message.
  ///
  /// Never the body itself: it may be long, and an upload response carries
  /// customer names.
  static String _describe(Object? body) {
    if (body is Map) {
      final keys = body.keys.take(6).join(', ');
      return keys.isEmpty ? 'an empty object' : 'an object with: $keys';
    }
    if (body is List) return 'an empty list';
    return 'text rather than JSON';
  }

  /// The extension of [filename], lowercased and without the dot — `xlsx` for
  /// `Health Check Aug.xlsx`. Empty when the name carries no extension.
  static String fileExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return '';
    return filename.substring(dot + 1).toLowerCase();
  }

  // --- Mapping ------------------------------------------------------------

  /// One record of a `/cases` response.
  ///
  /// The row itself goes through [CaseRow], so this endpoint and
  /// `get-smartpointer` cannot drift into reading the same columns two ways —
  /// they did, and the copies disagreed about which statuses were legacy.
  ///
  /// What is layered on here is what only this endpoint sends: the assignment
  /// fields and the three nested collections behind the detail panel's
  /// Comments, Documents and Activity tabs. None of them exist on the smart
  /// pointer contract, so they have no place on the row model.
  CaseItem _caseFromJson(Map<String, dynamic> json) {
    final activity = [
      for (final a in _list(json['activity']))
        CaseActivity(
          type: _activityType(_str(a['type'])),
          actor: _str(a['actor'] ?? a['user']),
          at: _date(a['at'] ?? a['created_at']) ?? DateTime.now(),
          comment: _str(a['comment']),
        ),
    ];

    return CaseRow.fromJson(json).toCaseItem().copyWith(
      assignedBy: _str(json['assigned_by']),
      assignedDate: _date(json['assigned_date']),
      priority: _str(json['priority']),
      updatedNote: _str(json['updated_note'] ?? json['last_message']),
      updatedBy: _str(json['updated_by']),
      lastActivity: _lastActivity(json, activity),
      comments: [
        for (final m in _list(json['comments'] ?? json['messages']))
          CaseComment(
            author: _str(m['author']),
            text: _str(m['text'] ?? m['message']),
            at: _date(m['sent_at'] ?? m['created_at']) ?? DateTime.now(),
          ),
      ],
      documents: [
        for (final d in _list(json['documents']))
          CaseDocument(
            name: _str(d['name'] ?? d['filename']),
            uploadedBy: _str(d['uploaded_by']),
            uploadedAt:
                _date(d['uploaded_at'] ?? d['created_at']) ?? DateTime.now(),
            version: _str(d['version'], fallback: 'v1.0'),
          ),
      ],
      activity: activity,
    );
  }

  /// The grid's Activity column. Falls back to the newest audit entry when the
  /// response does not carry a dedicated summary.
  static ActivityEntry? _lastActivity(
    Map<String, dynamic> json,
    List<CaseActivity> activity,
  ) {
    final raw = json['last_activity'];
    if (raw is Map<String, dynamic>) {
      return ActivityEntry(
        type: _activityType(_str(raw['type'])),
        at: _date(raw['at']) ?? DateTime.now(),
      );
    }
    if (activity.isEmpty) return null;
    final last = activity.last;
    return ActivityEntry(type: last.type, at: last.at);
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
}
