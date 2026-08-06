import 'dart:typed_data';

import 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart'
    as impl;

/// Hands [bytes] to the platform as a file download.
///
/// Conditional import: the web implementation touches browser APIs that do not
/// compile on the VM, so tests and any future native build get the stub.
void downloadBytes({
  required Uint8List bytes,
  required String filename,
  String mimeType = 'text/csv',
}) => impl.downloadBytes(bytes: bytes, filename: filename, mimeType: mimeType);
