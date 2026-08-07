import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../data/mock_data.dart';
import '../models/pending_case.dart';
import 'searchable_dropdown.dart';
import 'table_scroll_frame.dart';

/// How a column renders. The four validated kinds show plain text while the
/// value resolves and turn into a red, still-editable dropdown when it does
/// not.
enum _CellKind {
  text,
  client,
  delete,
  cpu,
  team,
  exception,
  healthCheck,
  reason,
}

class _Col {
  final String label;
  final double width;
  final _CellKind kind;

  final String Function(PendingCase) value;

  const _Col({
    required this.label,
    required this.width,
    required this.value,
    this.kind = _CellKind.text,
  });

  /// Free-text and routing pickers have nothing useful to filter on. The
  /// health check category is validated but still the natural way to slice the
  /// report, so it keeps its filter.
  bool get filterable =>
      kind == _CellKind.text || kind == _CellKind.healthCheck;
}

/// The validation report: every row the file contained, with cells the master
/// data did not recognise flagged in red and editable in place.
class ValidationResultsTable extends StatefulWidget {
  final List<PendingCase> rows;

  /// Error rows the user ticked, for the parent's "Download Error Data".
  final ValueChanged<Set<PendingCase>>? onSelectionChanged;

  /// Fired whenever an edit changes a row's validity, so the parent's counts
  /// can follow along.
  final VoidCallback? onRowsChanged;

  /// A row the user removed with its own delete button. The parent owns
  /// [rows], so it does the removing; the table only drops its own state for
  /// that row afterwards.
  final ValueChanged<PendingCase>? onDeleteRow;

  const ValidationResultsTable({
    super.key,
    required this.rows,
    this.onSelectionChanged,
    this.onRowsChanged,
    this.onDeleteRow,
  });

  @override
  State<ValidationResultsTable> createState() => _ValidationResultsTableState();
}

class _ValidationResultsTableState extends State<ValidationResultsTable> {
  static const double _rowPadding = 10;
  static const double _checkboxWidth = 44;

  /// Height of the inline dropdown editors, sized so a row carrying controls
  /// matches the height of a plain text row.
  static const double _controlHeight = 28;

  /// The reason field is taller than the dropdowns on purpose: it is the one
  /// cell the user types free text into, and it appears on every row, so the
  /// extra height costs no parity between clean and flagged rows.
  static const double _reasonHeight = 38;

  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  /// Reason inputs, keyed by row identity so edits survive re-filtering.
  final Map<PendingCase, TextEditingController> _reasonCtrls = {};

  final Set<PendingCase> _selected = {};
  final Map<String, String> _filters = {};
  int _pageSize = 10;
  int _page = 0;

  /// File order, with the three validated columns last so the cells the user
  /// has to act on sit together at the end of the row.
  ///
  /// The delete button leads rather than trailing: the row is nearly 3000px
  /// wide, so an action column at the far end would need a full scroll right
  /// to reach.
  late final List<_Col> _cols = [
    _Col(label: '', width: 46, kind: _CellKind.delete, value: (_) => ''),
    _Col(
      label: 'CLIENT ID',
      width: 125,
      kind: _CellKind.client,
      value: (r) => r.clientId,
    ),
    _Col(label: 'CUSTOMER NAME', width: 190, value: (r) => r.customerName),
    _Col(label: 'ACCOUNT NO', width: 150, value: (r) => r.accountNo),
    _Col(label: 'LINE NO', width: 105, value: (r) => r.lineNo),
    _Col(
      label: 'HEALTH CHECK CATEGORY',
      width: 200,
      kind: _CellKind.healthCheck,
      value: (r) => r.healthCheckCategory,
    ),
    _Col(label: 'SUB CATEGORY', width: 190, value: (r) => r.subCategory),
    _Col(label: 'SUPPORT SYSTEM', width: 160, value: (r) => r.supportSystem),
    _Col(label: 'CORE SYSTEM', width: 160, value: (r) => r.coreSystem),
    _Col(label: 'SEGMENT', width: 140, value: (r) => r.segment),
    _Col(label: 'FACILITY SR. NO', width: 150, value: (r) => r.facilitySrNo),
    _Col(label: 'MAKER', width: 130, value: (r) => r.maker),
    _Col(label: 'CHECKER', width: 120, value: (r) => r.checker),
    _Col(label: 'LS SRM DATE', width: 140, value: (r) => r.lsSrmDate),
    _Col(
      label: 'EXCEPTION CATEGORY',
      width: 200,
      kind: _CellKind.exception,
      value: (r) => r.exceptionCategory,
    ),
    _Col(
      label: 'REASON',
      width: 320,
      kind: _CellKind.reason,
      value: (r) => r.reason,
    ),
    _Col(
      label: 'CPU',
      width: 160,
      kind: _CellKind.cpu,
      value: (r) => r.cpuDisplay,
    ),
    _Col(
      label: 'ACTIONABLE TEAM',
      width: 215,
      kind: _CellKind.team,
      value: (r) => r.teamDisplay,
    ),
  ];

  double get _totalWidth =>
      _cols.fold(0.0, (sum, c) => sum + c.width) +
      _checkboxWidth +
      _rowPadding * 2;

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    for (final ctrl in _reasonCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  TextEditingController _reasonController(PendingCase r) =>
      _reasonCtrls.putIfAbsent(r, () => TextEditingController(text: r.reason));

  List<PendingCase> get _filtered {
    return widget.rows.where((r) {
      for (final col in _cols) {
        final selected = _filters[col.label];
        if (selected != null && col.value(r) != selected) return false;
      }
      return true;
    }).toList();
  }

  /// Only the master categories. Offering the file's own rejected values here
  /// would let the user "fix" a cell by picking the very value that failed —
  /// the rejected text is shown through the closed button's hint instead.
  List<String> get _exceptionOptions => MockData.exceptionCategories;

  List<String> _optionsFor(_Col col) {
    final set = <String>{for (final r in widget.rows) col.value(r)};
    return set.where((v) => v.isNotEmpty).toList()..sort();
  }

  /// Re-checks validity after an inline edit and lets the parent's stats strip
  /// follow.
  ///
  /// A tick survives the row turning clean. Correcting a flagged row is
  /// precisely when the user wants it in the submit, so dropping the
  /// selection there would undo the thing they just did.
  void _rowEdited() {
    setState(() {});
    widget.onRowsChanged?.call();
    widget.onSelectionChanged?.call({..._selected});
  }

  void _toggle(PendingCase r, bool on) {
    setState(() => on ? _selected.add(r) : _selected.remove(r));
    widget.onSelectionChanged?.call({..._selected});
  }

  /// Hands a single row to the parent for removal. No confirmation prompt —
  /// the snackbar the parent raises carries an undo instead, which is cheaper
  /// than a dialog on every row.
  void _deleteRow(PendingCase r) {
    // Safe to drop: the text lives on the row itself, so an undo rebuilds the
    // controller from it.
    _reasonCtrls.remove(r)?.dispose();
    setState(() => _selected.remove(r));
    widget.onDeleteRow?.call(r);
    widget.onSelectionChanged?.call({..._selected});
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 9999);
    // Clamped for display only — [_page] keeps the page the user actually
    // asked for. Writing the clamp back would forget it: deleting the last row
    // on the last page collapses the page count, and an undo would then return
    // the row to a page the table has already navigated away from.
    //
    // Clamping here also absorbs two pager taps landing in the same frame,
    // since both compute from this value rather than stepping _page twice.
    final page = _page.clamp(0, totalPages - 1);
    final start = page * _pageSize;
    final end = (start + _pageSize).clamp(0, filtered.length);
    final pageRows = filtered.sublist(start, end);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppTheme.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: TableScrollFrame(
              contentWidth: _totalWidth,
              horizontalController: _hScroll,
              verticalController: _vScroll,
              // Nearly every cell here is a dropdown or a text field, and a
              // mouse pan would eat their clicks. Panning stays on the
              // scrollbar, the wheel and trackpad swipes.
              mouseDrag: false,
              header: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _headerRow(pageRows),
                  _filterRow(),
                  const Divider(height: 1, color: AppColors.border),
                ],
              ),
              body: _body(pageRows),
              overlay: pageRows.isEmpty
                  ? const Text(
                      'No rows match the current filters.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    )
                  : null,
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _footer(filtered.length, start, end, page, totalPages),
        ],
      ),
    );
  }

  // --- Header + filters ---------------------------------------------------

  Widget _headerRow(List<PendingCase> pageRows) {
    // Covers the page the user is looking at, clean rows included — ticking
    // through to a submit is the common path, not just picking error rows.
    final allSelected =
        pageRows.isNotEmpty && pageRows.every(_selected.contains);

    return Container(
      height: 44,
      color: AppColors.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: _rowPadding),
      child: Row(
        children: [
          SizedBox(
            width: _checkboxWidth,
            child: _checkbox(
              value: allSelected,
              onChanged: pageRows.isEmpty
                  ? null
                  : (v) {
                      setState(() {
                        if (v ?? false) {
                          _selected.addAll(pageRows);
                        } else {
                          _selected.removeAll(pageRows);
                        }
                      });
                      widget.onSelectionChanged?.call({..._selected});
                    },
            ),
          ),
          for (final col in _cols)
            SizedBox(
              width: col.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    col.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: _filters.containsKey(col.label)
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _checkbox({
    required bool value,
    required ValueChanged<bool?>? onChanged,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 20,
        height: 20,
        child: Checkbox(
          value: value,
          onChanged: onChanged,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: const BorderSide(color: AppColors.borderStrong, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  Widget _filterRow() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: _rowPadding, vertical: 7),
      child: Row(
        children: [
          const SizedBox(width: _checkboxWidth),
          for (final col in _cols)
            SizedBox(
              width: col.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: col.filterable
                    ? _filterDropdown(col)
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterDropdown(_Col col) {
    return SearchableDropdown<String>(
      // Editing a flagged cell can retire the value a filter is pinned to;
      // the field reads as unset until that value is back on a row.
      value: _filters[col.label],
      options: _optionsFor(col),
      labelOf: (v) => v,
      hint: 'Show all',
      clearLabel: 'Show all',
      searchHint: 'Search ${col.label.toLowerCase()}…',
      iconSize: 17,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      textStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      hintStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      onChanged: (v) => setState(() {
        if (v == null) {
          _filters.remove(col.label);
        } else {
          _filters[col.label] = v;
        }
        _page = 0;
      }),
    );
  }

  // --- Body ---------------------------------------------------------------

  Widget _body(List<PendingCase> rows) {
    if (rows.isEmpty) {
      // Still a scroll view: the frame's scrollbar needs a live position on
      // [_vScroll], and an empty state would otherwise leave it unattached.
      // The message itself is the frame's overlay, so that it centres on the
      // viewport rather than on the full width of the columns.
      return ListView(controller: _vScroll, children: const [SizedBox()]);
    }

    // The vertical scrollbar lives in TableScrollFrame, pinned to the card's
    // right edge rather than riding along with the horizontal pan.
    return ListView.separated(
      controller: _vScroll,
      itemCount: rows.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) => _dataRow(rows[i]),
    );
  }

  Widget _dataRow(PendingCase r) {
    final flagged = r.hasErrors;
    return Container(
      // A faint wash marks the whole row so an error is findable without
      // scrolling sideways to the offending column.
      color: flagged
          ? AppColors.dangerBg.withValues(alpha: 0.45)
          : AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: _rowPadding, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: _checkboxWidth,
            // Every row carries a box: the ticks drive the submit as well as
            // the error export, so a row must stay selectable after the user
            // corrects it — that is the point at which they want to send it.
            child: _checkbox(
              value: _selected.contains(r),
              onChanged: (v) => _toggle(r, v ?? false),
            ),
          ),
          for (final col in _cols)
            SizedBox(
              width: col.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _cell(col, r),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(_Col col, PendingCase r) {
    switch (col.kind) {
      case _CellKind.delete:
        return _deleteButton(r);

      case _CellKind.text:
        return _plain(col.value(r));

      case _CellKind.client:
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            col.value(r).isEmpty ? '—' : col.value(r),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryLight,
            ),
          ),
        );

      case _CellKind.cpu:
        return _validated(
          valid: r.cpuValid,
          display: r.cpuDisplay,
          value: r.cpu,
          options: MockData.cpus,
          onChanged: (v) {
            r.cpu = v;
            _rowEdited();
          },
        );

      case _CellKind.team:
        return _validated(
          valid: r.teamValid,
          display: r.teamDisplay,
          value: r.actionableTeam,
          options: MockData.teams,
          onChanged: (v) {
            r.actionableTeam = v;
            _rowEdited();
          },
        );

      case _CellKind.healthCheck:
        return _validated(
          valid: r.healthCheckValid,
          display: r.healthCheckCategory,
          value: r.healthCheckCategory.trim().isEmpty
              ? null
              : r.healthCheckCategory,
          options: MockData.healthCheckCategories,
          onChanged: (v) {
            r.healthCheckCategory = v ?? '';
            _rowEdited();
          },
        );

      case _CellKind.exception:
        return _validated(
          valid: r.exceptionValid,
          display: r.exceptionCategory,
          value: r.exceptionCategory.trim().isEmpty
              ? null
              : r.exceptionCategory,
          options: _exceptionOptions,
          onChanged: (v) {
            r.exceptionCategory = v ?? '';
            _rowEdited();
          },
        );

      case _CellKind.reason:
        return SizedBox(
          height: _reasonHeight,
          child: TextField(
            controller: _reasonController(r),
            style: const TextStyle(fontSize: 13),
            onChanged: (v) => r.reason = v,
            // The text sits mid-field rather than riding the top edge once the
            // box is taller than one line of type.
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 10,
              ),
              hintText: 'Reason',
              hintStyle: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: AppColors.primaryLight,
                  width: 1.4,
                ),
              ),
            ),
          ),
        );
    }
  }

  /// The row's own remove control. Sized to the dropdown height so it does not
  /// stretch the row it sits in.
  Widget _deleteButton(PendingCase r) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: 'Remove this row from the upload',
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _deleteRow(r),
            child: const SizedBox(
              width: _controlHeight,
              height: _controlHeight,
              child: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppColors.danger,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _plain(String text, {Color color = AppColors.textSecondary}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: text,
        waitDuration: const Duration(milliseconds: 600),
        child: Text(
          text.isEmpty ? '—' : text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: text.isEmpty ? AppColors.textMuted : color,
          ),
        ),
      ),
    );
  }

  /// One of the four master-data columns. Always a picker, never plain text:
  /// the reviewer changes these on rows the file got right as often as on the
  /// ones it got wrong. A rejected value keeps the file's wording and turns the
  /// control red, but the control itself is the same either way.
  Widget _validated({
    required bool valid,
    required String display,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final accent = valid ? AppColors.textPrimary : AppColors.danger;

    return SearchableDropdown<String>(
      // A value the master list does not carry reads as unset, so the
      // rejected text shows through the hint instead of being offered back.
      value: value,
      options: options,
      labelOf: (v) => v,
      hint: display.isEmpty ? 'Select' : display,
      searchHint: 'Search…',
      height: _controlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: valid ? AppColors.surface : AppColors.dangerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: valid
              ? AppColors.border
              : AppColors.danger.withValues(alpha: 0.45),
        ),
      ),
      leading: valid
          ? null
          : const Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: AppColors.danger,
            ),
      iconSize: 16,
      iconColor: valid ? AppColors.textMuted : AppColors.danger,
      textStyle: TextStyle(
        fontSize: 12,
        fontWeight: valid ? FontWeight.w500 : FontWeight.w600,
        color: accent,
      ),
      hintStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: accent,
      ),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  // --- Footer -------------------------------------------------------------

  Widget _footer(int total, int start, int end, int page, int totalPages) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      // Count on the left, pager on the right; the pager drops to its own line
      // when a phone-width footer cannot hold both.
      child: Wrap(
        spacing: 14,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                total == 0 ? 'No rows' : 'Showing ${start + 1}–$end of $total',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              if (_selected.isNotEmpty) ...[
                const SizedBox(width: 14),
                Text(
                  '${_selected.length} selected',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _entriesSelector(),
              const SizedBox(width: 14),
              _pageBtn(
                icon: Icons.chevron_left_rounded,
                enabled: page > 0,
                // Assigns rather than steps, so the displayed page is always
                // what moves — see the clamp in build.
                onTap: () => setState(() => _page = page - 1),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    '${page + 1} / $totalPages',
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _pageBtn(
                icon: Icons.chevron_right_rounded,
                enabled: page < totalPages - 1,
                onTap: () => setState(() => _page = page + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _entriesSelector() {
    return SizedBox(
      width: 108,
      child: SearchableDropdown<int>(
        value: _pageSize,
        options: const [10, 25, 50],
        labelOf: (n) => '$n / page',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        onChanged: (v) => setState(() {
          _pageSize = v ?? 10;
          _page = 0;
        }),
      ),
    );
  }

  Widget _pageBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: enabled ? AppColors.surface : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(
            icon,
            size: 19,
            color: enabled ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
