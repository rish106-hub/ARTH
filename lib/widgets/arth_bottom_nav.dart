import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

void goToArthTab(BuildContext context, int index) {
  switch (index) {
    case 0:
      context.go('/paycheck');
      break;
    case 1:
      context.go('/paycheck/promise');
      break;
    case 2:
      context.go('/paycheck/inbox');
      break;
    case 3:
      context.go('/paycheck/you');
      break;
  }
}

class ArthBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const ArthBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  static const _items = [
    _NavItem(
      icon: Icons.today_outlined,
      activeIcon: Icons.today_rounded,
      label: 'Paycheck',
    ),
    _NavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments_rounded,
      label: 'Promise',
    ),
    _NavItem(
      icon: Icons.route_outlined,
      activeIcon: Icons.route_rounded,
      label: 'Inbox',
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'You',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(10, 7, 10, bottomPad + 7),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: List.generate(_items.length, (i) {
          final item = _items[i];
          final selected = i == selectedIndex;
          return Expanded(
            child: Semantics(
              selected: selected,
              button: true,
              label: item.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onTap(i),
                child: SizedBox(
                  height: 56,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: AppMotion.fast,
                        curve: AppMotion.standard,
                        width: 32,
                        height: 26,
                        decoration: BoxDecoration(
                          color: selected ? AppColors.ink : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          selected ? item.activeIcon : item.icon,
                          color: selected
                              ? AppColors.surface
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.micro(
                          color: selected
                              ? AppColors.ink
                              : AppColors.textSecondary,
                        ).copyWith(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
