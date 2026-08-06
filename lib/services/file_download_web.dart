import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a browser download by clicking a synthetic anchor at a blob URL.
void downloadBytes({
  required Uint8List bytes,
  required String filename,
  String mimeType = 'text/csv',
}) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;

  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Release the blob, otherwise it is held for the life of the document.
  web.URL.revokeObjectURL(url);
}
