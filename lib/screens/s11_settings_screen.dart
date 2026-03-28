import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../providers/user_profile_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/animated_number.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final account = ref.watch(authProvider);
    final taxAsync = ref.watch(taxResultProvider);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // Ambient background glow
          Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.gold.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header
                _SettingsHeader(size: size),

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Account hero card
                        _AccountHeroCard(
                          account: account,
                          onSignOut: () => _confirmSignOut(context, ref),
                          onEdit: () => context.go('/questions'),
                        ),

                        const SizedBox(height: 20),

                        // Tax snapshot strip
                        taxAsync.when(
                          data: (result) => _TaxSnapshotStrip(
                            ctc: profile.annualCTC,
                            gapCount: result.gapCount,
                            totalGap: result.totalGapAmount,
                            regime: result.betterRegime.name,
                          ),
                          loading: () => const _SnapshotSkeleton(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),

                        const SizedBox(height: 24),
                        _SectionHeader(label: 'TAX PROFILE'),
                        const SizedBox(height: 10),

                        // Tax profile card
                        _GlassSection(
                          children: [
                            _ProfileDetailRow(
                              icon: Icons.account_balance_wallet_outlined,
                              label: 'Annual CTC',
                              value:
                                  '₹ ${(profile.annualCTC / 100000).toStringAsFixed(1)} Lakhs',
                            ),
                            _ProfileDetailRow(
                              icon: Icons.work_outline_rounded,
                              label: 'Employment',
                              value: profile.employmentType.name == 'salaried'
                                  ? 'Salaried'
                                  : 'Self-Employed',
                            ),
                            _ProfileDetailRow(
                              icon: Icons.location_city_outlined,
                              label: 'City',
                              value: profile.city,
                            ),
                            _ProfileDetailRow(
                              icon: Icons.cake_outlined,
                              label: 'Age Group',
                              value: profile.ageGroup.label,
                            ),
                            _ProfileDetailRow(
                              icon: Icons.home_outlined,
                              label: 'Pays Rent',
                              value: profile.paysRent ? 'Yes' : 'No',
                              isLast: true,
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Recalculate button
                        _ActionTile(
                          icon: Icons.tune_rounded,
                          label: 'Recalculate My Gap',
                          subtitle: 'Update your income details and re-run',
                          badge: 'EDIT',
                          onTap: () => context.go('/questions'),
                        ),
                        const SizedBox(height: 8),
                        _ActionTile(
                          icon: Icons.compare_arrows_rounded,
                          label: 'Old vs New Regime',
                          subtitle: 'Side-by-side regime breakdown',
                          onTap: () => context.push('/regime-comparison'),
                        ),

                        const SizedBox(height: 24),
                        _SectionHeader(label: 'PROGRESS'),
                        const SizedBox(height: 10),

                        _ActionTile(
                          icon: Icons.checklist_rounded,
                          label: 'Action Plan',
                          subtitle: 'Your deduction to-do list',
                          onTap: () => context.go('/action-plan'),
                        ),
                        const SizedBox(height: 8),
                        _ActionTile(
                          icon: Icons.timeline_rounded,
                          label: 'Progress Tracker',
                          subtitle: 'Key deadlines and FY timeline',
                          onTap: () => context.push('/progress'),
                        ),
                        const SizedBox(height: 8),
                        _ActionTile(
                          icon: Icons.ios_share_rounded,
                          label: 'Share My Gap Card',
                          subtitle: 'Generate a shareable summary',
                          onTap: () => context.push('/share'),
                        ),

                        const SizedBox(height: 24),
                        _SectionHeader(label: 'ACCOUNT & SECURITY'),
                        const SizedBox(height: 10),

                        if (account != null) ...[
                          _AccountSecurityTile(account: account),
                          const SizedBox(height: 8),
                        ],

                        const SizedBox(height: 24),
                        _SectionHeader(label: 'DATA & PRIVACY'),
                        const SizedBox(height: 10),

                        _GlassSection(
                          children: [
                            _PrivacyRow(
                              icon: Icons.cloud_done_rounded,
                              iconColor: AppColors.teal,
                              label: 'Server Sync',
                              description:
                                  'Your data is encrypted and stored securely on ARTH servers.',
                            ),
                            _PrivacyRow(
                              icon: Icons.lock_outline_rounded,
                              iconColor: AppColors.gold,
                              label: 'Encryption',
                              description:
                                  'AES-256 encryption at rest. We never share your data with third parties.',
                              isLast: true,
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        _ActionTile(
                          icon: Icons.delete_forever_rounded,
                          label: 'Clear All Data',
                          subtitle: 'Permanently wipe profile and calculations',
                          iconColor: AppColors.alert,
                          labelColor: AppColors.alert,
                          onTap: () => _confirmClear(context, ref),
                        ),

                        const SizedBox(height: 24),
                        _AppFooter(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),

                ArthBottomNav(
                  selectedIndex: 3,
                  onTap: (i) {
                    switch (i) {
                      case 0:
                        context.go('/gap-reveal');
                        break;
                      case 1:
                        context.go('/action-plan');
                        break;
                      case 2:
                        context.go('/progress');
                        break;
                      case 3:
                        break;
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _ArthDialog(
        title: 'Sign Out?',
        body: 'This will remove your account from this device.',
        confirmLabel: 'Sign Out',
        confirmColor: AppColors.alert,
        onConfirm: () async {
          Navigator.pop(ctx);
          // Clear profile and gap state before invalidating auth so uid is
          // still readable inside clearAll().
          await ref.read(userProfileProvider.notifier).clearAll();
          ref.invalidate(gapStateProvider);
          ref.invalidate(taxResultProvider);
          await ref.read(authProvider.notifier).signOut();
          if (context.mounted) context.go('/auth');
        },
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _ArthDialog(
        title: 'Clear Everything?',
        body:
            'Your tax profile and all calculated gaps will be permanently deleted.',
        confirmLabel: 'Clear Data',
        confirmColor: AppColors.alert,
        onConfirm: () async {
          Navigator.pop(ctx);
          HapticFeedback.heavyImpact();
          await ref.read(userProfileProvider.notifier).clearAll();
          ref.invalidate(taxResultProvider);
          ref.invalidate(gapStateProvider);
          if (context.mounted) context.go('/welcome');
        },
      ),
    );
  }
}

// ─── HEADER ──────────────────────────────────────────────────────────────────
class _SettingsHeader extends StatelessWidget {
  final Size size;
  const _SettingsHeader({required this.size});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 360;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        spacing: 12,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: compact ? 24 : 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
            ),
            child: Text(
              'FY 2025-26',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── ACCOUNT HERO CARD ───────────────────────────────────────────────────────
class _AccountHeroCard extends StatelessWidget {
  final dynamic account;
  final VoidCallback onSignOut;
  final VoidCallback onEdit;

  const _AccountHeroCard({
    required this.account,
    required this.onSignOut,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (account == null) {
      return _GuestCard(onSignIn: () => context.go('/auth'));
    }

    final compact = MediaQuery.sizeOf(context).width < 360;
    final name = account.name as String? ?? 'User';
    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : 'A';

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.gold.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.gold.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Avatar
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.gold, Color(0xFFD4A017)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: compact ? 180 : 190,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          account.email,
                          style: AppTextStyles.caption(
                              color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Sync badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.teal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.teal.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_done_rounded,
                            size: 11, color: AppColors.teal),
                        const SizedBox(width: 4),
                        Text(
                          'Synced',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _HeroButton(
                      icon: Icons.tune_rounded,
                      label: 'Update Profile',
                      onTap: onEdit,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HeroButton(
                      icon: Icons.logout_rounded,
                      label: 'Sign Out',
                      onTap: onSignOut,
                      isDanger: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestCard extends StatelessWidget {
  final VoidCallback onSignIn;
  const _GuestCard({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.person_outline_rounded,
                color: AppColors.textSecondary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Not signed in', style: AppTextStyles.bodyMedium()),
                Text('Sign in to sync your data',
                    style: AppTextStyles.micro(color: AppColors.textSecondary)),
              ],
            ),
          ),
          ElevatedButton(
            style: AppButtons.primaryGold.copyWith(
              padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            ),
            onPressed: onSignIn,
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;

  const _HeroButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? AppColors.alert : AppColors.gold;
    final compact = MediaQuery.sizeOf(context).width < 360;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── TAX SNAPSHOT STRIP ───────────────────────────────────────────────────────
class _TaxSnapshotStrip extends StatelessWidget {
  final int ctc;
  final int gapCount;
  final int totalGap;
  final String regime;

  const _TaxSnapshotStrip({
    required this.ctc,
    required this.gapCount,
    required this.totalGap,
    required this.regime,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 360;
    return Row(
      children: [
        Expanded(
          child: _SnapCell(
            label: 'Your CTC',
            value: '₹${(ctc / 100000).toStringAsFixed(1)}L',
            icon: Icons.account_balance_wallet_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SnapCell(
            label: 'Gaps Found',
            value: '$gapCount',
            icon: Icons.search_rounded,
            highlight: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SnapCell(
            label: 'Potential Save',
            value:
                compact ? '₹${formatRupeesCompact(totalGap)}' : '₹${NumberFormat('#,##,##0', 'en_IN').format(totalGap)}',
            icon: Icons.savings_outlined,
          ),
        ),
      ],
    );
  }
}

class _SnapCell extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  const _SnapCell({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.gold.withValues(alpha: 0.08)
            : AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight
              ? AppColors.gold.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 14,
              color: highlight ? AppColors.gold : AppColors.textSecondary),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: highlight ? AppColors.gold : AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(label,
              style: AppTextStyles.micro(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _SnapshotSkeleton extends StatelessWidget {
  const _SnapshotSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
          3,
          (_) => Expanded(
                child: Container(
                  height: 72,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              )),
    );
  }
}

// ─── ACCOUNT SECURITY TILE ───────────────────────────────────────────────────
class _AccountSecurityTile extends StatelessWidget {
  final dynamic account;
  const _AccountSecurityTile({required this.account});

  @override
  Widget build(BuildContext context) {
    return _GlassSection(
      children: [
        _PrivacyRow(
          icon: Icons.lock_outline_rounded,
          iconColor: AppColors.teal,
          label: 'Data Privacy',
          description: 'Your tax profile is encrypted and synced to ARTH servers. Only you can access it.',
          isLast: true,
        ),
      ],
    );
  }
}

// ─── GLASS SECTION ───────────────────────────────────────────────────────────
class _GlassSection extends StatelessWidget {
  final List<Widget> children;
  const _GlassSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }
}

// ─── PROFILE DETAIL ROW ──────────────────────────────────────────────────────
class _ProfileDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  const _ProfileDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 360;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style:
                        AppTextStyles.caption(color: AppColors.textSecondary)),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  value,
                  style: AppTextStyles.bodyMedium().copyWith(
                    fontSize: compact ? 13 : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
              indent: 42, endIndent: 0, color: AppColors.divider, height: 1),
      ],
    );
  }
}

// ─── PRIVACY ROW ─────────────────────────────────────────────────────────────
class _PrivacyRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String description;
  final bool isLast;

  const _PrivacyRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.description,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.bodyMedium()),
                    const SizedBox(height: 2),
                    Text(description,
                        style: AppTextStyles.micro(
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
              indent: 64, endIndent: 0, color: AppColors.divider, height: 1),
      ],
    );
  }
}

// ─── ACTION TILE ─────────────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final Color iconColor;
  final Color? labelColor;
  final String? badge;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.iconColor = AppColors.gold,
    this.labelColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final lColor = labelColor ?? AppColors.textPrimary;
    final compact = MediaQuery.sizeOf(context).width < 360;
    return Material(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            label,
                            style: AppTextStyles.bodyMedium().copyWith(
                              color: lColor,
                              fontSize: compact ? 14 : null,
                            ),
                          ),
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                badge!,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.gold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle,
                        style: AppTextStyles.micro(
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── SECTION HEADER ──────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        letterSpacing: 2.0,
      ),
    );
  }
}

// ─── APP FOOTER ──────────────────────────────────────────────────────────────
class _AppFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(color: AppColors.divider.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '₹',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.gold.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'ARTH',
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'v1.0  |  Finance Act 2025  |  FY 2025-26',
          style: AppTextStyles.micro(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Not a rupee less. Not a rupee more.',
          style: AppTextStyles.micro(color: AppColors.textMuted)
              .copyWith(fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 5,
          runSpacing: 4,
          children: [
            Icon(Icons.shield_outlined, size: 11, color: AppColors.teal),
            Text(
              'Secured on ARTH Cloud  |  AES-256 Encrypted',
              style: AppTextStyles.micro(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ],
    );
  }
}

// ─── REUSABLE DIALOG ─────────────────────────────────────────────────────────
class _ArthDialog extends StatelessWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final Color confirmColor;
  final VoidCallback onConfirm;

  const _ArthDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.confirmColor,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.border),
      ),
      title: Text(title, style: AppTextStyles.h3()),
      content:
          Text(body, style: AppTextStyles.body(color: AppColors.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: AppTextStyles.body(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: onConfirm,
          child: Text(confirmLabel,
              style: AppTextStyles.body(color: confirmColor)),
        ),
      ],
    );
  }
}
