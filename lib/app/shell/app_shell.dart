import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_tokens.dart';
import '../../core/widgets/badges.dart';
import '../../features/chat/application/chat_providers.dart';
import '../router/routes.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _items = [
  _NavItem('Bosh sahifa', Icons.home_outlined, Icons.home_rounded),
  _NavItem('Qidiruv', Icons.search_rounded, Icons.saved_search_rounded),
  _NavItem(
    'Chat',
    Icons.chat_bubble_outline_rounded,
    Icons.chat_bubble_rounded,
  ),
  _NavItem('Profil', Icons.person_outline_rounded, Icons.person_rounded),
];

/// Persistent tab scaffold. Tabs keep their state (IndexedStack via
/// StatefulShellRoute); re-tapping the active tab pops it to its root.
/// Phones get a bottom bar with a raised "+" button; wide screens a rail.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    HapticFeedback.selectionClick();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  void _create(BuildContext context) {
    HapticFeedback.mediumImpact();
    context.push(AppRoutes.create);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadChats = ref.watch(unreadChatsCountProvider);
    final expanded = AppBreakpoints.of(context) == WindowClass.expanded;

    if (expanded) {
      final palette = context.palette;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _goBranch,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.8,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: FloatingActionButton(
                  heroTag: 'rail-create',
                  tooltip: 'E’lon joylash',
                  elevation: 0,
                  backgroundColor: palette.primary,
                  foregroundColor: palette.onPrimary,
                  onPressed: () => _create(context),
                  child: const Icon(Icons.add_rounded, size: AppIconSize.xl),
                ),
              ),
              destinations: [
                for (final (index, item) in _items.indexed)
                  NavigationRailDestination(
                    icon: CountBadge(
                      count: index == 2 ? unreadChats : 0,
                      child: Icon(item.icon),
                    ),
                    selectedIcon: CountBadge(
                      count: index == 2 ? unreadChats : 0,
                      child: Icon(item.selectedIcon),
                    ),
                    label: Text(item.label),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: palette.border),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _BottomBar(
        currentIndex: navigationShell.currentIndex,
        unreadChats: unreadChats,
        onSelect: _goBranch,
        onCreate: () => _create(context),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.currentIndex,
    required this.unreadChats,
    required this.onSelect,
    required this.onCreate,
  });

  final int currentIndex;
  final int unreadChats;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  static const _barHeight = 64.0;
  static const _createSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Nav labels don't grow past 1.2× so five slots always fit on a 320pt phone.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2);

    Widget tab(int index) => Expanded(
      child: _TabButton(
        item: _items[index],
        selected: currentIndex == index,
        badge: index == 2 ? unreadChats : 0,
        onTap: () => onSelect(index),
      ),
    );

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.border)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: palette.shadow,
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: _barHeight,
            child: Row(
              children: [
                tab(0),
                tab(1),
                Expanded(
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: 'E’lon joylash',
                      excludeSemantics: true,
                      child: Tooltip(
                        message: 'E’lon joylash',
                        child: Material(
                          color: palette.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onCreate,
                            child: Ink(
                              width: _createSize,
                              height: _createSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color.lerp(
                                      palette.primary,
                                      Colors.white,
                                      0.12,
                                    )!,
                                    palette.primaryPressed,
                                  ],
                                ),
                                boxShadow: AppShadows.primaryGlow(
                                  palette.primary,
                                ),
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                color: palette.onPrimary,
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                tab(2),
                tab(3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = selected ? palette.primary : palette.textTertiary;
    return Semantics(
      selected: selected,
      button: true,
      label: badge > 0 ? '${item.label}, $badge ta o‘qilmagan' : item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        highlightShape: BoxShape.rectangle,
        containedInkWell: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.fast),
              child: CountBadge(
                key: ValueKey(selected),
                count: badge,
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  color: color,
                  size: AppIconSize.md + 1,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
