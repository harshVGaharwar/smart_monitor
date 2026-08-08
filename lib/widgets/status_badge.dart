import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/case_item.dart';

/// Colour-coded pill for a [CaseStatus].
class StatusBadge extends StatelessWidget {
  final CaseStatus status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = colorsFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status.label,
              maxLines: 2,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Foreground and background for a status. Public so the grid and the detail
  /// panel tint matching chips without duplicating the mapping.
  static (Color, Color) colorsFor(CaseStatus s) => switch (s) {
    // The two a reviewer can set. Both are "waiting on someone", so they share
    // the pending tint and are told apart by their label.
    CaseStatus.pendingWithCpu => (AppColors.warning, AppColors.warningBg),
    CaseStatus.pendingWithHealthChecker => (AppColors.info, AppColors.infoBg),
    CaseStatus.inReview => (AppColors.info, AppColors.infoBg),
    CaseStatus.verified => (AppColors.success, AppColors.successBg),
    // Completed is terminal and unremarkable — deliberately the quietest.
    CaseStatus.completed => (AppColors.textSecondary, AppColors.surfaceAlt),
    CaseStatus.needClarification => (
      const Color(0xFFC2410C),
      const Color(0xFFFFF1E6),
    ),
  };
}
