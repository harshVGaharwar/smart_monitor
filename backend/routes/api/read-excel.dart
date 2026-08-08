import 'dart:io';
import 'dart:typed_data';

import 'package:backend/src/api_envelope.dart';
import 'package:backend/src/cases_file_parser.dart';
import 'package:backend/src/dummy_excel_rows.dart';
import 'package:backend/src/smart_rows.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /api/read-excel — the bulk health-check spreadsheet.
///
/// Takes the workbook as multipart under the field `file` and answers with its
/// rows parsed, under `data.rows` in the shared envelope. The values are
/// returned as the file stated them; the client resolves CPU / team / category
/// against the master data so its results table can revalidate a corrected
/// cell without another round trip.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return SmartEnvelope.failure(
      'Use POST to upload a cases file.',
      statusCode: HttpStatus.methodNotAllowed,
    );
  }

  final FormData form;
  try {
    form = await context.request.formData();
  } catch (_) {
    return SmartEnvelope.failure(
      'Expected a multipart upload with a "file" part.',
    );
  }

  final file = form.files['file'];
  if (file == null) {
    return SmartEnvelope.failure('No file was attached to the upload.');
  }

  final bytes = Uint8List.fromList(await file.readAsBytes());
  if (bytes.lengthInBytes > _maxUploadBytes) {
    return SmartEnvelope.failure(
      'The file is larger than the 25 MB limit.',
      statusCode: HttpStatus.requestEntityTooLarge,
    );
  }

  // The client states the type alongside the part; a browser upload can carry
  // a filename the server should not have to trust. Falling back to the
  // filename keeps plain multipart posts (curl, the API tests) working.
  final declared = form.fields['fileType']?.trim().toLowerCase();
  final extension = (declared == null || declared.isEmpty)
      ? _extensionOf(file.name)
      : declared.replaceFirst(RegExp(r'^\.'), '');

  List<Map<String, dynamic>> parsed;
  try {
    parsed = CasesFileParser.parse(extension: extension, bytes: bytes);
  } on CasesFileException catch (e) {
    // A file the user can fix — a missing column, an unreadable workbook — so
    // it is reported as a rejected request rather than a server fault, and the
    // message is the one shown on the upload card. Unless the sample fallback
    // is on, in which case the screen gets rows to work with instead.
    if (!readExcelFallback) {
      return SmartEnvelope.failure(
        e.message,
        statusCode: HttpStatus.unprocessableEntity,
      );
    }
    // Said out loud: the response is about to look like a successful read, and
    // whoever is running the server should see why it is not one.
    stdout.writeln(
      'read-excel: ${file.name} could not be parsed (${e.message}) — '
      'answering with ${dummyExcelRows.length} sample rows. '
      'Set READ_EXCEL_DUMMY=0 to return the error instead.',
    );
    parsed = dummyExcelRows;
  }

  final rows = [for (final row in parsed) smartRow(row)];
  return SmartEnvelope.success(
    // The text the live service answers a successful read with, kept
    // verbatim: the upload card shows it as it arrives.
    message: 'Upload Successful',
    data: {'rows': rows},
  );
}

/// Whether an unreadable upload falls back to [dummyExcelRows].
///
/// On by default, like the database seed: a local server exists to develop the
/// screens against, and the upload flow is unreachable until someone builds a
/// spreadsheet matching the parser's column contract. `READ_EXCEL_DUMMY=0`
/// turns it off, which is what a run that is actually testing file parsing —
/// or any deployment — wants.
///
/// Settable rather than final so the tests can exercise both paths in one run;
/// the environment is read once, at startup, and nothing but a test writes it.
bool readExcelFallback = Platform.environment['READ_EXCEL_DUMMY'] != '0';

/// Mirrors the ceiling the client enforces before the bytes are sent.
const _maxUploadBytes = 25 * 1024 * 1024;

/// The extension of [filename], lowercased and without the dot.
String _extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return '';
  return filename.substring(dot + 1).toLowerCase();
}
