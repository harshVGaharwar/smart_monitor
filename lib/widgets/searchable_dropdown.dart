import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// A picker that opens a searchable list in an overlay anchored under the
/// field, rather than Material's menu that lands on top of it.
///
/// Every list in this app is master data — hundreds of CPUs, teams and
/// categories — so scrolling a menu to find one value does not scale. The
/// overlay leads with a search box and filters as the user types.
///
/// It replaces [DropdownButton] everywhere, so it has to cover every shape
/// those call sites had: a bare cell filter, a bordered form field, a flagged
/// cell with a warning icon in front of the value. Hence the styling
/// parameters — the widget draws the closed field, the caller says how.
class SearchableDropdown<T> extends StatefulWidget {
  final T? value;
  final List<T> options;

  /// How an option reads, in the closed field and in the list.
  final String Function(T) labelOf;

  /// Fired with the chosen option, or null when [clearLabel] is picked.
  final ValueChanged<T?> onChanged;

  /// Shown in the closed field while nothing is selected.
  final String hint;

  /// A leading entry that clears the selection — "Show all" on the column
  /// filters. Null leaves the list with no way back to an empty value, which
  /// is what the form fields want.
  final String? clearLabel;

  final TextStyle textStyle;
  final TextStyle hintStyle;

  final double iconSize;
  final Color? iconColor;

  /// Painted in front of the value, e.g. the warning on a rejected cell.
  final Widget? leading;

  /// The closed field's box. Null draws no border or fill.
  final BoxDecoration? decoration;

  final EdgeInsetsGeometry padding;
  final double height;

  final String searchHint;

  /// Widest the overlay may get. It never goes narrower than the field.
  final double menuMaxWidth;

  const SearchableDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.hint = 'Select',
    this.clearLabel,
    this.textStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
    this.hintStyle = const TextStyle(
      fontSize: 13,
      color: AppColors.textMuted,
    ),
    this.iconSize = 18,
    this.iconColor,
    this.leading,
    this.decoration,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
    this.height = 30,
    this.searchHint = 'Search…',
    this.menuMaxWidth = 340,
  });

  @override
  State<SearchableDropdown<T>> createState() => _SearchableDropdownState<T>();
}

class _SearchableDropdownState<T> extends State<SearchableDropdown<T>> {
  final LayerLink _link = LayerLink();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  OverlayEntry? _entry;

  /// Height the overlay is allowed to take, search box included. Enough for
  /// roughly six options before the list starts scrolling.
  static const double _menuMaxHeight = 296;
  static const double _rowHeight = 36;

  @override
  void dispose() {
    _remove();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The row scrolled out from under an open overlay would leave it pointing
  /// at nothing, so a table that rebuilds without this field closes it.
  @override
  void deactivate() {
    _remove();
    super.deactivate();
  }

  bool get _isOpen => _entry != null;

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  void _close() {
    if (!_isOpen) return;
    setState(_remove);
  }

  void _select(T? option) {
    _close();
    widget.onChanged(option);
  }

  void _open() {
    if (_isOpen) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final media = MediaQuery.of(context);
    final origin = box.localToGlobal(Offset.zero);
    final fieldSize = box.size;

    final width = math.min(
      math.max(fieldSize.width, 220.0),
      math.max(widget.menuMaxWidth, fieldSize.width),
    );

    // Anchored under the field by default, and flipped above it only when the
    // room below genuinely cannot hold the list.
    final below = media.size.height - media.padding.bottom - origin.dy -
        fieldSize.height;
    final above = origin.dy - media.padding.top;
    final wanted = math.min(_menuMaxHeight, _naturalHeight());
    final flip = below < wanted + 12 && above > below;
    final maxHeight = math.min(
      _menuMaxHeight,
      math.max(120.0, (flip ? above : below) - 12),
    );

    // Right-hand columns would otherwise push the overlay off the viewport,
    // so it slides back inside rather than being clipped.
    final overflow = (origin.dx + width) - (media.size.width - 8);
    final dx = overflow > 0 ? -overflow : 0.0;

    _searchCtrl.clear();

    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Anything outside the overlay dismisses it.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _close,
            ),
          ),
          Positioned(
            width: width,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: flip ? Alignment.topLeft : Alignment.bottomLeft,
              followerAnchor: flip ? Alignment.bottomLeft : Alignment.topLeft,
              offset: Offset(dx, flip ? -4 : 4),
              child: _menu(maxHeight),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_entry!);
    setState(() {});
    // The search box takes focus on open, so the user can type straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isOpen) _searchFocus.requestFocus();
    });
  }

  double _naturalHeight() {
    final count = widget.options.length + (widget.clearLabel == null ? 0 : 1);
    return 52 + count * _rowHeight + 8;
  }

  Widget _menu(double maxHeight) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
          boxShadow: AppTheme.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        constraints: BoxConstraints(maxHeight: maxHeight),
        // Rebuilt from the search box's own notifications: the overlay is not
        // a child of this state's element, so setState would not reach it.
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchCtrl,
          builder: (_, search, _) => _menuBody(search.text),
        ),
      ),
    );
  }

  Widget _menuBody(String query) {
    final q = query.trim().toLowerCase();
    final matches = [
      for (final option in widget.options)
        if (q.isEmpty || widget.labelOf(option).toLowerCase().contains(q))
          option,
    ];
    final clear = widget.clearLabel;
    final showClear =
        clear != null && (q.isEmpty || clear.toLowerCase().contains(q));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _searchField(matches),
        const Divider(height: 1, color: AppColors.border),
        Flexible(
          child: matches.isEmpty && !showClear
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'No matches',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  children: [
                    if (showClear)
                      _optionRow(
                        label: clear,
                        selected: widget.value == null,
                        onTap: () => _select(null),
                      ),
                    for (final option in matches)
                      _optionRow(
                        label: widget.labelOf(option),
                        selected: option == widget.value,
                        onTap: () => _select(option),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _searchField(List<T> matches) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          style: const TextStyle(fontSize: 13),
          textAlignVertical: TextAlignVertical.center,
          // Enter takes the first match, so a search that narrows to one
          // option does not need the mouse back.
          onSubmitted: (_) {
            if (matches.isNotEmpty) _select(matches.first);
          },
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.surfaceAlt,
            hintText: widget.searchHint,
            hintStyle: const TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 17,
              color: AppColors.textMuted,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: AppColors.primaryLight,
                width: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionRow({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: _rowHeight),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: selected ? AppColors.infoBg : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 16,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    // A value the option list no longer carries reads as unset, the same
    // guard DropdownButton needed against its "exactly one item" assertion.
    final selected = value != null && widget.options.contains(value);
    final label = selected ? widget.labelOf(value) : widget.hint;

    return CompositedTransformTarget(
      link: _link,
      child: Focus(
        onKeyEvent: (_, event) {
          if (_isOpen &&
              event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _close();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: InkWell(
          onTap: _isOpen ? _close : _open,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: widget.height,
            padding: widget.padding,
            decoration: widget.decoration,
            child: Row(
              children: [
                if (widget.leading != null) ...[
                  widget.leading!,
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: selected ? widget.textStyle : widget.hintStyle,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  _isOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: widget.iconSize,
                  color: widget.iconColor ?? AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
