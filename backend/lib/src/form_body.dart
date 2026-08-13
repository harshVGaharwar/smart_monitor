import 'package:dart_frog/dart_frog.dart';

/// The values a posted request carried, and the name of the file with them.
typedef PostedBody = ({Map<String, dynamic> fields, String supportDocument});

/// Reads a body that may be JSON or multipart.
///
/// Two shapes, because a note can carry a file: JSON on its own, multipart
/// when `supportDocument` rides along. The values are the same either way, so
/// only the reading of them differs — and a route that takes both should not
/// have to say so twice.
///
/// [fileField] is the multipart key the file rides under — `supportDocument`
/// on a comment, `document` on a reassignment.
///
/// Null when the body could not be read at all, which the caller answers as a
/// bad request in its own words.
Future<PostedBody?> readPostedBody(
  Request request, {
  String fileField = 'supportDocument',
}) async {
  if (_isMultipart(request)) {
    try {
      final form = await request.formData();
      return (
        fields: <String, dynamic>{...form.fields},
        // Only the name: this stub has nowhere to serve bytes back from.
        supportDocument: form.files[fileField]?.name ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  final dynamic payload;
  try {
    payload = await request.json();
  } catch (_) {
    return null;
  }
  return (
    fields:
        payload is Map
            ? Map<String, dynamic>.from(payload)
            : <String, dynamic>{},
    supportDocument: '',
  );
}

/// Whether the request carries a multipart form rather than a JSON body.
bool _isMultipart(Request request) {
  final type = request.headers['content-type'] ?? '';
  return type.toLowerCase().contains('multipart/form-data');
}
