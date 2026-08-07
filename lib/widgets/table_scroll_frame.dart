import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'pan_scroll_view.dart';

/// Wraps a wide table in always-visible, draggable scrollbars pinned to the
/// viewport edges, with a pinned [header] above vertically scrolling [body].
///
/// The vertical bar is mounted outside the horizontal scroll view on purpose:
/// nested inside it, the bar pans away with the content instead of staying at
/// the right-hand edge.
class TableScrollFrame extends StatelessWidget {
  /// Intrinsic width of the columns; the frame stretches to the viewport when
  /// this is narrower, so the header band spans the full card.
  final double contentWidth;

  final ScrollController horizontalController;
  final ScrollController verticalController;

  /// Stays put while [body] scrolls; must be [contentWidth] wide.
  final Widget header;

  /// The scrolling rows. Must be driven by [verticalController].
  final Widget body;

  /// Forwarded to [PanScrollView]. Tables whose cells hold dropdowns or text
  /// fields must turn this off, or a click that drifts is eaten by the pan.
  final bool mouseDrag;

  /// Shown centred in the visible area, above the rows — for the empty state.
  ///
  /// Deliberately outside the horizontal scroll view: placed inside it, this
  /// would centre itself across the full column width, which on a wide table
  /// puts it off the right-hand edge of the viewport, and it would drift as
  /// the user pans.
  final Widget? overlay;

  const TableScrollFrame({
    super.key,
    required this.contentWidth,
    required this.horizontalController,
    required this.verticalController,
    required this.header,
    required this.body,
    this.mouseDrag = true,
    this.overlay,
  });

  /// Space reserved along each edge so the bars never sit on top of cells.
  static const double _gutter = 14;
  static const double _thickness = 9;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - _gutter;
        final width = contentWidth < available ? available : contentWidth;

        final frame = ScrollbarTheme(
          data: ScrollbarThemeData(
            thickness: const WidgetStatePropertyAll(_thickness),
            radius: const Radius.circular(5),
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.dragged)
                  ? AppColors.primary
                  : (states.contains(WidgetState.hovered)
                        ? AppColors.textSecondary
                        : AppColors.borderStrong),
            ),
            trackColor: const WidgetStatePropertyAll(AppColors.surfaceAlt),
            trackBorderColor: const WidgetStatePropertyAll(AppColors.border),
          ),
          child: Scrollbar(
            controller: verticalController,
            thumbVisibility: true,
            trackVisibility: true,
            interactive: true,
            // The rows are one scrollable deeper than the horizontal pane
            // this bar is mounted around.
            notificationPredicate: (n) => n.depth == 1,
            child: Padding(
              padding: const EdgeInsets.only(right: _gutter),
              child: Scrollbar(
                controller: horizontalController,
                thumbVisibility: true,
                trackVisibility: true,
                interactive: true,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: _gutter),
                  child: PanScrollView(
                    controller: horizontalController,
                    mouseDrag: mouseDrag,
                    child: SizedBox(
                      width: width,
                      child: Column(
                        children: [
                          header,
                          Expanded(child: body),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (overlay == null) return frame;

        // Sits over the whole frame rather than the row area alone: the header
        // band is a fraction of an empty table's height, so the offset is not
        // worth threading its height through for. Hit-testing stays with the
        // frame so the scrollbars and filter row keep working underneath.
        return Stack(
          children: [
            frame,
            Positioned.fill(
              child: IgnorePointer(child: Center(child: overlay)),
            ),
          ],
        );
      },
    );
  }
}
