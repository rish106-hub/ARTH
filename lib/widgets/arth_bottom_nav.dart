import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';

void goToArthTab(BuildContext context, int index) {
  switch (index) {
    case 0:
      context.go('/paycheck');
      break;
    case 1:
      context.go('/paycheck/money');
      break;
    case 2:
      context.go('/paycheck/plan');
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
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      label: 'Home',
    ),
    _NavItem(
      icon: Icons.description_outlined,
      activeIcon: Icons.description_rounded,
      label: 'Money',
    ),
    _NavItem(
      icon: Icons.calculate_outlined,
      activeIcon: Icons.calculate_rounded,
      label: 'Plan',
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPad + 8),
      decoration: const BoxDecoration(
        color: PaycheckColors.surface,
        border: Border(top: BorderSide(color: PaycheckColors.divider)),
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
                borderRadius: AppRadius.control,
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
                          color: selected
                              ? PaycheckColors.ink
                              : Colors.transparent,
                          borderRadius: AppRadius.card,
                        ),
                        child: Icon(
                          selected ? item.activeIcon : item.icon,
                          color: selected
                              ? PaycheckColors.surface
                              : PaycheckColors.textSecondary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PaycheckType.micro(
                          color: selected
                              ? PaycheckColors.ink
                              : PaycheckColors.textSecondary,
                        ).copyWith(
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500),
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
