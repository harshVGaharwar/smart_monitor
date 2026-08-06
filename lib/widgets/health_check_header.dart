import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Counts shown in the status summary strip.
class StatusCounts {
  final int total;
  final int pending;
  final int inReview;
  final int verified;
  final int completed;
  final int needsClarification;

  const StatusCounts({
    required this.total,
    required this.pending,
    required this.inReview,
    required this.verified,
    required this.completed,
    required this.needsClarification,
  });
}

/// Dashboard header: title and live summary, search, status counts, and the
/// export action.
///
/// Filtering is not here: the grid below carries a picker under each of its
/// own column headings, which is both narrower to aim at and honest about
/// which field it acts on.
class HealthCheckHeader extends StatelessWidget {
  final StatusCounts counts;
  final int recordCount;

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  final DateTime lastUpdated;
  final VoidCallback onRefresh;

  final VoidCallback onExport;

  final bool hasNotifications;
  final VoidCallback? onNotifications;

  const HealthCheckHeader({
    super.key,
    required this.counts,
    required this.recordCount,
    required this.searchController,
    required this.onSearchChanged,
    required this.lastUpdated,
    required this.onRefresh,
    required this.onExport,
    this.hasNotifications = false,
    this.onNotifications,
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
          'Health Check Dashboard',
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

    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _searchField(context, isMobile),
        const SizedBox(width: 8),
        _notificationBell(),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 18,
        16,
        isMobile ? 10 : 14,
        14,
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: titleBlock),
                    _notificationBell(),
                  ],
                ),
                const SizedBox(height: 12),
                _searchField(context, isMobile),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleBlock),
                trailing,
              ],
            ),
    );
  }

  Widget _summaryLine() {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _inlineStat(counts.pending, 'pending'),
        _dot(),
        _inlineStat(counts.inReview, 'in review'),
        _dot(),
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
          suffixIcon: searchController.text.isEmpty
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

  Widget _notificationBell() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onNotifications,
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none_rounded),
          iconSize: 23,
          color: AppColors.textSecondary,
        ),
        if (hasNotifications)
          Positioned(
            right: 9,
            top: 8,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
            ),
          ),
      ],
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
          Wrap(
            spacing: 22,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _count(counts.total, 'Total', AppColors.textPrimary),
              _count(counts.pending, 'Pending', AppColors.warning),
              _count(counts.inReview, 'In Review', AppColors.info),
              _count(counts.verified, 'Verified', AppColors.success),
              _count(counts.completed, 'Completed', AppColors.textSecondary),
              _count(
                counts.needsClarification,
                'Needs Clarification',
                AppColors.danger,
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
