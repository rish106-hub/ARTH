import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

void goToArthTab(BuildContext context, int index) {
  switch (index) {
    case 0:
      context.go('/discover');
      break;
    case 1:
      context.go('/documents');
      break;
    case 2:
      context.go('/action-plan');
      break;
    case 3:
      context.go('/profile');
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
      icon: Icons.space_dashboard_outlined,
      activeIcon: Icons.space_dashboard_rounded,
      label: 'Home',
    ),
    _NavItem(
      icon: Icons.folder_special_outlined,
      activeIcon: Icons.folder_special_rounded,
      label: 'Vault',
    ),
    _NavItem(
      icon: Icons.checklist_outlined,
      activeIcon: Icons.checklist_rounded,
      label: 'Coach',
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
      padding: EdgeInsets.fromLTRB(10, 7, 10, bottomPad + 7),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
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
                borderRadius: AppRadius.card,
                onTap: () => onTap(i),
                child: SizedBox(
                  height: 52,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        selected ? item.activeIcon : item.icon,
                        color:
                            selected ? AppColors.gold : AppColors.textSecondary,
                        size: 21,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          color: selected
                              ? AppColors.gold
                              : AppColors.textSecondary,
                          letterSpacing: 0,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
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
