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
  cpu,
  team,
  date,
  activity,
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

  /// Fixed filter choices, for a column whose slices are set by the workflow
  /// rather than by whatever values the rows happen to carry. Left null, the
  /// dropdown offers the distinct values present in the data instead.
  final List<String>? options;

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

  bool get filterable => value != null;
}

/// The statuses the STATUS filter always offers, whether or not a row is
/// currently in one — they are part of the workflow, so a week where nobody
/// happens to be waiting on the health checker should not make that choice
/// disappear.
final List<String> _statusOptions = [
  for (final s in CaseStatus.assignable) s.label,
];

/// The dashboard record grid.
class CasesTable extends StatefulWidget {
  final List<CaseItem> cases;

  /// Opens the detail drawer for a record, on a specific tab.
  final void Function(CaseItem, CaseDetailTab) onOpenCase;

  const CasesTable({super.key, required this.cases, required this.onOpenCase});

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
    // Filters on the line the cell leads with — the specific failure, or the
    // check that raised the record where no reason was captured. The italic
    // second line is the same check, so matching it too would only ever
    // widen a slice the reader already sees.
    _Col(
      label: 'DESCRIPTION',
      width: 240,
      sort: _SortKey.description,
      value: _description,
      cell: _descriptionCell,
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
      options: _statusOptions,
      cell:
          (c) => Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(status: c.status),
          ),
    ),
    _Col(label: 'DATE', width: 130, sort: _SortKey.date, cell: _dateCell),
    _Col(
      label: 'ACTIVITY',
      width: 150,
      sort: _SortKey.activity,
      value: (c) => c.lastActivity?.type.label ?? '',
      cell: _activityCell,
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
      _checkboxWidth +
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
  /// A column declaring [_Col.options] offers exactly those and nothing else:
  /// they are the workflow's own list, so one goes on being offered through a
  /// week where no record happens to be in it, and a value the data carries
  /// that the workflow does not name never joins them. STATUS is the reason —
  /// the dashboard has two statuses, and a stray value arriving on a row must
  /// not quietly become a third choice in the dropdown.
  List<String> _optionsFor(_Col col) {
    final fixed = col.options;
    if (fixed != null) return fixed;

    final present = <String>{for (final c in widget.cases) col.value!(c)}
      ..removeWhere((v) => v.isEmpty);
    return present.toList()..sort();
  }

  List<CaseItem> get _sorted {
    String keyOf(CaseItem c) => switch (_sortKey) {
      _SortKey.client => c.clientId,
      _SortKey.description => _description(c),
      _SortKey.cpu => c.cpu,
      _SortKey.team => c.team,
      _SortKey.date => '',
      _SortKey.activity => c.lastActivity?.type.label ?? '',
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

  /// What the Description column reads from — the specific failure text, or
  /// the check that raised the record when no reason was captured.
  static String _description(CaseItem c) =>
      c.reason.isNotEmpty ? c.reason : c.healthCheckCategory;

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
                          _selected.removeAll(rows.map((c) => c.exceptionCode));
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
          const SizedBox(width: _checkboxWidth),
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

  /// What failed, over the check that raised it. The check is dropped when it
  /// is already standing in as the description.
  Widget _descriptionCell(CaseItem c) {
    final text = _description(c);
    if (text.isEmpty) return _plain('');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            height: 1.25,
            color: AppColors.textPrimary,
          ),
        ),
        if (c.reason.isNotEmpty && c.healthCheckCategory.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            c.healthCheckCategory,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
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

  Widget _activityCell(CaseItem c) {
    final activity = c.lastActivity;
    if (activity == null) return _plain('');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(activity.type.icon, size: 14, color: activity.type.color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                activity.type.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: activity.type.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _time(activity.at),
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }

  /// Message count, opening the record's thread. Reads as a link only when
  /// there is something to read.
  Widget _messageCell(CaseItem c) {
    final count = c.comments.length;
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
        _actionIcon(
          icon: Icons.check_circle_outline_rounded,
          tooltip: 'Verify',
          onTap: () => widget.onOpenCase(c, CaseDetailTab.verify),
        ),
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

  static String _time(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '${hour.toString().padLeft(2, '0')}:$minute '
        '${d.hour < 12 ? 'AM' : 'PM'}';
  }
}
