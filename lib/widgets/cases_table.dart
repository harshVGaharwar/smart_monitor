import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/case_item.dart';
import 'case_detail_panel.dart';
import 'searchable_dropdown.dart';
import 'status_badge.dart';
import 'table_scroll_frame.dart';

/// Which column a sort is keyed on.
enum _SortKey {
  client,
  description,
  reason,
  cpu,
  team,
  date,
  lastMessage,
  customer,
  account,
  lineNo,
  subCategory,
  supportSystem,
  coreSystem,
}

class _Col {
  final String label;
  final double width;
  final _SortKey? sort;

  /// The text this column filters on. Columns whose every row reads
  /// differently — the last message — or that carry a count rather than a
  /// value leave it null and get no filter dropdown.
  final String Function(CaseItem)? value;

  /// How the column paints a row. Held here so the list below is the only
  /// place column order is written down — heading, filter and cell all follow
  /// it, and reordering cannot leave a cell under the wrong heading.
  final Widget Function(CaseItem) cell;

  const _Col({
    required this.label,
    required this.width,
    required this.cell,
    this.sort,
    this.value,
    this.options,
  });

  /// The filter's options, when listing them alphabetically would be wrong.
  /// Dates are the case: `05 Aug` sorting before `21 Jul` reads as a bug.
  final List<String> Function(List<CaseItem>)? options;

  bool get filterable => value != null;
}

/// The dashboard record grid.
class CasesTable extends StatefulWidget {
  final List<CaseItem> cases;

  /// Opens the detail drawer for a record, on a specific tab.
  final void Function(CaseItem, CaseDetailTab) onOpenCase;

  /// The tabs the drawer will offer, from [tabsFor]. A row action that opens a
  /// tab this reader does not have would land them on Basic Info instead, so
  /// the icon is left out rather than shown doing nothing.
  final List<CaseDetailTab> tabs;

  /// Whether the per-row checkbox is offered — the "tick in dashboard" right.
  final bool canTick;

  const CasesTable({
    super.key,
    required this.cases,
    required this.onOpenCase,
    required this.tabs,
    required this.canTick,
  });

  @override
  State<CasesTable> createState() => _CasesTableState();
}

class _CasesTableState extends State<CasesTable> {
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  final Set<String> _selected = {};

  /// Selected filter per column label; absent means "Show all".
  final Map<String, String> _filters = {};

  _SortKey _sortKey = _SortKey.client;
  bool _sortAsc = true;
  final int _pageSize = 10;
  int _page = 0;

  static const double _rowPadding = 12;
  static const double _actionsWidth = 132;
  static const double _checkboxWidth = 52;

  /// Who the record is, then who owns it, then what is wrong with it: client,
  /// customer and CPU lead so a reader can identify a row before scrolling
  /// into the detail columns.
  late final List<_Col> _cols = [
    _Col(
      label: 'CLIENT ID',
      width: 130,
      sort: _SortKey.client,
      // Filterable like the rest: a client with several exceptions across
      // categories is the one slice a reader most often wants, and reaching
      // for the search box to get it means retyping the id on every visit.
      value: (c) => c.clientId,
      cell: _clientCell,
    ),
    _Col(
      label: 'CUSTOMER NAME',
      width: 180,
      sort: _SortKey.customer,
      value: (c) => c.customerName,
      cell: (c) => _strong(c.customerName),
    ),
    _Col(
      label: 'CPU',
      width: 140,
      sort: _SortKey.cpu,
      value: (c) => c.cpu,
      cell: (c) => _strong(c.cpu),
    ),
    // The check that raised the record, and beside it what actually failed.
    // One column carried both until reason got its own: the check is the
    // slice a reader filters by, the reason is the sentence they read, and
    // pairing them meant the filter offered a different set per row.
    _Col(
      label: 'DESCRIPTION',
      width: 240,
      sort: _SortKey.description,
      value: (c) => c.healthCheckCategory,
      cell: _descriptionCell,
    ),
    _Col(
      label: 'REASON',
      width: 280,
      sort: _SortKey.reason,
      value: (c) => c.reason,
      cell: _reasonCell,
    ),
    _Col(
      label: 'TEAM',
      width: 150,
      sort: _SortKey.team,
      value: (c) => c.team,
      cell: (c) => _plain(c.team),
    ),
    _Col(
      label: 'STATUS',
      width: 150,
      value: _statusLabel,
      cell:
          (c) => Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(status: c.status),
          ),
    ),
    _Col(
      label: 'DATE',
      width: 130,
      sort: _SortKey.date,
      // Filters on the text the cell shows, so picking an option and reading
      // the column agree. Ordered by the date behind it rather than by that
      // text — see [_Col.options].
      value: (c) => _date(_rowDate(c)),
      options: _dateOptions,
      cell: _dateCell,
    ),
    _Col(label: 'MESSAGE', width: 120, cell: _messageCell),
    _Col(
      label: 'LAST MESSAGE',
      width: 220,
      sort: _SortKey.lastMessage,
      cell: _lastMessageCell,
    ),
    _Col(
      label: 'ACCOUNT NO',
      width: 150,
      sort: _SortKey.account,
      value: (c) => c.accountNo,
      cell: (c) => _strong(c.accountNo),
    ),
    _Col(
      label: 'LINE NO',
      width: 110,
      sort: _SortKey.lineNo,
      value: (c) => c.lineNo,
      cell: (c) => _plain(c.lineNo),
    ),
    _Col(
      label: 'SUB CATEGORY',
      width: 180,
      sort: _SortKey.subCategory,
      value: (c) => c.subCategory,
      cell: (c) => _plain(c.subCategory),
    ),
    _Col(
      label: 'SUPPORT SYSTEM',
      width: 160,
      sort: _SortKey.supportSystem,
      value: (c) => c.supportSystem,
      cell: (c) => _plain(c.supportSystem),
    ),
    _Col(
      label: 'CORE SYSTEM',
      width: 160,
      sort: _SortKey.coreSystem,
      value: (c) => c.coreSystem,
      cell: (c) => _plain(c.coreSystem),
    ),
  ];

  double get _totalWidth =>
      // Dropped along with the column, or every row would carry 52px of empty
      // gutter and scroll further than it has content for.
      (widget.canTick ? _checkboxWidth : 0) +
      _cols.fold(0.0, (sum, c) => sum + c.width) +
      _actionsWidth +
      _rowPadding * 2;

  @override
  void didUpdateWidget(CasesTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reload can drop rows the user had ticked. Their codes would otherwise
    // sit in the set for good, counted in the footer with nothing on screen to
    // untick them by.
    if (!identical(oldWidget.cases, widget.cases)) _pruneSelection();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  /// Drops selections for rows the filters no longer show.
  ///
  /// Selection is scoped to what is currently on offer, not to every row the
  /// page has ever handed over: a tick the user cannot see is one they cannot
  /// clear, and it would go on inflating the count — and travel into whatever
  /// a bulk action does next — from behind a filter they have since changed.
  /// Paging is deliberately not part of that: the other pages of the same
  /// filtered set are still reachable without touching a filter.
  void _pruneSelection() {
    if (_selected.isEmpty) return;
    final visible = {for (final c in _filtered) c.exceptionCode};
    _selected.removeWhere((code) => !visible.contains(code));
  }

  /// The rows left after the column filters, before sorting.
  List<CaseItem> get _filtered {
    if (_filters.isEmpty) return widget.cases;
    return widget.cases.where((c) {
      for (final col in _cols) {
        final selected = _filters[col.label];
        if (selected != null && col.value!(c) != selected) return false;
      }
      return true;
    }).toList();
  }

  /// What the STATUS filter slices on — the record's own status, the same
  /// text the badge shows, so picking a value in the dropdown selects exactly
  /// the rows displaying it.
  static String _statusLabel(CaseItem c) => c.status.label;

  /// Distinct values for a column, so a filter never offers a choice that
  /// would yield nothing. Read from every row the page handed over, not from
  /// [_filtered] — a dropdown that shed its options as soon as a sibling
  /// filter was set would be a one-way trip.
  ///
  /// STATUS is derived like the rest: the rows arrive as one user's queue, so
  /// the statuses present are the statuses that can be here. A fixed list of
  /// the workflow's own buckets would offer the other side's, which behind
  /// this grid could only ever come back empty.
  List<String> _optionsFor(_Col col) {
    final build = col.options;
    if (build != null) return build(widget.cases);

    final present = <String>{for (final c in widget.cases) col.value!(c)}
      ..removeWhere((v) => v.isEmpty);
    return present.toList()..sort();
  }

  /// The dates on screen, newest first.
  ///
  /// Ordered on the [DateTime] and formatted afterwards: the cell's text sorts
  /// alphabetically, which would put every August before every July. Rows
  /// carrying no date are left out — there is nothing to filter them by.
  static List<String> _dateOptions(List<CaseItem> cases) {
    final dates = <DateTime>[
      for (final c in cases)
        if (_rowDate(c) case final d?) d,
    ]..sort((a, b) => b.compareTo(a));

    // Two stamps on the same day read as one option, and the first wins so the
    // order above is kept.
    return <String>{for (final d in dates) _date(d)}.toList();
  }

  List<CaseItem> get _sorted {
    String keyOf(CaseItem c) => switch (_sortKey) {
      _SortKey.client => c.clientId,
      _SortKey.description => c.healthCheckCategory,
      _SortKey.reason => c.reason,
      _SortKey.cpu => c.cpu,
      _SortKey.team => c.team,
      _SortKey.date => '',
      _SortKey.lastMessage => c.updatedNote,
      _SortKey.customer => c.customerName,
      _SortKey.account => c.accountNo,
      _SortKey.lineNo => c.lineNo,
      _SortKey.subCategory => c.subCategory,
      _SortKey.supportSystem => c.supportSystem,
      _SortKey.coreSystem => c.coreSystem,
    };

    final list = [..._filtered];
    list.sort((a, b) {
      // Client and account read as numbers to the user, so sort them that way;
      // the date column sorts chronologically rather than by its printed form.
      final r = switch (_sortKey) {
        _SortKey.client || _SortKey.account => (int.tryParse(keyOf(a)) ?? 0)
            .compareTo(int.tryParse(keyOf(b)) ?? 0),
        // Records without a date sort to the bottom of the ascending list.
        _SortKey.date => (_rowDate(a) ?? DateTime(0)).compareTo(
          _rowDate(b) ?? DateTime(0),
        ),
        _ => keyOf(a).toLowerCase().compareTo(keyOf(b).toLowerCase()),
      };
      return _sortAsc ? r : -r;
    });
    return list;
  }

  /// The Date column: when the record last moved, falling back to when it was
  /// assigned and then to the LS/RM date.
  static DateTime? _rowDate(CaseItem c) =>
      c.updatedAt ?? c.assignedDate ?? c.lsrmDate;

  void _onSort(_SortKey key) => setState(() {
    if (_sortKey == key) {
      _sortAsc = !_sortAsc;
    } else {
      _sortKey = key;
      _sortAsc = true;
    }
  });

  @override
  Widget build(BuildContext context) {
    final rows = _sorted;
    final totalPages = (rows.length / _pageSize).ceil().clamp(1, 9999);
    // Clamped both ways: two taps landing in the same frame both see the
    // previous frame's enabled flag, so the page index can overshoot either
    // end before this rebuild runs.
    _page = _page.clamp(0, totalPages - 1);
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, rows.length);
    final pageRows = rows.sublist(start, end);

    return Column(
      children: [
        Expanded(
          child: TableScrollFrame(
            contentWidth: _totalWidth,
            horizontalController: _hScroll,
            verticalController: _vScroll,
            // The filter row holds dropdowns, and a mouse pan would eat the
            // clicks that open them. Panning stays on the scrollbar, the wheel
            // and trackpad swipes — same trade the upload table makes.
            mouseDrag: false,
            header: _headerRow(rows),
            body: _body(pageRows),
            overlay:
                pageRows.isEmpty
                    ? const Text(
                      'No records match the current filters.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    )
                    : null,
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        _footer(rows.length, start, end, totalPages),
      ],
    );
  }

  // --- Header -------------------------------------------------------------

  Widget _headerRow(List<CaseItem> rows) {
    // Governs everything the filters currently show, not just the ten on
    // screen: a box that ticked one page at a time left the rest selected
    // behind the pager, where unticking it could not reach them.
    final allSelected =
        rows.isNotEmpty &&
        rows.every((c) => _selected.contains(c.exceptionCode));
    // Tristate so a part-selected grid does not read as an empty one, which is
    // what made a single row's tick look like it had done nothing.
    final anySelected = rows.any((c) => _selected.contains(c.exceptionCode));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 46,
          color: AppColors.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: _rowPadding),
          child: Row(
            children: [
              // Left out entirely, not disabled: a column of dead boxes reads
              // as a broken grid rather than as a right this reader lacks.
              if (widget.canTick)
                SizedBox(
                  width: _checkboxWidth,
                  child: _checkbox(
                    value: allSelected ? true : (anySelected ? null : false),
                    tristate: true,
                    onChanged:
                        (v) => setState(() {
                          // Null is the indeterminate leg of the cycle; from there
                          // the useful move is to finish selecting, not to clear.
                          if (v ?? false) {
                            _selected.addAll(rows.map((c) => c.exceptionCode));
                          } else {
                            _selected.removeAll(
                              rows.map((c) => c.exceptionCode),
                            );
                          }
                        }),
                  ),
                ),
              for (final col in _cols)
                SizedBox(width: col.width, child: _headerCell(col)),
              const SizedBox(
                width: _actionsWidth,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'ACTIONS',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _filterRow(),
        const Divider(height: 1, color: AppColors.border),
      ],
    );
  }

  /// A "Show all" picker under each column that has a fixed set of values, so
  /// the grid can be sliced without leaving it for the header above.
  Widget _filterRow() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: _rowPadding, vertical: 7),
      child: Row(
        children: [
          // Aligns the filters under their headings, so it goes when the tick
          // column does.
          if (widget.canTick) const SizedBox(width: _checkboxWidth),
          for (final col in _cols)
            SizedBox(
              width: col.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child:
                    col.filterable
                        ? _filterDropdown(col)
                        : const SizedBox.shrink(),
              ),
            ),
          const SizedBox(width: _actionsWidth),
        ],
      ),
    );
  }

  Widget _filterDropdown(_Col col) {
    return SearchableDropdown<String>(
      // A filter can be left pinned to a value no row carries any more — the
      // page's own search narrows what reaches this table — and the dropdown
      // shows it as unset until it comes back.
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
      onChanged:
          (v) => setState(() {
            if (v == null) {
              _filters.remove(col.label);
            } else {
              _filters[col.label] = v;
            }
            _page = 0;
            _pruneSelection();
          }),
    );
  }

  Widget _headerCell(_Col col) {
    final active = col.sort != null && col.sort == _sortKey;
    // A filtered column reads as active too: its dropdown sits a row below and
    // scrolls out of view on a grid this wide.
    final lit = active || _filters.containsKey(col.label);
    final label = Text(
      col.label,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: lit ? AppColors.textPrimary : AppColors.textSecondary,
      ),
    );

    if (col.sort == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Align(alignment: Alignment.centerLeft, child: label),
      );
    }

    return InkWell(
      onTap: () => _onSort(col.sort!),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            Flexible(child: label),
            const SizedBox(width: 4),
            Icon(
              active
                  ? (_sortAsc
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded)
                  : Icons.unfold_more_rounded,
              size: 13,
              color: active ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkbox({
    required bool? value,
    required ValueChanged<bool?> onChanged,
    bool tristate = false,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 24,
        height: 24,
        child: Checkbox(
          value: value,
          tristate: tristate,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          activeColor: AppColors.primary,
          side: const BorderSide(color: AppColors.borderStrong, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // --- Body ---------------------------------------------------------------

  Widget _body(List<CaseItem> rows) {
    if (rows.isEmpty) {
      // Still a scroll view: the frame's scrollbar needs a live position on
      // [_vScroll], and an empty state would otherwise leave it unattached.
      // The message itself is the frame's overlay, so that it centres on the
      // viewport rather than on the full width of the columns.
      return ListView(controller: _vScroll, children: const [SizedBox()]);
    }

    return ListView.separated(
      controller: _vScroll,
      itemCount: rows.length,
      separatorBuilder:
          (_, _) => const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) => _dataRow(rows[i], i),
    );
  }

  Widget _dataRow(CaseItem c, int index) {
    return Container(
      color: index.isOdd ? AppColors.surfaceAlt : AppColors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: _rowPadding,
        vertical: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.canTick)
            SizedBox(
              width: _checkboxWidth,
              child: _checkbox(
                value: _selected.contains(c.exceptionCode),
                onChanged:
                    (v) => setState(() {
                      if (v ?? false) {
                        _selected.add(c.exceptionCode);
                      } else {
                        _selected.remove(c.exceptionCode);
                      }
                    }),
              ),
            ),
          for (final col in _cols)
            SizedBox(
              width: col.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: col.cell(c),
              ),
            ),
          SizedBox(width: _actionsWidth, child: _actions(c)),
        ],
      ),
    );
  }

  Widget _clientCell(CaseItem c) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => widget.onOpenCase(c, CaseDetailTab.basicInfo),
        borderRadius: BorderRadius.circular(4),
        child: Text(
          c.clientId,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLight,
          ),
        ),
      ),
    );
  }

  /// The check that raised the record.
  Widget _descriptionCell(CaseItem c) {
    if (c.healthCheckCategory.isEmpty) return _plain('');
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        c.healthCheckCategory,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          height: 1.25,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  /// What actually failed, in the health check's own words.
  ///
  /// Two lines and muted: it is the longest text in the row — a full sentence
  /// where every other column is a label — so it reads as detail beside the
  /// check rather than competing with it.
  Widget _reasonCell(CaseItem c) {
    if (c.reason.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('—', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        c.reason,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.3,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _dateCell(CaseItem c) {
    final date = _rowDate(c);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        date == null ? '—' : _date(date),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          color: date == null ? AppColors.textMuted : AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _messageCell(CaseItem c) {
    // The count the queue endpoint sent, not `comments.length` — a grid row is
    // read without its thread, so counting off that list would report every
    // case as having none.
    final count = c.messageCount;
    final label =
        count == 0 ? 'No Messages' : '$count Message${count == 1 ? '' : 's'}';
    final color = count == 0 ? AppColors.textMuted : AppColors.primaryLight;

    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => widget.onOpenCase(c, CaseDetailTab.comments),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 14, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: count == 0 ? FontWeight.w400 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lastMessageCell(CaseItem c) {
    if (c.updatedNote.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('—', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          c.updatedNote,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.3,
            color: AppColors.textPrimary,
          ),
        ),
        if (c.updatedBy.isNotEmpty) ...[
          const SizedBox(height: 2),
          // Author only: the timestamp has its own column now.
          Text(
            c.updatedBy,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _plain(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text.isEmpty ? '—' : text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.3,
        color: text.isEmpty ? AppColors.textMuted : AppColors.textSecondary,
      ),
    ),
  );

  /// A single value carrying more weight than [_plain] — used for the columns
  /// a reader scans down to identify the record.
  Widget _strong(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text.isEmpty ? '—' : text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: text.isEmpty ? AppColors.textMuted : AppColors.textPrimary,
      ),
    ),
  );

  Widget _actions(CaseItem c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _actionIcon(
          icon: Icons.visibility_outlined,
          tooltip: 'View details',
          onTap: () => widget.onOpenCase(c, CaseDetailTab.basicInfo),
        ),
        if (widget.tabs.contains(CaseDetailTab.verify))
          _actionIcon(
            icon: Icons.check_circle_outline_rounded,
            tooltip: 'Verify',
            onTap: () => widget.onOpenCase(c, CaseDetailTab.verify),
          ),
        if (widget.tabs.contains(CaseDetailTab.reassign))
          _actionIcon(
            icon: Icons.swap_horiz_rounded,
            tooltip: 'Reassign',
            onTap: () => widget.onOpenCase(c, CaseDetailTab.reassign),
          ),
      ],
    );
  }

  Widget _actionIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon),
      iconSize: 19,
      color: AppColors.textMuted,
      hoverColor: AppColors.infoBg,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.all(6),
      ),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }

  // --- Footer -------------------------------------------------------------

  Widget _footer(int total, int start, int end, int totalPages) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  children: [
                    const TextSpan(text: 'Showing '),
                    TextSpan(
                      text: '${total == 0 ? 0 : end}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: ' of '),
                    TextSpan(
                      text: '$total',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: ' records'),
                  ],
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
              _pageBtn(
                label: 'Prev',
                icon: Icons.arrow_back_rounded,
                enabled: _page > 0,
                onTap:
                    () => setState(() {
                      if (_page > 0) _page--;
                    }),
              ),
              // Flexible so the pager still fits a phone-width footer: this
              // label gives way before the Prev/Next buttons do.
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'Page ${_page + 1} of $totalPages',
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              _pageBtn(
                label: 'Next',
                icon: Icons.arrow_forward_rounded,
                iconTrailing: true,
                enabled: _page < totalPages - 1,
                onTap:
                    () => setState(() {
                      if (_page < totalPages - 1) _page++;
                    }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pageBtn({
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    bool iconTrailing = false,
  }) {
    final color = enabled ? AppColors.textPrimary : AppColors.textMuted;
    final content = [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 7),
      Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    ];

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: iconTrailing ? content.reversed.toList() : content,
          ),
        ),
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime? d) {
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} '
        '${d.year}';
  }

}
