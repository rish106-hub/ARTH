import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import 'ui_policy.dart';

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
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    _NavItem(
      icon: Icons.folder_special_outlined,
      activeIcon: Icons.folder_special_rounded,
      label: 'Vault',
    ),
    _NavItem(
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome_rounded,
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
    final reduceMotion = MotionPolicy.reduce(context);
    final blur = SurfacePolicy.blur(context, normal: 16);
    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, bottom: bottomPad + 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: blur <= 0
            ? _NavContainer(
                selectedIndex: selectedIndex,
                onTap: onTap,
                reduceMotion: reduceMotion,
              )
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: _NavContainer(
                  selectedIndex: selectedIndex,
                  onTap: onTap,
                  reduceMotion: reduceMotion,
                ),
              ),
      ),
    );
  }
}

class _NavContainer extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final bool reduceMotion;

  const _NavContainer({
    required this.selectedIndex,
    required this.onTap,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(ArthBottomNav._items.length, (i) {
          final item = ArthBottomNav._items[i];
          final isSelected = i == selectedIndex;
          return GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    width: 34,
                    height: 30,
                    decoration: isSelected
                        ? BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            boxShadow: reduceMotion
                                ? null
                                : [
                                    BoxShadow(
                                      color: AppColors.gold.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 10,
                                      spreadRadius: 1,
                                    ),
                                  ],
                          )
                        : null,
                    child: Icon(
                      isSelected ? item.activeIcon : item.icon,
                      color:
                          isSelected ? AppColors.gold : AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9,
                      color:
                          isSelected ? AppColors.gold : AppColors.textSecondary,
                      letterSpacing: 0,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
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
