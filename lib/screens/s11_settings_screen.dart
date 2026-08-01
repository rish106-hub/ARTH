import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../models/user_profile.dart';
import '../providers/user_profile_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/animated_number.dart';
import '../widgets/arth_brand_mark.dart';
import '../utils/session_cleanup.dart';
import 'package:url_launcher/url_launcher.dart';

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
                    PaycheckColors.gold.withValues(alpha: 0.06),
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
                        const _SectionHeader(label: 'TAX PROFILE'),
                        const SizedBox(height: 12),

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
                        const _SectionHeader(label: 'PROGRESS'),
                        const SizedBox(height: 12),

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
                        const SizedBox(height: 8),
                        _ActionTile(
                          icon: Icons.insights_rounded,
                          label: 'Spend Map',
                          subtitle: 'On-device parsing with account backup',
                          badge: 'NEW',
                          onTap: () => context.push('/spend-map'),
                        ),

                        const SizedBox(height: 24),
                        const _SectionHeader(label: 'ACCOUNT & SECURITY'),
                        const SizedBox(height: 12),

                        if (account != null) ...[
                          _AccountSecurityTile(account: account),
                          const SizedBox(height: 8),
                        ],

                        const SizedBox(height: 24),
                        const _SectionHeader(label: 'DATA & PRIVACY'),
                        const SizedBox(height: 12),

                        const _GlassSection(
                          children: [
                            _PrivacyRow(
                              icon: Icons.cloud_done_rounded,
                              iconColor: PaycheckColors.teal,
                              label: 'Server Sync',
                              description:
                                  'Your data is encrypted and stored securely on ARTH servers.',
                            ),
                            _PrivacyRow(
                              icon: Icons.lock_outline_rounded,
                              iconColor: PaycheckColors.gold,
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
                          iconColor: PaycheckColors.alert,
                          labelColor: PaycheckColors.alert,
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
                  onTap: (i) => goToArthTab(context, i),
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
        confirmColor: PaycheckColors.alert,
        onConfirm: () async {
          Navigator.pop(ctx);
          await signOutDeviceAndRouteToAuth(context, ref);
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
        confirmColor: PaycheckColors.alert,
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
            style: PaycheckType.h2(
              color: PaycheckColors.textPrimary,
            ).copyWith(
              fontSize: compact ? 24 : 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: PaycheckColors.gold.withValues(alpha: 0.12),
              borderRadius: AppRadius.card,
              border:
                  Border.all(color: PaycheckColors.gold.withValues(alpha: 0.3)),
            ),
            child: Text(
              'FY2025-26 Filing',
              style: PaycheckType.micro(
                color: PaycheckColors.gold,
              ).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
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
      borderRadius: AppRadius.card,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                PaycheckColors.gold.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.04),
              ],
            ),
            borderRadius: AppRadius.card,
            border: Border.all(
              color: PaycheckColors.gold.withValues(alpha: 0.3),
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
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [PaycheckColors.gold, Color(0xFFD4A017)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: PaycheckType.bodyMedium(
                          color: Colors.black,
                        ).copyWith(fontSize: 18, fontWeight: FontWeight.w700),
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
                          style: PaycheckType.bodyMedium(
                            color: PaycheckColors.textPrimary,
                          ).copyWith(fontSize: 18, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          account.email,
                          style: PaycheckType.caption(
                            color: PaycheckColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Sync badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: PaycheckColors.teal.withValues(alpha: 0.15),
                      borderRadius: AppRadius.card,
                      border: Border.all(
                        color: PaycheckColors.teal.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_done_rounded,
                          size: 11,
                          color: PaycheckColors.teal,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Synced',
                          style: PaycheckType.caption(
                            color: PaycheckColors.teal,
                          ).copyWith(fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _HeroButton(
                      icon: Icons.tune_rounded,
                      label: 'Update Profile',
                      onTap: onEdit,
                    ),
                  ),
                  const SizedBox(width: 12),
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
        color: PaycheckColors.bgCard,
        borderRadius: AppRadius.card,
        border: Border.all(color: PaycheckColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: PaycheckColors.bgSurface,
              shape: BoxShape.circle,
              border: Border.all(color: PaycheckColors.border),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: PaycheckColors.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Not signed in', style: PaycheckType.bodyMedium()),
                Text(
                  'Sign in to sync your data',
                  style:
                      PaycheckType.micro(color: PaycheckColors.textSecondary),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: AppButtons.primaryGold.copyWith(
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
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
    final color = isDanger ? PaycheckColors.alert : PaycheckColors.gold;
    final compact = MediaQuery.sizeOf(context).width < 360;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: AppRadius.control,
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: PaycheckType.bodyMedium(
                    color: color,
                  ).copyWith(
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w600,
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
            value: compact
                ? '₹${formatRupeesCompact(totalGap)}'
                : '₹${NumberFormat('#,##,##0', 'en_IN').format(totalGap)}',
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: highlight
            ? PaycheckColors.gold.withValues(alpha: 0.08)
            : PaycheckColors.bgCard,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: highlight
              ? PaycheckColors.gold.withValues(alpha: 0.3)
              : PaycheckColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 14,
            color:
                highlight ? PaycheckColors.gold : PaycheckColors.textSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: PaycheckType.bodyStrong(
              color:
                  highlight ? PaycheckColors.gold : PaycheckColors.textPrimary,
            ).copyWith(fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: PaycheckType.micro(color: PaycheckColors.textSecondary),
          ),
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
            decoration: const BoxDecoration(
              color: PaycheckColors.bgCard,
              borderRadius: AppRadius.card,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── ACCOUNT SECURITY TILE ───────────────────────────────────────────────────
class _AccountSecurityTile extends StatelessWidget {
  final dynamic account;
  const _AccountSecurityTile({required this.account});

  @override
  Widget build(BuildContext context) {
    return const _GlassSection(
      children: [
        _PrivacyRow(
          icon: Icons.lock_outline_rounded,
          iconColor: PaycheckColors.teal,
          label: 'Data Privacy',
          description:
              'Your tax profile is encrypted and synced to ARTH servers. Only you can access it.',
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
        color: PaycheckColors.bgCard,
        borderRadius: AppRadius.card,
        border: Border.all(color: PaycheckColors.border),
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
              Icon(icon, size: 16, color: PaycheckColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style:
                      PaycheckType.caption(color: PaycheckColors.textSecondary),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  value,
                  style: PaycheckType.bodyMedium().copyWith(
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
          const Divider(
            indent: 42,
            endIndent: 0,
            color: PaycheckColors.divider,
            height: 1,
          ),
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
                  borderRadius: AppRadius.card,
                ),
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: PaycheckType.bodyMedium()),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: PaycheckType.micro(
                        color: PaycheckColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(
            indent: 64,
            endIndent: 0,
            color: PaycheckColors.divider,
            height: 1,
          ),
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
    this.iconColor = PaycheckColors.gold,
    this.labelColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final lColor = labelColor ?? PaycheckColors.textPrimary;
    final compact = MediaQuery.sizeOf(context).width < 360;
    return Material(
      color: PaycheckColors.bgCard,
      borderRadius: AppRadius.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.control,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: AppRadius.control,
            border: Border.all(color: PaycheckColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: AppRadius.card,
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 16),
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
                          style: PaycheckType.bodyMedium().copyWith(
                            color: lColor,
                            fontSize: compact ? 14 : null,
                          ),
                        ),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  PaycheckColors.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge!,
                              style: PaycheckType.micro(
                                color: PaycheckColors.gold,
                              ).copyWith(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: PaycheckType.micro(
                        color: PaycheckColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: PaycheckColors.textMuted,
                size: 18,
              ),
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
      style: PaycheckType.micro(
        color: PaycheckColors.textMuted,
      ).copyWith(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0),
    );
  }
}

// ─── APP FOOTER ──────────────────────────────────────────────────────────────
class _AppFooter extends StatelessWidget {
  static const _websiteUrl = 'https://arth-website.vercel.app/';

  Future<void> _openWebsite() async {
    final uri = Uri.parse(_websiteUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(color: PaycheckColors.divider.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _openWebsite,
          child: ArthBrandMark(
            size: 24,
            spacing: 8,
            wordmarkStyle: PaycheckType.heading(
              color: PaycheckColors.textSecondary,
            ).copyWith(fontSize: 14),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'v1.0  |  Dual-year rules  |  FY2026-27 planning first',
          style: PaycheckType.micro(color: PaycheckColors.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Not a rupee less. Not a rupee more.',
          style: PaycheckType.micro(
            color: PaycheckColors.textMuted,
          ).copyWith(fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 5,
          runSpacing: 4,
          children: [
            const Icon(Icons.shield_outlined,
                size: 11, color: PaycheckColors.teal),
            Text(
              'Secured on ARTH Cloud  |  AES-256 Encrypted',
              style: PaycheckType.micro(color: PaycheckColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            GestureDetector(
              onTap: _openWebsite,
              child: Text(
                'Privacy Policy',
                style: PaycheckType.micro(color: PaycheckColors.gold),
              ),
            ),
            Text(
              '·',
              style: PaycheckType.micro(color: PaycheckColors.textMuted),
            ),
            GestureDetector(
              onTap: _openWebsite,
              child: Text(
                'Terms of Use',
                style: PaycheckType.micro(color: PaycheckColors.gold),
              ),
            ),
            Text(
              '·',
              style: PaycheckType.micro(color: PaycheckColors.textMuted),
            ),
            GestureDetector(
              onTap: _openWebsite,
              child: Text(
                'Visit Website',
                style: PaycheckType.micro(color: PaycheckColors.gold),
              ),
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
      backgroundColor: PaycheckColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.control,
        side: BorderSide(color: PaycheckColors.border),
      ),
      title: Text(title, style: PaycheckType.heading()),
      content: Text(
        body,
        style: PaycheckType.body(color: PaycheckColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: PaycheckType.body(color: PaycheckColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: onConfirm,
          child: Text(
            confirmLabel,
            style: PaycheckType.body(color: confirmColor),
          ),
        ),
      ],
    );
  }
}
