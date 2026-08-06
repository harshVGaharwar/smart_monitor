import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A horizontally scrolling view that can also be panned by dragging with a
/// mouse.
///
/// Flutter only accepts drag gestures from touch input by default, so on the
/// desktop web build a wide table is reachable only via a horizontal wheel,
/// a trackpad swipe or the scrollbar thumb. Adding mouse to [dragDevices]
/// makes click-and-drag work too.
///
/// The catch is that Flutter resolves a mouse drag after only 2px of movement,
/// and the winning drag cancels the tap underneath it. A table whose cells hold
/// dropdowns or text fields must therefore pass [mouseDrag] as false, or those
/// controls swallow any click that drifts even slightly — see
/// [ValidationResultsTable]. Wrapping the control in its own drag recogniser
/// does not help: it changes which drag wins, not the fact that a drag won.
class PanScrollView extends StatelessWidget {
  final ScrollController controller;
  final Widget child;

  /// Whether click-and-drag pans the view. Turn it off for tables with inline
  /// editors; the scrollbar, wheel and trackpad still scroll them.
  final bool mouseDrag;

  const PanScrollView({
    super.key,
    required this.controller,
    required this.child,
    this.mouseDrag = true,
  });

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          if (mouseDrag) PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
        // Scrollbars are supplied explicitly by the tables.
        scrollbars: false,
      ),
      child: SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        child: child,
      ),
    );
  }
}
