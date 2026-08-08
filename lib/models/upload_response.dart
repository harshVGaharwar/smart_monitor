import 'case_row.dart';
import 'cases_response.dart';
import 'pending_case.dart';

/// The body of `POST /read-excel` — the workbook as the server read it.
///
/// Mirrors the service's envelope field for field and in the same order, the
/// way [CasesResponse] does for the dashboard, so a response can be read
/// against a captured payload without translating it first. The fields this
/// app has no use for — [body], [userName], [userCode], [branchName],
/// [branchCode], [menu] — are carried rather than dropped: they are part of the
/// contract, and a caller that starts needing one should find it here.
///
/// The rows arrive as [CaseRow], the same wire model the dashboard reads, since
/// the two endpoints return the same row: an upload row is a stored one without
/// `status` and `imported_at`. [rows] maps them into [PendingCase], the
/// editable model the upload screen works in.
class UploadResponse {
  /// 0 on a response that worked, non-zero on one the caller can fix.
  final int code;

  /// What the service said. `Upload Successful` on a read that worked — shown
  /// on the upload card as it arrives.
  final String message;

  /// Always null from this service; carried because the contract has it.
  final Object? body;

  /// Mirrors [code]. Either one can report a failure on a 200, so this rather
  /// than the HTTP status is what decides whether the response is usable.
  final bool success;

  /// The payload. Null on a failure, which is why [rows] can answer empty
  /// without anyone having to check.
  final DataBlock? data;

  /// What the service reported. It is 0 even on responses plainly carrying
  /// rows, so nothing counts with it — see [rowCount].
  final int count;

  final String? userName;
  final String? userCode;
  final String? branchName;
  final String? branchCode;
  final Object? menu;

  const UploadResponse({
    required this.code,
    required this.message,
    this.body,
    required this.success,
    this.data,
    required this.count,
    this.userName,
    this.userCode,
    this.branchName,
    this.branchCode,
    this.menu,
  });

  /// Reads a decoded body of any shape.
  ///
  /// A decoded body is usually a JSON object, but not always: a gateway's
  /// error page, a proxy's plain text and an empty response all arrive here
  /// too. Reading one as zero rows would leave the upload card saying nothing,
  /// so each becomes a failure carrying the text as its message.
  factory UploadResponse.fromBody(Object? body) {
    if (body is Map<String, dynamic>) return UploadResponse.fromJson(body);
    // A server that answers with the rows and no envelope around them.
    if (body is List) {
      return UploadResponse.fromJson({
        'code': CasesResponse.ok,
        'success': true,
        'data': body,
      });
    }
    final text = body == null ? '' : '$body'.trim();
    return UploadResponse.fromJson({
      'code': CasesResponse.rejected,
      'success': false,
      'message': text.isEmpty ? 'The server sent an empty response.' : text,
    });
  }

  /// Reads the response body.
  ///
  /// Every field is read defensively — a missing key or an unexpected type
  /// yields a default rather than throwing. A screen that cannot render the
  /// file is a worse answer than one row with a blank cell.
  factory UploadResponse.fromJson(Map<String, dynamic> json) {
    // A body with no `data` key is its own payload, so a server answering with
    // a plain `{"rows": [...]}` still reads. An envelope that states
    // `data: null` means a failure carrying no payload, and stays null.
    final payload = json.containsKey('data') ? json['data'] : json;
    return UploadResponse(
      code: _int(json['code']) ?? CasesResponse.ok,
      message: _text(json['message']),
      body: json['body'],
      // Absent means nothing was claimed either way, so `code` decides — a
      // server that reports only one of the two is still understood.
      success: json['success'] is bool
          ? json['success'] as bool
          : (_int(json['code']) ?? CasesResponse.ok) == CasesResponse.ok,
      data: payload == null ? null : DataBlock.fromJson(payload),
      count: _int(json['count']) ?? 0,
      userName: _nullable(json['userName']),
      userCode: _nullable(json['userCode']),
      branchName: _nullable(json['branchName']),
      branchCode: _nullable(json['branchCode']),
      menu: json['menu'],
    );
  }

  /// The rows as they arrived, for a caller that wants the wire shape.
  List<CaseRow> get wireRows => data?.rows ?? const [];

  /// Every data row in the file, clean or not, in file order.
  ///
  /// Numbered as it maps: the response carries no id, so a row's position in
  /// the file is what fills the report's ID column — and it has to survive
  /// filtering and the errors-only export, where the list order no longer
  /// matches the file.
  List<PendingCase> get rows => [
    for (final (index, row) in wireRows.indexed)
      row.toPendingCase(sequence: index + 1),
  ];

  /// How many rows arrived.
  ///
  /// [count] is not it: the service sends 0 there even on a response plainly
  /// carrying rows, so the card would report a file it did not read.
  int get rowCount => wireRows.length;

  /// True when the call worked, whatever it returned.
  ///
  /// [success] alone decides. [code] is not re-checked: a gateway that answers
  /// `success: true` with an HTTP-style code of 200 is reporting success, and
  /// reading the code as well would throw away a file the user just uploaded.
  bool get isSuccess => success;

  /// Why the call failed, or null when it succeeded. The message is shown
  /// verbatim on the upload card, so it is passed through as it arrived.
  String? get failure {
    if (isSuccess) return null;
    return message.isEmpty ? 'The server rejected the request.' : message;
  }

  /// True when the server returned nothing the report could show.
  bool get isEmpty => wireRows.isEmpty;

  /// The editable review state for these rows.
  ///
  /// A fresh outcome each call: it is mutable, and the screen owns the copy it
  /// is showing.
  UploadOutcome toOutcome() => UploadOutcome(rows: rows);

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  static String _text(Object? value) {
    if (value == null) return '';
    final text = '$value'.trim();
    return text == 'null' || text == 'nan' ? '' : text;
  }

  static String? _nullable(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }
}
