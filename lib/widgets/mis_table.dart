import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../models/mis_report.dart';
import 'searchable_dropdown.dart';
import 'table_scroll_frame.dart';

/// MIS Data register: a per-column "Show all" filter row, free-text search,
/// a tick checkbox per row and a Submit action for the ticked rows.
class MisTable extends StatefulWidget {
  final List<MisReport> reports;
  const MisTable({super.key, required this.reports});

  @override
  State<MisTable> createState() => _MisTableState();
}

/// One column of the register: how wide it is, how to read its value out of a
/// row, and whether it gets a filter dropdown.
class _MisCol {
  final String label;
  final double width;
  final String Function(MisReport) value;
  final bool filterable;

  const _MisCol({
    required this.label,
    required this.width,
    required this.value,
    this.filterable = true,
  });
}

class _MisTableState extends State<MisTable> {
  final _searchCtrl = TextEditingController();
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  String _search = '';

  /// Selected filter per column label; absent means "Show all".
  final Map<String, String> _filters = {};

  /// Tick state by row, kept locally until Submit.
  late Map<int, bool> _ticks;

  /// Completion dates stamped in this session, keyed by report. Approving a
  /// row records the moment it happened; withdrawing the approval drops the
  /// stamp, so the register falls back to the date it arrived with rather
  /// than losing it.
  final Map<int, DateTime> _completions = {};

  /// Bumped for a row every time its completion date is stamped. The cell
  /// keys its flash on this, so each approval restarts the animation instead
  /// of leaving a stale one to finish.
  final Map<int, int> _flashes = {};

  /// The tick box sits beside the date it stamps, so the act and its result
  /// read as one pair. It carries the dashboard's selection styling, with a
  /// select-all leading its heading and no filter under it. The report's
  /// serial number is not shown; it identifies nothing the reader needs,
  /// though it still keys the tick state.
  late final List<_MisCol> _cols = [
    _MisCol(
      label: 'REPORT NAME',
      width: 240,
      value: (r) => r.reportName,
      filterable: false,
    ),
    _MisCol(label: 'MIS RECD FROM', width: 168, value: (r) => r.recdFrom),
    _MisCol(label: 'FREQUENCY', width: 130, value: (r) => r.frequency),
    _MisCol(label: 'CATEGORY', width: 180, value: (r) => r.category),
    _MisCol(label: 'EMPLOYEE NAME', width: 168, value: (r) => r.employeeName),
    _MisCol(label: _tickCol, width: 140, value: (_) => '', filterable: false),
    _MisCol(
      label: _completionCol,
      width: 180,
      value: (r) => _fmt(_completions[r.srNo] ?? r.tickDate),
    ),
    _MisCol( 
      label: 'LAST PUBLISHED DATE',
      width: 200,
      value: (r) => _fmt(r.lastPublishedDate),
    ),
  ];

  double get _totalWidth =>
      _cols.fold(0.0, (sum, c) => sum + c.width) + _rowPadding * 2;

  static const double _rowPadding = 5;

  /// The approval column, whose cells are checkboxes rather than text.
  static const _tickCol = 'DATE UPDATE';

  /// The column an approval stamps.
  static const _completionCol = 'COMPLETED DATE';

  @override
  void initState() {
    super.initState();
    _ticks = {for (final r in widget.reports) r.srNo: r.ticked};
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  List<MisReport> get _filtered {
    return widget.reports.where((r) {
      for (final col in _cols) {
        final selected = _filters[col.label];
        if (selected != null && col.value(r) != selected) return false;
      }
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final hay = _cols.map((c) => c.value(r)).join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  /// Distinct values for a column, used to populate its filter dropdown.
  List<String> _optionsFor(_MisCol col) {
    final set = <String>{for (final r in widget.reports) col.value(r)};
    final list = set.where((v) => v.isNotEmpty).toList()..sort();
    return list;
  }

  int get _tickedCount => _ticks.values.where((v) => v).length;

  void _submit() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        content: Text(
          _tickedCount == 0
              ? 'No reports ticked'
              : '$_tickedCount report(s) submitted',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final isMobile = context.isMobile;

    // Same two-card shape as the dashboard: title, search and Submit up top,
    // and the register below with its filters under its own column headings.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerCard(context, isMobile),
        SizedBox(height: isMobile ? 12 : 16),
        Expanded(child: _tableCard(rows)),
      ],
    );
  }

  Widget _tableCard(List<MisReport> rows) {
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
              // The filter row holds dropdowns, and a mouse pan would eat the
              // clicks that open them. Panning stays on the scrollbar, the
              // wheel and trackpad swipes.
              mouseDrag: false,
              header: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _headerRow(),
                  _filterRow(),
                  const Divider(height: 1, color: AppColors.border),
                ],
              ),
              body: _body(rows),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _footer(rows.length),
        ],
      ),
    );
  }

  // --- Header card --------------------------------------------------------

  Widget _headerCard(BuildContext context, bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppTheme.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: _titleRow(context, isMobile),
    );
  }

  Widget _titleRow(BuildContext context, bool isMobile) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'MIS Data',
          style: TextStyle(
            fontSize: isMobile ? 19 : 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${widget.reports.length} report'
          '${widget.reports.length == 1 ? '' : 's'} · $_tickedCount ticked',
          style: const TextStyle(
            fontSize: 13.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 18,
        16,
        isMobile ? 14 : 18,
        14,
      ),
      child:
          isMobile
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  titleBlock,
                  const SizedBox(height: 12),
                  _searchField(context, isMobile),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _submitButton(),
                  ),
                ],
              )
              : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: titleBlock),
                  _searchField(context, isMobile),
                  const SizedBox(width: 12),
                  _submitButton(),
                ],
              ),
    );
  }

  Widget _searchField(BuildContext context, bool isMobile) {
    return SizedBox(
      width: isMobile ? double.infinity : context.widthClamp(0.24, 200, 320),
      height: 44,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _search = v),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceAlt,
          hintText: 'Search reports…',
          hintStyle: const TextStyle(fontSize: 14, color: AppColors.textMuted),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 19,
            color: AppColors.textMuted,
          ),
          suffixIcon:
              _search.isEmpty
                  ? null
                  : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 17),
                    color: AppColors.textMuted,
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    },
                  ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(
              color: AppColors.primaryLight,
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _submitButton() {
    return Material(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _submit,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          child: Text(
            'Submit',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // --- Header + filters ---------------------------------------------------

  /// Light band matching the dashboard grid.
  Widget _headerRow() {
    return Container(
      height: 46,
      color: AppColors.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: _rowPadding),
      child: Row(
        children: [
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
                      letterSpacing: 0.5,
                      color:
                          _filters.containsKey(col.label)
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

  /// A "Show all" picker under each filterable column, in the band the
  /// register's own headings sit in.
  Widget _filterRow() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: _rowPadding, vertical: 7),
      child: Row(
        children: [
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
        ],
      ),
    );
  }

  Widget _filterDropdown(_MisCol col) {
    return SearchableDropdown<String>(
      // A stamped completion date can retire the value a filter is pinned to;
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
      onChanged:
          (v) => setState(() {
            if (v == null) {
              _filters.remove(col.label);
            } else {
              _filters[col.label] = v;
            }
          }),
    );
  }

  // --- Body ---------------------------------------------------------------

  Widget _body(List<MisReport> rows) {
    if (rows.isEmpty) {
      // Still a scroll view: the frame's scrollbar needs a live position on
      // [_vScroll], and an empty state would otherwise leave it unattached.
      return ListView(
        controller: _vScroll,
        children: const [
          Padding(
            padding: EdgeInsets.all(28),
            child: Center(
              child: Text(
                'No reports match the current filters.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      );
    }

    // The vertical scrollbar lives in TableScrollFrame, pinned to the card's
    // right edge rather than riding along with the horizontal pan.
    return ListView.separated(
      controller: _vScroll,
      itemCount: rows.length,
      separatorBuilder:
          (_, _) => const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) => _dataRow(rows[i], i),
    );
  }

  Widget _dataRow(MisReport r, int index) {
    return Container(
      color: index.isOdd ? AppColors.surfaceAlt : AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: _rowPadding, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final col in _cols)
            SizedBox(
              width: col.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: switch (col.label) {
                  _tickCol => _checkbox(
                    value: _ticks[r.srNo] ?? false,
                    onChanged: (v) => _approve(r, v ?? false),
                  ),
                  _completionCol => _completionCell(col, r),
                  _ => _cellText(col, r),
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Approving a report stamps its completion date with the moment it
  /// happened; withdrawing the approval drops that stamp. Either way the cell
  /// two columns over changes, which is easy to miss on a row this wide — so
  /// the new date flashes once, rather than swapping in silently.
  void _approve(MisReport r, bool approved) {
    setState(() {
      _ticks[r.srNo] = approved;
      if (approved) {
        _completions[r.srNo] = DateTime.now();
      } else {
        _completions.remove(r.srNo);
      }
      _flashes[r.srNo] = (_flashes[r.srNo] ?? 0) + 1;
    });
  }

  /// The completion date, washed green for a beat after an approval changes
  /// it. Keyed on the flash counter so a second approval restarts the fade
  /// instead of riding the first one out.
  Widget _completionCell(_MisCol col, MisReport r) {
    final flash = _flashes[r.srNo];
    final text = _cellText(col, r);
    if (flash == null) return text;

    return TweenAnimationBuilder<double>(
      key: ValueKey(flash),
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      builder:
          (_, t, child) => DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.successBg.withValues(alpha: t),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: child,
            ),
          ),
      child: text,
    );
  }

  Widget _cellText(_MisCol col, MisReport r) {
    final isName = col.label == 'REPORT NAME';
    final text = col.value(r);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text.isEmpty ? '—' : text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.35,
          fontWeight: isName ? FontWeight.w600 : FontWeight.w400,
          color:
              text.isEmpty
                  ? AppColors.textMuted
                  : (isName ? AppColors.textPrimary : AppColors.textSecondary),
        ),
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
        width: 24,
        height: 24,
        child: Checkbox(
          value: value,
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

  // --- Footer -------------------------------------------------------------

  /// Submit lives in the header card now, so the footer only reports counts.
  Widget _footer(int shown) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
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
                  text: '$shown',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: ' of '),
                TextSpan(
                  text: '${widget.reports.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: ' reports'),
              ],
            ),
          ),
          Text(
            '$_tickedCount ticked',
            style: TextStyle(
              fontSize: 13,
              fontWeight: _tickedCount > 0 ? FontWeight.w600 : FontWeight.w400,
              color:
                  _tickedCount > 0
                      ? AppColors.primary
                      : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime? d) {
    if (d == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}
