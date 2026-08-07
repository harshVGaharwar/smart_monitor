import 'dart:io';
import 'dart:typed_data';

import 'package:backend/src/cases_file_parser.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/cases/upload — the bulk health-check spreadsheet.
///
/// Takes the workbook as multipart under the field `file` and returns its rows
/// parsed, under `rows`. The values are returned as the file stated them; the
/// client resolves CPU / team / category against the master data so its
/// results table can revalidate a corrected cell without another round trip.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'message': 'Use POST to upload a cases file.'},
    );
  }

  final FormData form;
  try {
    form = await context.request.formData();
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'Expected a multipart upload with a "file" part.'},
    );
  }

  final file = form.files['file'];
  if (file == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'No file was attached to the upload.'},
    );
  }

  final bytes = Uint8List.fromList(await file.readAsBytes());
  if (bytes.lengthInBytes > _maxUploadBytes) {
    return Response.json(
      statusCode: HttpStatus.requestEntityTooLarge,
      body: {'message': 'The file is larger than the 25 MB limit.'},
    );
  }

  // The client states the type alongside the part; a browser upload can carry
  // a filename the server should not have to trust. Falling back to the
  // filename keeps plain multipart posts (curl, the API tests) working.
  final declared = form.fields['fileType']?.trim().toLowerCase();
  final extension = (declared == null || declared.isEmpty)
      ? _extensionOf(file.name)
      : declared.replaceFirst(RegExp(r'^\.'), '');

  try {
    final rows = CasesFileParser.parse(extension: extension, bytes: bytes);
    return Response.json(body: {'rows': rows, 'count': rows.length});
  } on CasesFileException catch (e) {
    // A file the user can fix — a missing column, an unreadable workbook — so
    // it is reported as a rejected request rather than a server fault, and the
    // message is the one shown on the upload card.
    return Response.json(
      statusCode: HttpStatus.unprocessableEntity,
      body: {'message': e.message},
    );
  }
}

/// Mirrors the ceiling the client enforces before the bytes are sent.
const _maxUploadBytes = 25 * 1024 * 1024;

/// The extension of [filename], lowercased and without the dot.
String _extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return '';
  return filename.substring(dot + 1).toLowerCase();
}
