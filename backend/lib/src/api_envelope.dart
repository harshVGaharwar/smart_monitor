import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// The response envelope every endpoint here answers with.
///
/// It mirrors the shape the UAT gateway returns
/// (`https://BBRAUAT.hdfcbankuat.com:9124/SmartAPI/…`) field for field and in
/// the same order, so the client reads one contract whether it is pointed at
/// this server or at the real one — which is the whole point of running this
/// locally.
///
/// The fields this server has nothing to say about — `body`, `userName`,
/// `userCode`, `branchName`, `branchCode`, `menu` — are sent as null rather
/// than dropped: a client written against UAT expects the keys to be present,
/// and a missing key reads differently from an explicit null.
///
/// The payload a caller actually wants is always under `data`. Its shape is
/// per endpoint: `{"rows": [...]}` for the two read endpoints, a plain integer
/// for `update-smartpointer`.
class SmartEnvelope {
  SmartEnvelope._();

  /// `code` on a response that worked.
  static const int ok = 0;

  /// `code` on a request the caller can fix — a bad payload, an unreadable
  /// file. Distinct from [ok]; the client treats anything non-zero as failed.
  static const int failed = 1;

  /// A 200 carrying [data].
  ///
  /// [message] is the text UAT sends for the same call, since it is shown as
  /// is on the upload card and in the import toast.
  static Response success({
    required String message,
    Object? data,
    int count = 0,
  }) {
    return Response.json(
      body: build(
        code: ok,
        message: message,
        success: true,
        data: data,
        count: count,
      ),
    );
  }

  /// A failure, in the same envelope.
  ///
  /// The HTTP status is kept honest ([statusCode]) as well as the envelope's
  /// `success`/`code`, so a client that only checks one of the two still sees
  /// the failure. `data` is null: there is no payload to read.
  static Response failure(
    String message, {
    int statusCode = HttpStatus.badRequest,
    int code = failed,
  }) {
    return Response.json(
      statusCode: statusCode,
      body: build(code: code, message: message, success: false),
    );
  }

  /// The envelope itself, for a caller that needs the map rather than a
  /// response — the tests, mainly.
  ///
  /// Insertion order is the order UAT writes the fields in, so a local
  /// response can be diffed against a captured one without reordering it
  /// first.
  static Map<String, dynamic> build({
    required int code,
    required String message,
    required bool success,
    Object? data,
    int count = 0,
  }) {
    return <String, dynamic>{
      'code': code,
      'message': message,
      'body': null,
      'success': success,
      'data': data,
      'count': count,
      'userName': null,
      'userCode': null,
      'branchName': null,
      'branchCode': null,
      'menu': null,
    };
  }
}
