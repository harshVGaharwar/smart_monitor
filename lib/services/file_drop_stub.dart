import 'dart:typed_data';

/// Handle returned by [listenForFileDrop]; cancelling detaches the listeners.
class FileDropSubscription {
  const FileDropSubscription();
  void cancel() {}
}

/// No-op away from the browser: there is no OS-level drag source to listen to,
/// so the widget simply never sees a hover or a drop.
FileDropSubscription listenForFileDrop({
  required bool Function(double x, double y) hitTest,
  required void Function(bool hovering) onHover,
  required void Function(String name, int size, Uint8List bytes) onFile,
}) => const FileDropSubscription();
