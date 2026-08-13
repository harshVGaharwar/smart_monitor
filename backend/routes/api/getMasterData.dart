import 'dart:io';

import 'package:backend/src/api_envelope.dart';
import 'package:backend/src/master_data.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/getMasterData — the reference lists every screen works against.
///
/// ```text
/// GET /api/getMasterData
/// ```
///
/// No parameters. The lists are the same for every user and every screen: what
/// a CPU is called does not depend on who is asking, so there is nothing here
/// to narrow by employee code or role the way `/api/get-smartpointer` is.
///
/// Five lists under `data`, each an array of plain strings:
/// `cpus`, `teams`, `exceptionCategories`, `healthCheckCategories` and
/// `reassignReasons`. Plain strings because that is what a case row stores —
/// the client matches an uploaded value onto one of these and writes the
/// canonical spelling back, so an id alongside the name would be a second
/// identity for something the database already keys by name.
///
/// One call rather than five: they are read together, by the dashboard's
/// reassign panel and the upload screen's validation alike, and a screen that
/// had to wait on five round trips would show empty dropdowns for four of them.
///
/// Stateless — no repository, nothing to read off the context. The data is
/// fixed at compile time; see `masterData`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return SmartEnvelope.failure(
      'Use GET to read master data.',
      statusCode: HttpStatus.methodNotAllowed,
    );
  }

  return SmartEnvelope.success(
    message: 'Master Data Loaded',
    data: masterData,
  );
}
