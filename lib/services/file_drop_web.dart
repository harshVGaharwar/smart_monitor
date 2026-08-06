import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Handle returned by [listenForFileDrop]; cancelling detaches the listeners.
class FileDropSubscription {
  final List<(String, web.EventListener)> _listeners;
  const FileDropSubscription(this._listeners);

  void cancel() {
    for (final (type, listener) in _listeners) {
      web.document.removeEventListener(type, listener);
    }
  }
}

/// Routes browser file drops to a Flutter widget.
///
/// Flutter web paints into a single canvas, so there is no per-widget DOM node
/// to attach a drop target to. The listeners go on the document instead and
/// [hitTest] decides whether the pointer is over the drop zone, using CSS
/// pixels — which map 1:1 onto Flutter's logical coordinates on web.
///
/// `dragover` must have its default prevented on every event, not just those
/// over the zone: without it the browser refuses the drop and navigates to the
/// file instead.
FileDropSubscription listenForFileDrop({
  required bool Function(double x, double y) hitTest,
  required void Function(bool hovering) onHover,
  required void Function(String name, int size, Uint8List bytes) onFile,
}) {
  var hovering = false;

  void setHover(bool value) {
    if (value == hovering) return;
    hovering = value;
    onHover(value);
  }

  void onDragOver(web.Event event) {
    event.preventDefault();
    final e = event as web.MouseEvent;
    setHover(hitTest(e.clientX.toDouble(), e.clientY.toDouble()));
  }

  // Leaving the window at all clears the highlight; a drag that re-enters
  // fires dragover again immediately.
  void onDragLeave(web.Event event) {
    final e = event as web.MouseEvent;
    if (e.clientX == 0 && e.clientY == 0) setHover(false);
  }

  void onDrop(web.Event event) {
    event.preventDefault();
    final e = event as web.MouseEvent;
    final inside = hitTest(e.clientX.toDouble(), e.clientY.toDouble());
    setHover(false);
    if (!inside) return;

    final transfer = (e as web.DragEvent).dataTransfer;
    final file = transfer?.files.item(0);
    if (file == null) return;

    // Read off the event loop; the drop handler itself cannot be async.
    file.arrayBuffer().toDart.then((buffer) {
      onFile(file.name, file.size, buffer.toDart.asUint8List());
    });
  }

  final listeners = <(String, web.EventListener)>[
    ('dragover', onDragOver.toJS),
    ('dragleave', onDragLeave.toJS),
    ('drop', onDrop.toJS),
  ];
  for (final (type, listener) in listeners) {
    web.document.addEventListener(type, listener);
  }
  return FileDropSubscription(listeners);
}
