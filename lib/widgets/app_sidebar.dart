import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_mark.dart';

class NavDestination {
  final IconData icon;
  final String label;
  const NavDestination(this.icon, this.label);
}

const kNavItems = <NavDestination>[
  NavDestination(Icons.dashboard_rounded, 'Dashboard'),
  NavDestination(Icons.assessment_rounded, 'MIS'),
  NavDestination(Icons.upload_file_rounded, 'Upload Document'),
];

/// Fixed dark navigation rail. Collapses to icon-only when [expanded] is false.
///
/// The rail owns the whole chrome: the collapse control sits beside the brand
/// and the account block sits at the foot, so no separate top bar is needed.
class AppSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool expanded;

  /// Collapses or expands the rail. On mobile the rail is inside a drawer,
  /// where this closes it instead.
  final VoidCallback onToggle;

  final String displayName;
  final VoidCallback onLogout;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.expanded,
    required this.onToggle,
    required this.displayName,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final width = expanded ? 244.0 : 76.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primaryDark, Color(0xFF16233D)],
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (var i = 0; i < kNavItems.length; i++)
                    _NavTile(
                      item: kNavItems[i],
                      selected: i == selectedIndex,
                      expanded: expanded,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  /// Brand plus the collapse control. The 76px rail cannot hold both side by
  /// side, so they stack there instead.
  Widget _buildHeader() {
    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Column(
          children: [
            const BrandMark(size: 36, onDark: true),
            const SizedBox(height: 10),
            _toggleButton(),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 72,
      padding: const EdgeInsets.only(left: 18, right: 10),
      child: Row(
        children: [
          const BrandMark(size: 36, onDark: true),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'SMART',
              overflow: TextOverflow.clip,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
          _toggleButton(),
        ],
      ),
    );
  }

  Widget _toggleButton() {
    return IconButton(
      onPressed: onToggle,
      tooltip: expanded ? 'Collapse menu' : 'Expand menu',
      icon: Icon(expanded ? Icons.menu_open_rounded : Icons.menu_rounded),
      iconSize: 22,
      color: Colors.white.withValues(alpha: 0.72),
      hoverColor: Colors.white.withValues(alpha: 0.10),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
    );
  }

  /// Account block. It lives here rather than in a top bar so the rail is the
  /// only chrome on the page.
  Widget _buildFooter() {
    final initials = displayName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    final avatar = Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
        shape: BoxShape.circle,
      ),
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final signOut = IconButton(
      onPressed: onLogout,
      tooltip: 'Sign out',
      icon: const Icon(Icons.logout_rounded),
      iconSize: 19,
      color: Colors.white.withValues(alpha: 0.72),
      hoverColor: Colors.white.withValues(alpha: 0.10),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(expanded ? 18 : 0, 12, expanded ? 8 : 0, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
      ),
      child: expanded
          ? Row(
              children: [
                avatar,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Supervisor',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                signOut,
              ],
            )
          : Column(
              children: [
                Tooltip(message: displayName, child: avatar),
                const SizedBox(height: 8),
                signOut,
              ],
            ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final NavDestination item;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: 46,
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 0),
      alignment: expanded ? Alignment.centerLeft : Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: selected
            ? Border.all(color: Colors.white.withValues(alpha: 0.10))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.icon,
            size: 21,
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.62),
          ),
          if (expanded) ...[
            const SizedBox(width: 14),
            // Flexible so a long destination name ellipsises instead of
            // overflowing the fixed-width rail.
            Flexible(
              child: Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.72),
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: content,
      ),
    );

    if (expanded) return tile;
    return Tooltip(message: item.label, child: tile);
  }
}
