import 'case_item.dart';
import 'case_row.dart';

/// The body of `GET /get-smartpointer` — the stored cases the dashboard grid
/// shows.
///
/// Mirrors the service's envelope field for field and in the same order, so
/// the response can be read against a captured payload without translating it
/// first. The fields this app has no use for — [body], [userName], [userCode],
/// [branchName], [branchCode], [menu] — are carried rather than dropped: they
/// are part of the contract, and a caller that starts needing one should find
/// it here rather than reaching back into a decoded map.
///
/// The rows arrive as [CaseRow], the wire shape, and [cases] maps them into
/// the model the screens work in.
class CasesResponse {
  /// `code` on a response that worked.
  static const int ok = 0;

  /// `code` on one the caller cannot use, including the failures this app
  /// reports for itself when the body never came from the service at all.
  static const int rejected = 1;

  /// 0 on a response that worked, non-zero on one the caller can fix.
  final int code;

  /// What the service said. `Upload Successful` on a read that worked — the
  /// same text it answers the upload with.
  final String message;

  /// Always null from this service; carried because the contract has it.
  final Object? body;

  /// Mirrors [code]. Either one can report a failure on a 200, so this rather
  /// than the HTTP status is what decides whether the response is usable.
  final bool success;

  /// The payload. Null on a failure, which is why [cases] can answer empty
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

  const CasesResponse({
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
  /// too, since `ApiClient` hands those over as a raw string rather than
  /// throwing. Reading one as zero rows would put an empty grid in front of
  /// the user with nothing to say why, so each becomes a failure carrying the
  /// text as its message.
  factory CasesResponse.fromBody(Object? body) {
    if (body is Map<String, dynamic>) return CasesResponse.fromJson(body);
    // A server that answers with the rows and no envelope around them.
    if (body is List) {
      return CasesResponse.fromJson({
        'code': ok,
        'success': true,
        'data': body,
      });
    }
    final text = body == null ? '' : '$body'.trim();
    return CasesResponse.fromJson({
      'code': rejected,
      'success': false,
      'message': text.isEmpty ? 'The server sent an empty response.' : text,
    });
  }

  /// Reads the response body.
  ///
  /// Every field is read defensively — a missing key or an unexpected type
  /// yields a default rather than throwing. A dashboard that cannot render is
  /// a worse answer than one row with a blank cell.
  ///
  /// A body that is not a JSON object never reaches here: `CaseApi` turns a
  /// gateway's error page or an empty response into an `ApiException` first,
  /// so the message the user sees says what actually happened.
  factory CasesResponse.fromJson(Map<String, dynamic> json) {
    // A body with no `data` key is its own payload, so a server answering
    // with a plain `{"rows": [...]}` — or an older build of this one — still
    // reads. An envelope that states `data: null` means a failure carrying no
    // payload, which is a different thing and stays null.
    final payload = json.containsKey('data') ? json['data'] : json;
    return CasesResponse(
      code: _int(json['code']) ?? 0,
      message: _text(json['message']),
      body: json['body'],
      // Absent means nothing was claimed either way, so `code` decides — a
      // server that reports only one of the two is still understood.
      success:
          json['success'] is bool
              ? json['success'] as bool
              : (_int(json['code']) ?? ok) == ok,
      data: payload == null ? null : DataBlock.fromJson(payload),
      count: _int(json['count']) ?? 0,
      userName: _nullable(json['userName']),
      userCode: _nullable(json['userCode']),
      branchName: _nullable(json['branchName']),
      branchCode: _nullable(json['branchCode']),
      menu: json['menu'],
    );
  }

  /// The cases, in the order the service listed them, read into the model the
  /// screens work in.
  List<CaseItem> get cases => [for (final row in rows) row.toCaseItem()];

  /// The rows as they arrived, for a caller that wants the wire shape.
  List<CaseRow> get rows => data?.rows ?? const [];

  /// How many cases arrived.
  ///
  /// [count] is not it: the service sends 0 there even on a response plainly
  /// carrying rows, so the footer would claim records the grid cannot show.
  int get rowCount => rows.length;

  /// True when the call worked, whatever it returned.
  ///
  /// [success] alone decides. [code] is not re-checked here: a gateway that
  /// answers `success: true` with an HTTP-style code of 200 is reporting
  /// success, and reading the code as well would throw away a perfectly good
  /// payload. Where the response states no `success`, the code has already
  /// settled it — see the constructor.
  bool get isSuccess => success;

  /// Why the call failed, or null when it succeeded.
  ///
  /// A failure can arrive with a 200 — the envelope reports it in `success`
  /// and `code`, not in the status line — so this, not the HTTP status, is
  /// what the dashboard's error banner is driven from.
  String? get failure {
    if (isSuccess) return null;
    return message.isEmpty ? 'The server rejected the request.' : message;
  }

  /// True when the service holds no cases yet — the grid's empty state, which
  /// is not an error.
  bool get isEmpty => rows.isEmpty;

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

/// The `data` block of a read response: the rows and nothing else.
///
/// A type of its own rather than a bare list because that is what the wire
/// says — `data` is an object with a `rows` array, and flattening it here
/// would hide a level the contract actually has.
class DataBlock {
  final List<CaseRow> rows;

  const DataBlock({required this.rows});

  /// Reads the block.
  ///
  /// Accepts a bare array as well as the `{"rows": [...]}` object, and the
  /// `data` / `items` spellings, so a server that returns the list directly
  /// still reads.
  factory DataBlock.fromJson(Object? json) {
    final raw =
        json is List
            ? json
            : (json is Map
                ? json['rows'] ?? json['data'] ?? json['items']
                : null);

    return DataBlock(
      rows: [
        if (raw is List)
          for (final item in raw)
            if (item is Map<String, dynamic>) CaseRow.fromJson(item),
      ],
    );
  }
}
