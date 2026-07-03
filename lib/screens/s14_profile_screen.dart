import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/account_profile.dart';
import '../models/entitlement.dart';
import '../models/user_account.dart';
import '../models/user_profile.dart';
import '../providers/account_profile_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/entitlement_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/server_api_service.dart';
import '../theme/app_theme.dart';
import '../utils/session_cleanup.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';

const _avatarColorOptions = {
  'gold': AppColors.gold,
  'teal': AppColors.teal,
  'amber': AppColors.amber,
  'green': AppColors.success,
  'blue': AppColors.info,
};

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(accountProfileProvider);
    final authAccount = ref.watch(authProvider);
    final completeAsync = ref.watch(completedTaxProfileProvider);
    final entitlement = ref.watch(entitlementProvider);
    final taxProfile = ref.watch(userProfileProvider);

    return ArthScaffold(
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 3,
        onTap: (i) {
          switch (i) {
            case 0:
              context.go('/discover');
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
      child: Column(
        children: [
          ArthPremiumAppBar(
            eyebrow: 'Profile',
            title: 'Account and privacy',
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: () =>
                    ref.read(accountProfileProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh_rounded),
                color: AppColors.textSecondary,
              ),
            ],
          ),
          Expanded(
            child: accountAsync.when(
              loading: () => const ArthLoadingPanel(
                title: 'Loading profile',
                insights: ['Checking account and PAN vault status.'],
              ),
              error: (_, __) => ArthStatePanel(
                icon: Icons.cloud_off_rounded,
                title: 'Could not load profile',
                message: 'Your local account is safe. Retry when online.',
                actionLabel: 'Retry',
                onAction: () =>
                    ref.read(accountProfileProvider.notifier).refresh(),
              ),
              data: (profile) {
                final account = profile?.user ?? authAccount;
                if (account == null) {
                  return ArthStatePanel(
                    icon: Icons.lock_outline_rounded,
                    title: 'Sign in required',
                    message: 'Create an ARTH account to use Profile.',
                    actionLabel: 'Sign in',
                    onAction: () => context.go('/auth'),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AccountCard(
                        account: account,
                        onEditName: () =>
                            _showProfileSheet(context, ref, account),
                        onSignOut: () => _confirmSignOut(context, ref),
                      ),
                      const SizedBox(height: 16),
                      _DiagnosticCard(
                        completeAsync: completeAsync,
                        onStart: () => context.go('/questions'),
                      ),
                      const SizedBox(height: 16),
                      _TaxAccuracyCard(
                        profile: taxProfile,
                        onEdit: () =>
                            _showTaxAccuracySheet(context, ref, taxProfile),
                      ),
                      const SizedBox(height: 16),
                      _PanVaultCard(
                        pan: profile?.pan ?? PanVaultStatus.missing,
                        onAdd: () => _showPanSheet(context, ref),
                        onDelete: () => _confirmDeletePan(context, ref),
                      ),
                      const SizedBox(height: 16),
                      _PremiumDemoCard(
                        entitlement: entitlement,
                        onChanged: (enabled) => ref
                            .read(entitlementProvider.notifier)
                            .setPremiumDemo(enabled),
                      ),
                      const SizedBox(height: 16),
                      const _SupportAndDossierCard(),
                      const SizedBox(height: 16),
                      _PrivacyCard(),
                      const SizedBox(height: 16),
                      _DangerZone(
                        onClearData: () => _confirmClearData(context, ref),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showProfileSheet(
    BuildContext context,
    WidgetRef ref,
    UserAccount account,
  ) {
    final controller = TextEditingController(text: account.name);
    final phoneController = TextEditingController(text: account.phoneNumber);
    final initialsController = TextEditingController(text: account.initials);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        var saving = false;
        String? error;
        var avatarColor = account.avatarColor ?? 'gold';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> save() async {
              final name = controller.text.trim();
              final phone = _normalizePhone(phoneController.text);
              final initials = initialsController.text.trim().toUpperCase();
              if (name.length < 2) {
                setSheetState(() => error = 'Enter at least 2 characters');
                return;
              }
              if (phoneController.text.trim().isNotEmpty && phone == null) {
                setSheetState(
                    () => error = 'Enter a valid Indian phone number');
                return;
              }
              if (!RegExp(r'^[A-Z]{1,2}$').hasMatch(initials)) {
                setSheetState(() => error = 'Use 1 or 2 letters for avatar');
                return;
              }
              setSheetState(() {
                saving = true;
                error = null;
              });
              try {
                await ref.read(accountProfileProvider.notifier).updateProfile(
                      name: name,
                      phoneNumber: phone,
                      avatarInitials: initials,
                      avatarColor: avatarColor,
                    );
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } catch (_) {
                setSheetState(() {
                  saving = false;
                  error = 'Could not update profile. Try again.';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Edit profile', style: AppTextStyles.h2()),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '9749452397 or +919749452397',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: initialsController,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 2,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
                      TextInputFormatter.withFunction(
                        (oldValue, newValue) => newValue.copyWith(
                          text: newValue.text.toUpperCase(),
                          selection: newValue.selection,
                        ),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Display picture initials',
                      hintText: 'RD',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in _avatarColorOptions.entries)
                        ChoiceChip(
                          selected: avatarColor == option.key,
                          label: Text(option.key),
                          avatar: CircleAvatar(
                            backgroundColor: option.value,
                            radius: 7,
                          ),
                          onSelected: saving
                              ? null
                              : (_) =>
                                  setSheetState(() => avatarColor = option.key),
                        ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: AppTextStyles.caption(color: AppColors.alert),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: AppButtons.primaryGold,
                    onPressed: saving ? null : save,
                    child: Text(saving ? 'Saving...' : 'Save profile'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String? _normalizePhone(String raw) {
    final compact = raw.replaceAll(RegExp(r'[\s()-]'), '');
    if (compact.isEmpty) return null;
    if (RegExp(r'^[6-9][0-9]{9}$').hasMatch(compact)) {
      return '+91$compact';
    }
    if (RegExp(r'^\+91[6-9][0-9]{9}$').hasMatch(compact)) {
      return compact;
    }
    return null;
  }

  void _showTaxAccuracySheet(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) {
    TextEditingController money(int? value) =>
        TextEditingController(text: value?.toString() ?? '');
    final basic = money(profile.actualBasicSalary);
    final hra = money(profile.actualHraReceived);
    final professionalTax = money(profile.actualProfessionalTax);
    final selfPremium = money(profile.healthInsuranceSelfPremium);
    final parentPremium = money(profile.healthInsuranceParentsPremium);
    final savingsInterest = money(profile.savingsInterest);
    final fdInterest = money(profile.fdInterest);
    final employerNps = money(profile.employerNpsContribution);
    final donationRate = money(profile.donationDeductionRatePercent);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            int? read(
              TextEditingController controller,
              String label, {
              int max = 100000000,
            }) {
              final raw = controller.text.trim().replaceAll(',', '');
              if (raw.isEmpty) return null;
              final value = int.tryParse(raw);
              if (value == null || value < 0 || value > max) {
                throw FormatException(label);
              }
              return value;
            }

            Future<void> save() async {
              setSheetState(() {
                saving = true;
                error = null;
              });
              try {
                final updated = ref.read(userProfileProvider).copyWith(
                      actualBasicSalary: read(basic, 'basic salary'),
                      actualHraReceived: read(hra, 'HRA received'),
                      actualProfessionalTax: read(
                        professionalTax,
                        'professional tax',
                        max: 100000,
                      ),
                      healthInsuranceSelfPremium:
                          read(selfPremium, 'self premium'),
                      healthInsuranceParentsPremium:
                          read(parentPremium, 'parents premium'),
                      savingsInterest:
                          read(savingsInterest, 'savings interest'),
                      fdInterest: read(fdInterest, 'FD interest'),
                      employerNpsContribution:
                          read(employerNps, 'employer NPS'),
                      donationDeductionRatePercent:
                          read(donationRate, 'donation rate', max: 100),
                    );
                ref
                    .read(userProfileProvider.notifier)
                    .updateField((_) => updated);
                final complete = await ref
                    .read(userProfileProvider.notifier)
                    .isOnboardingComplete();
                if (complete) {
                  await ref.read(userProfileProvider.notifier).save();
                  ref.invalidate(taxResultProvider);
                }
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } on FormatException catch (e) {
                setSheetState(() {
                  saving = false;
                  error = 'Check ${e.message}. Use whole rupee amounts only.';
                });
              } catch (_) {
                setSheetState(() {
                  saving = false;
                  error = 'Could not save accuracy inputs. Try again.';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Tax accuracy inputs', style: AppTextStyles.h2()),
                    const SizedBox(height: 8),
                    Text(
                      'Optional. Empty fields use ARTH assumptions and are shown in calculation notes.',
                      style: AppTextStyles.body(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    _AccuracyInput(
                        controller: basic, label: 'Actual basic salary'),
                    _AccuracyInput(
                        controller: hra, label: 'Actual HRA received'),
                    _AccuracyInput(
                      controller: professionalTax,
                      label: 'Actual professional tax',
                    ),
                    _AccuracyInput(
                      controller: selfPremium,
                      label: '80D self/family premium',
                    ),
                    _AccuracyInput(
                      controller: parentPremium,
                      label: '80D parents premium',
                    ),
                    _AccuracyInput(
                      controller: savingsInterest,
                      label: 'Savings account interest',
                    ),
                    _AccuracyInput(
                        controller: fdInterest, label: 'FD interest'),
                    _AccuracyInput(
                      controller: employerNps,
                      label: 'Employer NPS contribution',
                    ),
                    _AccuracyInput(
                      controller: donationRate,
                      label: 'Donation deduction rate %',
                      hint: '50 or 100',
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: AppTextStyles.caption(color: AppColors.alert),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: AppButtons.primaryGold,
                      onPressed: saving ? null : save,
                      child: Text(saving ? 'Saving...' : 'Save inputs'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPanSheet(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        var consent = false;
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> save() async {
              final pan = controller.text.trim().toUpperCase();
              if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(pan)) {
                setSheetState(() => error = 'Enter a valid 10-character PAN');
                return;
              }
              if (!consent) {
                setSheetState(() => error = 'Consent is required to save PAN');
                return;
              }
              setSheetState(() {
                saving = true;
                error = null;
              });
              try {
                await ref.read(accountProfileProvider.notifier).savePan(pan);
                HapticFeedback.mediumImpact();
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } catch (saveError) {
                final message = _panSaveErrorMessage(saveError);
                setSheetState(() {
                  saving = false;
                  error = message;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('PAN Vault', style: AppTextStyles.h2()),
                  const SizedBox(height: 8),
                  Text(
                    'Optional. ARTH encrypts PAN on the server and only shows a masked version in the app.',
                    style: AppTextStyles.body(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 10,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                      TextInputFormatter.withFunction(
                        (oldValue, newValue) => newValue.copyWith(
                          text: newValue.text.toUpperCase(),
                          selection: newValue.selection,
                        ),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: 'PAN',
                      hintText: 'ABCDE1234F',
                      errorText: error,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  CheckboxListTile(
                    value: consent,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: saving
                        ? null
                        : (value) =>
                            setSheetState(() => consent = value ?? false),
                    title: Text(
                      'I consent to storing my PAN in encrypted form for future ARTH tax identity features.',
                      style: AppTextStyles.caption(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: AppButtons.primaryGold,
                    onPressed: saving ? null : save,
                    child: Text(saving ? 'Saving...' : 'Save PAN securely'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeletePan(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete saved PAN?'),
        content: const Text(
          'This removes PAN from your ARTH vault. You can add it again later.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(accountProfileProvider.notifier).deletePan();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _panSaveErrorMessage(Object error) {
    if (error is ServerApiException && error.statusCode == 409) {
      if (error.message.contains('different PAN')) {
        return 'This account already has a different PAN linked. Delete it first if you need to change it.';
      }
      return 'This PAN is already linked to another ARTH account.';
    }
    return 'Could not save PAN. Check connection and try again.';
  }

  void _confirmClearData(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
          'This wipes tax profile, calculations, progress, and PAN vault data from ARTH servers.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(userProfileProvider.notifier).clearAll();
              ref.invalidate(completedTaxProfileProvider);
              ref.invalidate(taxResultProvider);
              ref.invalidate(gapStateProvider);
              await ref.read(accountProfileProvider.notifier).refresh();
              if (context.mounted) context.go('/discover');
            },
            child: const Text('Clear data'),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('This removes this device session only.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await signOutDeviceAndRouteToAuth(context, ref);
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _PremiumDemoCard extends StatelessWidget {
  final Entitlement entitlement;
  final ValueChanged<bool> onChanged;

  const _PremiumDemoCard({
    required this.entitlement,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ArthSection(
      title: 'Plan',
      child: PremiumGlassPanel(
        tint: AppColors.gold,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: entitlement.isPremiumDemo,
              onChanged: onChanged,
              title: Text(
                entitlement.label,
                style: AppTextStyles.bodyMedium(),
              ),
              subtitle: Text(
                'Demo toggle only. No payment, no entitlement enforcement, and no hidden data collection.',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
              secondary: Icon(
                entitlement.isPremiumDemo
                    ? Icons.workspace_premium_outlined
                    : Icons.lock_open_outlined,
                color: AppColors.gold,
              ),
            ),
            const Divider(color: AppColors.divider),
            const _BenefitLine(
                text:
                    'Free: diagnostic, cockpit, PAN vault, document upload, AIS guide'),
            const _BenefitLine(
                text:
                    'Premium demo: document intelligence and CA-ready filing pack'),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final UserAccount account;
  final VoidCallback onEditName;
  final VoidCallback onSignOut;

  const _AccountCard({
    required this.account,
    required this.onEditName,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final avatarColor =
        _avatarColorOptions[account.avatarColor] ?? AppColors.gold;
    return PremiumGlassPanel(
      elevated: true,
      borderRadius: BorderRadius.circular(28),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: avatarColor.withValues(alpha: 0.18),
                child: Text(
                  account.initials,
                  style: AppTextStyles.h3(color: avatarColor),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.name, style: AppTextStyles.h3()),
                    const SizedBox(height: 3),
                    Text(
                      account.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppTextStyles.caption(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit profile',
                onPressed: onEditName,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Sign out',
                onPressed: onSignOut,
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _AccountDetailPill(
                  icon: Icons.call_outlined,
                  label: account.phoneNumber ?? 'Add phone',
                  active: account.phoneNumber != null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AccountDetailPill(
                  icon: Icons.photo_camera_outlined,
                  label: 'DP: ${account.initials}',
                  active: true,
                  color: avatarColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Profile photo upload will use the encrypted vault layer. Current DP stores initials and color only.',
              style: AppTextStyles.micro(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountDetailPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;

  const _AccountDetailPill({
    required this.icon,
    required this.label,
    required this.active,
    this.color = AppColors.teal,
  });

  @override
  Widget build(BuildContext context) {
    final tint = active ? color : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: AppRadius.pill,
        border: Border.all(color: tint.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: tint, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  final AsyncValue<bool> completeAsync;
  final VoidCallback onStart;

  const _DiagnosticCard({
    required this.completeAsync,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final complete = completeAsync.asData?.value ?? false;
    return PremiumGlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TrustBadge(
            icon: Icons.route_rounded,
            label: 'Tax diagnostic',
            color: AppColors.teal,
          ),
          const SizedBox(height: 14),
          Text(
            complete ? 'Diagnostic complete' : 'Start from scratch when ready',
            style: AppTextStyles.h3(),
          ),
          const SizedBox(height: 6),
          Text(
            complete
                ? 'Your cockpit, action plan, and progress are active.'
                : 'You can explore ARTH now and complete the 3-minute diagnostic later.',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            style: AppButtons.outlineGold,
            onPressed: onStart,
            icon:
                Icon(complete ? Icons.tune_rounded : Icons.play_arrow_rounded),
            label: Text(complete ? 'Update diagnostic' : 'Start diagnostic'),
          ),
        ],
      ),
    );
  }
}

class _TaxAccuracyCard extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onEdit;

  const _TaxAccuracyCard({
    required this.profile,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final activeCount = [
      profile.actualBasicSalary,
      profile.actualHraReceived,
      profile.actualProfessionalTax,
      profile.healthInsuranceSelfPremium,
      profile.healthInsuranceParentsPremium,
      profile.savingsInterest,
      profile.fdInterest,
      profile.employerNpsContribution,
      profile.donationDeductionRatePercent,
    ].where((value) => value != null).length;

    return PremiumGlassPanel(
      tint: AppColors.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: AppColors.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Tax accuracy inputs', style: AppTextStyles.h3()),
              ),
              TrustBadge(
                icon: activeCount > 0
                    ? Icons.verified_outlined
                    : Icons.info_outline_rounded,
                label: activeCount > 0 ? '$activeCount exact' : 'Optional',
                color: activeCount > 0 ? AppColors.success : AppColors.info,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Add exact salary breakup, HRA, 80D premium, interest, NPS, and donation inputs to reduce assumptions in tax results.',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            style: AppButtons.outlineGold,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Edit accuracy inputs'),
          ),
        ],
      ),
    );
  }
}

class _AccuracyInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;

  const _AccuracyInput({
    required this.controller,
    required this.label,
    this.hint = 'Optional',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixText: label.contains('%') ? null : '₹ ',
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _PanVaultCard extends StatelessWidget {
  final PanVaultStatus pan;
  final VoidCallback onAdd;
  final VoidCallback onDelete;

  const _PanVaultCard({
    required this.pan,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      tint: AppColors.teal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: AppColors.teal),
              const SizedBox(width: 10),
              Expanded(child: Text('PAN Vault', style: AppTextStyles.h3())),
              TrustBadge(
                icon: pan.present
                    ? Icons.verified_user_outlined
                    : Icons.lock_outline_rounded,
                label: pan.present ? 'Saved' : 'Optional',
                color: pan.present ? AppColors.success : AppColors.teal,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            pan.present
                ? 'Saved as ${pan.maskedPan}. Raw PAN is never shown after save.'
                : 'Add PAN later to prepare ARTH for identity-aware tax features. Not required for the current diagnostic.',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          const _BenefitLine(text: 'Future AIS, 26AS, and ITR readiness'),
          const _BenefitLine(text: 'Cleaner tax identity continuity'),
          const _BenefitLine(
              text: 'Encrypted server vault with masked display'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: AppButtons.primaryGold,
                  onPressed: onAdd,
                  icon: Icon(
                      pan.present ? Icons.edit_outlined : Icons.add_rounded),
                  label: Text(pan.present ? 'Update PAN' : 'Add PAN'),
                ),
              ),
              if (pan.present) ...[
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Delete PAN',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppColors.alert,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BenefitLine extends StatelessWidget {
  final String text;

  const _BenefitLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: AppColors.teal, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportAndDossierCard extends StatelessWidget {
  const _SupportAndDossierCard();

  @override
  Widget build(BuildContext context) {
    return ArthSection(
      title: 'Support and dossier',
      child: PremiumGlassPanel(
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  const Icon(Icons.assignment_outlined, color: AppColors.gold),
              title: Text('Tax Dossier', style: AppTextStyles.bodyMedium()),
              subtitle: Text(
                'Private summary of diagnostic, proof readiness, PAN status, and filing handoff.',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/tax-dossier'),
            ),
            const Divider(color: AppColors.divider),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.support_agent_rounded,
                color: AppColors.teal,
              ),
              title: Text('Help Center', style: AppTextStyles.bodyMedium()),
              subtitle: Text(
                'Report issues, ask tax-readiness questions, or get data/privacy help.',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/help'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ArthSection(
      title: 'Data and privacy',
      child: PremiumGlassPanel(
        child: Column(
          children: const [
            _PrivacyRow(
              icon: Icons.cloud_done_rounded,
              title: 'Cloud sync',
              body:
                  'Diagnostic, progress, and masked account state sync after sign-in.',
            ),
            Divider(color: AppColors.divider),
            _PrivacyRow(
              icon: Icons.visibility_off_outlined,
              title: 'No raw PAN display',
              body:
                  'PAN is optional, encrypted server-side, and never queued offline.',
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _PrivacyRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.gold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium()),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  final VoidCallback onClearData;

  const _DangerZone({required this.onClearData});

  @override
  Widget build(BuildContext context) {
    return ArthSection(
      title: 'App controls',
      child: PremiumGlassPanel(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading:
              const Icon(Icons.delete_forever_rounded, color: AppColors.alert),
          title: Text(
            'Clear all data',
            style: AppTextStyles.bodyMedium(color: AppColors.alert),
          ),
          subtitle: Text(
            'Wipe diagnostic, calculations, progress, and PAN vault.',
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onClearData,
        ),
      ),
    );
  }
}
