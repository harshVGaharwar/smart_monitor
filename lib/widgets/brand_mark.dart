import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The SMART logo mark — a rounded tile with a reconciliation glyph.
class BrandMark extends StatelessWidget {
  final double size;
  final bool onDark;
  const BrandMark({super.key, this.size = 40, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent, Color(0xFFB3121F)],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: onDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Icon(Icons.hub_rounded, color: Colors.white, size: size * 0.56),
    );
  }
}
