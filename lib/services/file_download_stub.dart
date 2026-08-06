import 'dart:typed_data';

/// No-op fallback for platforms without a browser download mechanism.
///
/// Reached by the VM (tests) and by any native build; a native target should
/// write to disk with path_provider and open the file instead.
void downloadBytes({
  required Uint8List bytes,
  required String filename,
  String mimeType = 'text/csv',
}) {
  // Intentionally empty: callers treat the download as fire-and-forget.
}
