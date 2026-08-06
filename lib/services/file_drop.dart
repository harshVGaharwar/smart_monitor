import 'dart:typed_data';

import 'file_drop_stub.dart'
    if (dart.library.js_interop) 'file_drop_web.dart'
    as impl;

export 'file_drop_stub.dart'
    if (dart.library.js_interop) 'file_drop_web.dart'
    show FileDropSubscription;

/// Listens for a file dragged onto the page and hands it to [onFile].
///
/// Conditional import, matching `file_download.dart`: the web implementation
/// touches browser APIs that do not compile on the VM, so tests and any future
/// native build get an inert stub.
///
/// [hitTest] receives viewport coordinates and decides whether the pointer is
/// over the drop zone, so the caller keeps control of what counts as a target.
impl.FileDropSubscription listenForFileDrop({
  required bool Function(double x, double y) hitTest,
  required void Function(bool hovering) onHover,
  required void Function(String name, int size, Uint8List bytes) onFile,
}) =>
    impl.listenForFileDrop(hitTest: hitTest, onHover: onHover, onFile: onFile);
