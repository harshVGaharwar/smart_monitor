import 'dart:io';

import 'package:backend/src/cases_repository.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /api/get-smartpointer — every stored case, for the dashboard grid.
///
/// The rows are shaped exactly as `/api/cases/upload` returns them, so one
/// mapping on the client serves both screens. Two fields are added that only
/// exist once a case has been stored: `status` and `imported_at`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'message': 'Use GET to read the stored cases.'},
    );
  }

  final rows = context.read<CasesRepository>().allCases();
  return Response.json(body: {'rows': rows, 'count': rows.length});
}
