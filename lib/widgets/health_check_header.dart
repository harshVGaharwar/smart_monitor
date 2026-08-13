import 'package:flutter/material.dart';
import '../models/case_item.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';
import '../theme/responsive.dart';

/// Counts shown in the status summary strip.
class StatusCounts {
  final int total;

  /// How many records sit in each status. Driven by the data rather than a
  /// fixed set of fields, so adding or retiring a status does not leave the
  /// strip quietly reporting zeroes for buckets nothing uses.
  final Map<CaseStatus, int> byStatus;

  const StatusCounts({required this.total, required this.byStatus});

  /// Counts [cases] into buckets.
  factory StatusCounts.of(List<CaseItem> cases) {
    final counts = <CaseStatus, int>{};
    for (final c in cases) {
      counts[c.status] = (counts[c.status] ?? 0) + 1;
    }
    return StatusCounts(total: cases.length, byStatus: counts);
  }

  int operator [](CaseStatus status) => byStatus[status] ?? 0;

  /// The statuses the strip lists: every one a reviewer can assign, so a
  /// bucket standing empty still reads as zero rather than vanishing, plus
  /// any retired status some record still carries.
  List<CaseStatus> get shown => [
    ...CaseStatus.assignable,
    for (final s in CaseStatus.values)
      if (!CaseStatus.assignable.contains(s) && (byStatus[s] ?? 0) > 0) s,
  ];
}

/// Dashboard header: title and live summary, search, status counts, and the
/// export action.
///
/// Filtering is not here: the grid below carries a picker under each of its
/// own column headings, which is both narrower to aim at and honest about
/// which field it acts on.
class HealthCheckHeader extends StatelessWidget {
  /// The heading, which names the side of the handover this reader works —
  /// see `AppRole.dashboardTitle`. Passed in rather than derived here: this
  /// widget is given what to draw and knows nothing about roles.
  final String title;

  final StatusCounts counts;
  final int recordCount;

  /// Whether the status breakdown is shown — the "view the summary" right.
  ///
  /// Only the counts go: search, refresh, the record total and export stay for
  /// everyone who reaches this screen, because they are how a reader works
  /// their own rows rather than how they read across the whole queue.
  final bool showSummary;

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  final DateTime lastUpdated;
  final VoidCallback onRefresh;

  final VoidCallback onExport;


  const HealthCheckHeader({
    super.key,
    required this.title,
    required this.counts,
    required this.recordCount,
    required this.searchController,
    required this.onSearchChanged,
    required this.lastUpdated,
    required this.onRefresh,
    required this.onExport,
    this.showSummary = true,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleRow(context, isMobile),
        const Divider(height: 1, color: AppColors.border),
        _countsRow(isMobile),
      ],
    );
  }

  // --- Title, summary, search ---------------------------------------------

  Widget _titleRow(BuildContext context, bool isMobile) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isMobile ? 19 : 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        _summaryLine(),
      ],
    );

    final trailing = _searchField(context, isMobile);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 18,
        16,
        isMobile ? 10 : 14,
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
                ],
              )
              : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [Expanded(child: titleBlock), trailing],
              ),
    );
  }

  Widget _summaryLine() {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showSummary) ...[
          _inlineStat(counts[CaseStatus.pendingWithCpu], 'with CPU'),
          _dot(),
          _inlineStat(
            counts[CaseStatus.pendingWithHealthChecker],
            'with health checker',
          ),
          _dot(),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onRefresh,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.refresh_rounded,
                  size: 15,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'Updated ${_relativeTime(lastUpdated)}',
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _inlineStat(int value, String label) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$value ',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot() => const Text(
    '·',
    style: TextStyle(fontSize: 15, color: AppColors.textMuted),
  );

  Widget _searchField(BuildContext context, bool isMobile) {
    return SizedBox(
      width: isMobile ? double.infinity : context.widthClamp(0.26, 240, 400),
      height: 44,
      child: TextField(
        controller: searchController,
        onChanged: onSearchChanged,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceAlt,
          hintText: 'Search client / account / case',
          hintStyle: const TextStyle(fontSize: 14, color: AppColors.textMuted),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 19,
            color: AppColors.textMuted,
          ),
          suffixIcon:
              searchController.text.isEmpty
                  ? null
                  : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 17),
                    color: AppColors.textMuted,
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
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

  // --- Status counts, record total and export -----------------------------

  /// The counts strip, with the record total and export closing the same
  /// line. The outer Wrap measures the two groups rather than guessing at a
  /// breakpoint: they share the line whenever both fit, and export drops to a
  /// line of its own only when it genuinely no longer does.
  Widget _countsRow(bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 18,
        vertical: 11,
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (showSummary)
            Wrap(
              spacing: 22,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _count(counts.total, 'Total', AppColors.textPrimary),
                // Tinted from the badge mapping, so a bucket here and the chip
                // on its rows never drift to different colours.
                for (final status in counts.shown)
                  _count(
                    counts[status],
                    status.label,
                    StatusBadge.colorsFor(status).$1,
                  ),
              ],
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flexible so the count gives way first on a narrow phone; the
              // export button keeps its full width either way.
              Flexible(
                child: Text(
                  '$recordCount record${recordCount == 1 ? '' : 's'}',
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _exportButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _count(int value, String label, Color color) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$value ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportButton() {
    final enabled = recordCount > 0;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onExport : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.file_download_outlined,
                size: 17,
                color: enabled ? AppColors.textPrimary : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                'Export Excel',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: enabled ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "2 minutes ago" / "just now" — coarse on purpose, it only needs to tell
  /// the user whether what they are looking at is stale.
  static String _relativeTime(DateTime when) {
    final seconds = DateTime.now().difference(when).inSeconds;
    if (seconds < 45) return 'just now';
    final minutes = (seconds / 60).round();
    if (minutes < 60) {
      return '$minutes minute${minutes == 1 ? '' : 's'} ago';
    }
    final hours = (minutes / 60).round();
    if (hours < 24) return '$hours hour${hours == 1 ? '' : 's'} ago';
    final days = (hours / 24).round();
    return '$days day${days == 1 ? '' : 's'} ago';
  }
}
