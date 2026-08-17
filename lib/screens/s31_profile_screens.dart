import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/paycheck.dart';
import '../models/user_account.dart';
import '../models/user_profile.dart';
import '../providers/account_profile_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/paycheck_provider.dart';
import '../providers/tax_document_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/app_update_service.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../utils/session_cleanup.dart';
import '../widgets/arth_brand_mark.dart';
import '../widgets/employer_picker.dart';
import '../widgets/premium_ui.dart';

class ProfessionalProfileView extends ConsumerWidget {
  final PaycheckState paycheck;

  const ProfessionalProfileView({super.key, required this.paycheck});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final account = ref.watch(accountProfileProvider).asData?.value;
    final taxProfile = ref.watch(userProfileProvider);
    final documents = ref.watch(taxDocumentProvider).asData?.value ?? const [];
    final user = account?.user ?? auth;
    final completion = _profileCompletion(
      user: user,
      profile: taxProfile,
      panPresent: account?.pan.present ?? false,
      documentCount: documents.length,
    );
    final name = user?.name.trim().isNotEmpty == true
        ? user!.name.trim()
        : paycheck.employeeName;
    final email = user?.email.trim() ?? '';

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            sliver: SliverList.list(
              children: [
                const ArthBrandMark(
                  size: 30,
                  spacing: 9,
                ),
                const SizedBox(height: 28),
                _IdentityHeader(
                  name: name,
                  email: email,
                  initials: user?.initials ?? 'A',
                  onEdit: () => context.push('/profile/details'),
                ),
                const SizedBox(height: 24),
                _CompletenessPanel(completion: completion),
                const SizedBox(height: 28),
                const _SectionTitle('Your information'),
                _ProfileGroup(
                  children: [
                    _ProfileRow(
                      icon: Icons.person_outline_rounded,
                      title: 'Personal details',
                      detail: _personalDetail(user),
                      onTap: () => context.push('/profile/details'),
                    ),
                    _ProfileRow(
                      icon: Icons.work_outline_rounded,
                      title: 'Employment and income',
                      detail: _employmentDetail(taxProfile, paycheck),
                      onTap: () => context.push('/profile/details'),
                    ),
                    _ProfileRow(
                      icon: Icons.badge_outlined,
                      title: 'Tax identity',
                      detail: account?.pan.present == true
                          ? account!.pan.maskedPan ?? 'PAN stored securely'
                          : 'PAN not added',
                      status: account?.pan.present == true
                          ? ProfileStatus.complete
                          : ProfileStatus.optional,
                      onTap: () => context.push('/profile/tax-identity'),
                    ),
                    _ProfileRow(
                      icon: Icons.receipt_long_outlined,
                      title: 'Tax planning answers',
                      detail:
                          '${taxProfile.city} · ${taxProfile.ageGroup.label}',
                      onTap: () => context.push('/tax-plan/questions'),
                      isLast: true,
                    ),
                  ],
                ),
                const _SectionTitle('Money tools'),
                _ProfileGroup(
                  children: [
                    _ProfileRow(
                      key: const Key('profile_spend_map'),
                      icon: Icons.sms_outlined,
                      title: 'Expenses from SMS',
                      detail: 'Scan 1, 3, 6, or 12 months and YTD',
                      status: ProfileStatus.action,
                      onTap: () => context.push('/spend-map'),
                    ),
                    _ProfileRow(
                      key: const Key('profile_money_goal'),
                      icon: Icons.flag_outlined,
                      title: 'Savings goal',
                      detail: 'Build a plan from net pay and observed expenses',
                      onTap: () => context.push('/money-goal'),
                    ),
                    _ProfileRow(
                      key: const Key('profile_work_costs'),
                      icon: Icons.work_outline_rounded,
                      title: 'Workday costs',
                      detail: 'Find repeat commute, meal and work-life costs',
                      onTap: () => context.push('/work-costs'),
                    ),
                    _ProfileRow(
                      key: const Key('profile_offer_compare'),
                      icon: Icons.balance_rounded,
                      title: 'Compare job offers',
                      detail: 'Rank uploaded offers and plan the negotiation',
                      onTap: () => context.push('/offers/compare'),
                    ),
                    _ProfileRow(
                      key: const Key('profile_monthly_commitments'),
                      icon: Icons.event_repeat_outlined,
                      title: 'Monthly commitments',
                      detail: 'Confirmed repeats and obligations you add',
                      onTap: () => context.push('/monthly-commitments'),
                    ),
                    _ProfileRow(
                      key: const Key('profile_decision_sandbox'),
                      icon: Icons.compare_arrows_rounded,
                      title: 'Decision sandbox',
                      detail: 'Test move, vehicle, and job choices',
                      onTap: () => context.push('/decision-sandbox'),
                      isLast: true,
                    ),
                  ],
                ),
                const _SectionTitle('Sources and connections'),
                _ProfileGroup(
                  children: [
                    _ProfileRow(
                      icon: Icons.folder_copy_outlined,
                      title: 'Documents',
                      detail: documents.isEmpty
                          ? 'Add offer letters, payslips and proofs'
                          : '${documents.length} document${documents.length == 1 ? '' : 's'} stored',
                      status: documents.isEmpty
                          ? ProfileStatus.action
                          : ProfileStatus.complete,
                      onTap: () => context.push('/documents'),
                    ),
                    _ProfileRow(
                      icon: Icons.alternate_email_rounded,
                      title: 'Gmail salary inbox',
                      detail: 'Not connected',
                      status: ProfileStatus.optional,
                      onTap: () => context.push('/profile/connections'),
                    ),
                    _ProfileRow(
                      icon: Icons.account_balance_outlined,
                      title: 'Bank and salary account',
                      detail: 'Not connected',
                      status: ProfileStatus.optional,
                      onTap: () => context.push('/profile/connections'),
                      isLast: true,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SectionTitle('Privacy and account'),
                _ProfileGroup(
                  children: [
                    _ProfileRow(
                      icon: Icons.shield_outlined,
                      title: 'Data and permissions',
                      detail: 'Review sources, retention and deletion',
                      onTap: () => context.push('/profile/privacy'),
                    ),
                    const _CheckForUpdatesRow(),
                    _ProfileRow(
                      icon: Icons.help_outline_rounded,
                      title: 'Help and support',
                      detail: 'Get help with your account or data',
                      onTap: () => context.push('/help'),
                      isLast: true,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SectionTitle('Session'),
                _ProfileGroup(
                  children: [
                    _ProfileRow(
                      key: const Key('profile_sign_out'),
                      icon: Icons.logout_rounded,
                      title: 'Sign out',
                      detail:
                          'Remove this account and its cached data from this device',
                      status: ProfileStatus.danger,
                      onTap: () => _confirmProfileSignOut(context, ref),
                      isLast: true,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SectionTitle('Preview'),
                _ProfileGroup(
                  children: [
                    _ProfileRow(
                      key: const Key('open_sample_paycheck'),
                      icon: Icons.visibility_outlined,
                      title: paycheck.usingSampleData
                          ? 'Close sample insights'
                          : 'View sample insights',
                      detail: 'Preview only. Never mixed with your account.',
                      onTap: () {
                        final notifier = ref.read(paycheckProvider.notifier);
                        if (paycheck.usingSampleData) {
                          notifier.closeSampleData();
                        } else {
                          notifier.useSampleData();
                        }
                      },
                      isLast: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _profileCompletion({
    required UserAccount? user,
    required UserProfile profile,
    required bool panPresent,
    required int documentCount,
  }) {
    final checks = [
      user?.name.trim().isNotEmpty == true,
      user?.email.trim().isNotEmpty == true,
      user?.phoneNumber?.trim().isNotEmpty == true,
      profile.city.trim().isNotEmpty,
      profile.annualCTC > 0,
      profile.actualBasicSalary != null,
      panPresent,
      documentCount > 0,
    ];
    return checks.where((value) => value).length;
  }

  String _personalDetail(UserAccount? user) {
    if (user?.phoneNumber?.trim().isNotEmpty == true) {
      return '${user!.email} · ${user.phoneNumber}';
    }
    return user?.email.isNotEmpty == true ? user!.email : 'Add contact details';
  }

  String _employmentDetail(UserProfile profile, PaycheckState paycheck) {
    final employer = paycheck.employer.trim().isNotEmpty
        ? paycheck.employer
        : profile.employerName.trim().isNotEmpty
            ? profile.employerName
            : 'Employer not added';
    final ctc = profile.annualCTC > 0
        ? '₹${(profile.annualCTC / 100000).toStringAsFixed(1)}L CTC'
        : 'CTC not added';
    return '$employer · $ctc';
  }
}

class _CheckForUpdatesRow extends StatefulWidget {
  const _CheckForUpdatesRow();

  @override
  State<_CheckForUpdatesRow> createState() => _CheckForUpdatesRowState();
}

class _CheckForUpdatesRowState extends State<_CheckForUpdatesRow> {
  bool _checking = false;
  String? _status;
  int? _installedBuild;

  @override
  Widget build(BuildContext context) {
    return _ProfileRow(
      key: const Key('check_for_updates'),
      icon: Icons.system_update_alt_rounded,
      title: 'Check for updates',
      detail: _checking
          ? (_status ?? 'Checking for a newer build…')
          : _installedBuild == null
              ? 'Get the latest ARTH build'
              : 'Installed build $_installedBuild',
      onTap: _checking ? null : _check,
    );
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = 'Checking for a newer build…';
    });
    try {
      const service = AppUpdateService();
      final update = await service.checkForUpdates();
      if (!mounted) return;
      setState(() => _installedBuild = update.currentVersionCode);
      if (!update.isAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ARTH is up to date. Installed build ${update.currentVersionCode}.',
            ),
          ),
        );
        return;
      }

      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('ARTH ${update.versionName} is available'),
          content: Text(
            update.releaseNotes.trim().isEmpty
                ? 'Download and install this update? Your saved data will remain on this device.'
                : '${update.releaseNotes.trim()}\n\nYour saved data will remain on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Later'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Update now'),
            ),
          ],
        ),
      );
      if (shouldInstall != true || !mounted) return;

      setState(() => _status = 'Downloading and verifying update…');
      await service.downloadAndInstall(update);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Update verified. Confirm installation to finish.'),
        ),
      );
    } on AppUpdateException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'UPDATES_UNAVAILABLE' =>
          'This build receives updates from its app store.',
        'INSTALL_PERMISSION_REQUIRED' =>
          'Allow ARTH to install updates, then check again.',
        _ => error.message,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
          _status = null;
        });
      }
    }
  }
}

class ProfileDetailsScreen extends ConsumerStatefulWidget {
  const ProfileDetailsScreen({super.key});

  @override
  ConsumerState<ProfileDetailsScreen> createState() =>
      _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends ConsumerState<ProfileDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _city;
  late final TextEditingController _ctc;
  late final TextEditingController _basic;
  late final TextEditingController _hra;
  late final TextEditingController _professionalTax;
  EmploymentType _employment = EmploymentType.salaried;
  String _employerName = '';
  AgeGroup _ageGroup = AgeGroup.below30;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final account = ref.read(accountProfileProvider).asData?.value?.user ??
        ref.read(authProvider);
    final profile = ref.read(userProfileProvider);
    _name = TextEditingController(text: account?.name ?? profile.name);
    _phone = TextEditingController(text: account?.phoneNumber ?? '');
    _city = TextEditingController(text: profile.city);
    _ctc = TextEditingController(text: _amountText(profile.annualCTC));
    _basic =
        TextEditingController(text: _amountText(profile.actualBasicSalary));
    _hra = TextEditingController(text: _amountText(profile.actualHraReceived));
    _professionalTax = TextEditingController(
      text: _amountText(profile.actualProfessionalTax),
    );
    _employment = profile.employmentType;
    _employerName = profile.employerName;
    _ageGroup = profile.ageGroup;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    _ctc.dispose();
    _basic.dispose();
    _hra.dispose();
    _professionalTax.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final remoteAccount = ref.watch(accountProfileProvider).asData?.value?.user;
    final account = remoteAccount ?? auth;
    if (_phone.text.trim().isEmpty &&
        remoteAccount?.phoneNumber?.trim().isNotEmpty == true) {
      _phone.text = remoteAccount!.phoneNumber!;
    }
    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: const _ProfileAppBar(title: 'Personal details'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              'Keep this current so ARTH can separate assumptions from verified facts.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            ),
            const SizedBox(height: 24),
            const _FormSectionTitle('Identity'),
            _ProfileTextField(
              controller: _name,
              label: 'Full name',
              textCapitalization: TextCapitalization.words,
              validator: (value) => value == null || value.trim().length < 2
                  ? 'Enter your full name'
                  : null,
            ),
            const SizedBox(height: 16),
            _ReadOnlyField(label: 'Email address', value: account?.email ?? ''),
            const SizedBox(height: 16),
            _ProfileTextField(
              controller: _phone,
              label: 'Mobile number',
              hint: '+91 98765 43210',
              keyboardType: TextInputType.phone,
              validator: (value) {
                final phone = value?.replaceAll(' ', '').trim() ?? '';
                if (phone.isEmpty) return null;
                if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)) {
                  return 'Use country code, for example +919876543210';
                }
                return null;
              },
            ),
            const SizedBox(height: 28),
            const _FormSectionTitle('Employment'),
            _ProfileTextField(
              controller: _city,
              label: 'Work city',
              textCapitalization: TextCapitalization.words,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter your work city'
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<EmploymentType>(
              initialValue: _employment,
              decoration: const InputDecoration(labelText: 'Employment type'),
              items: const [
                DropdownMenuItem(
                  value: EmploymentType.salaried,
                  child: Text('Salaried'),
                ),
                DropdownMenuItem(
                  value: EmploymentType.selfEmployed,
                  child: Text('Self-employed'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _employment = value);
              },
            ),
            if (_employment == EmploymentType.salaried) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('profile_select_employer'),
                onPressed: () async {
                  final employer = await showEmployerPicker(
                    context,
                    currentValue: _employerName,
                  );
                  if (employer != null && mounted) {
                    setState(() => _employerName = employer);
                  }
                },
                icon: const Icon(Icons.business_outlined),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _employerName.isEmpty ? 'Add your employer' : _employerName,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _ProfileTextField(
              controller: _ctc,
              label: 'Annual CTC',
              hint: '1200000',
              prefixText: '₹ ',
              keyboardType: TextInputType.number,
              validator: (value) =>
                  (_amount(value) ?? 0) <= 0 ? 'Enter your annual CTC' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AgeGroup>(
              initialValue: _ageGroup,
              decoration: const InputDecoration(labelText: 'Age group'),
              items: AgeGroup.values
                  .map(
                    (group) => DropdownMenuItem(
                      value: group,
                      child: Text(group.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _ageGroup = value);
              },
            ),
            const SizedBox(height: 28),
            const _FormSectionTitle('Optional exact salary values'),
            Text(
              'Annual values from your offer letter or Form 16. '
              'Leave what you do not know empty.',
              style: PaycheckType.body(color: PaycheckColors.inkSoft),
            ),
            const SizedBox(height: 16),
            _ProfileTextField(
              controller: _basic,
              label: 'Annual basic salary',
              prefixText: '₹ ',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _ProfileTextField(
              controller: _hra,
              label: 'Annual HRA received',
              prefixText: '₹ ',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _ProfileTextField(
              controller: _professionalTax,
              label: 'Annual professional tax',
              prefixText: '₹ ',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 28),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: PaycheckColors.ink,
                minimumSize: const Size.fromHeight(54),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.control,
                ),
              ),
              onPressed: _saving ? null : _save,
              child: Text(
                _saving ? 'Saving…' : 'Save changes',
                style: PaycheckType.bodyStrong(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final current = ref.read(userProfileProvider);
    final auth = ref.read(authProvider);
    final phone = _phone.text.replaceAll(' ', '').trim();
    var accountSynced = true;

    try {
      try {
        await ref.read(accountProfileProvider.notifier).updateProfile(
              name: _name.text.trim(),
              phoneNumber: phone.isEmpty ? null : phone,
            );
      } catch (_) {
        accountSynced = false;
        if (auth != null) {
          await ref.read(authProvider.notifier).saveAccount(
                auth.copyWith(
                  name: _name.text.trim(),
                  phoneNumber: phone.isEmpty ? null : phone,
                ),
              );
        }
      }

      ref.read(userProfileProvider.notifier).update(
            current.copyWith(
              name: _name.text.trim(),
              email: auth?.email ?? current.email,
              city: _city.text.trim(),
              annualCTC: _amount(_ctc.text) ?? current.annualCTC,
              employmentType: _employment,
              employerName: _employerName,
              ageGroup: _ageGroup,
              actualBasicSalary: _amount(_basic.text),
              actualHraReceived: _amount(_hra.text),
              actualProfessionalTax: _amount(_professionalTax.text),
            ),
          );
      final profileSynced = await ref.read(userProfileProvider.notifier).save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accountSynced && profileSynced
                ? 'Profile updated.'
                : 'Saved on this device. Server sync is pending.',
          ),
        ),
      );
      context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static int? _amount(String? raw) {
    final normalized = raw?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    return normalized.isEmpty ? null : int.tryParse(normalized);
  }

  static String _amountText(int? amount) => amount == null ? '' : '$amount';
}

class ProfileConnectionsScreen extends ConsumerWidget {
  const ProfileConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(taxDocumentProvider).asData?.value ?? const [];
    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: const _ProfileAppBar(title: 'Connected sources'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'ARTH should only read a source after you choose it and understand what will be imported.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Available now'),
          _ProfileGroup(
            children: [
              _ProfileRow(
                icon: Icons.upload_file_outlined,
                title: 'Manual document upload',
                detail: documents.isEmpty
                    ? 'Offer letters, payslips and tax proofs'
                    : '${documents.length} document${documents.length == 1 ? '' : 's'} stored',
                status: ProfileStatus.complete,
                onTap: () => context.push('/documents'),
                isLast: true,
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _SectionTitle('Planned connections'),
          _ProfileGroup(
            children: [
              _ProfileRow(
                icon: Icons.alternate_email_rounded,
                title: 'Gmail salary inbox',
                detail: 'Needs restricted Google approval',
                status: ProfileStatus.unavailable,
                onTap: () => _showConnectorDisclosure(
                  context,
                  title: 'Gmail is not connected',
                  detail:
                      'Reading salary emails requires a restricted Gmail scope, Google verification and a reviewed server-side data policy. ARTH will not request broad inbox access before that work is complete.',
                ),
              ),
              _ProfileRow(
                icon: Icons.account_balance_outlined,
                title: 'Bank account via Account Aggregator',
                detail: 'Needs a licensed AA provider',
                status: ProfileStatus.unavailable,
                onTap: () => _showConnectorDisclosure(
                  context,
                  title: 'Bank feed is not connected',
                  detail:
                      'Indian bank data should be connected through a consent-based Account Aggregator. ARTH still needs an approved provider before it can request or receive this data.',
                ),
                isLast: true,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: PaycheckColors.contractSoft,
              borderRadius: AppRadius.card,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: PaycheckColors.contract,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment apps are not salary sources.',
                        style: PaycheckType.body(color: PaycheckColors.ink),
                      ),
                      const ArthDisclosure(
                        label: 'Why not',
                        detail:
                            'Transaction notifications are incomplete evidence. Payslips, bank credits and employer documents are stronger inputs.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showConnectorDisclosure(
    BuildContext context, {
    required String title,
    required String detail,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: PaycheckColors.paper,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: PaycheckType.title()),
              const SizedBox(height: 12),
              Text(detail,
                  style: PaycheckType.body(color: PaycheckColors.inkSoft)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TaxIdentityScreen extends ConsumerStatefulWidget {
  const TaxIdentityScreen({super.key});

  @override
  ConsumerState<TaxIdentityScreen> createState() => _TaxIdentityScreenState();
}

class _TaxIdentityScreenState extends ConsumerState<TaxIdentityScreen> {
  final _pan = TextEditingController();
  bool _consent = false;
  bool _saving = false;

  @override
  void dispose() {
    _pan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProfileProvider).asData?.value;
    final present = account?.pan.present == true;
    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: const _ProfileAppBar(title: 'Tax identity'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'PAN is optional. It helps ARTH keep tax records tied to the right identity.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 24),
          if (present) ...[
            _ProfileGroup(
              children: [
                _ProfileRow(
                  icon: Icons.verified_user_outlined,
                  title: account?.pan.maskedPan ?? 'PAN stored',
                  detail: 'Encrypted and stored separately',
                  status: ProfileStatus.complete,
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _saving ? null : _deletePan,
              child: const Text('Remove PAN'),
            ),
          ] else ...[
            _ProfileTextField(
              controller: _pan,
              label: 'PAN',
              hint: 'ABCDE1234F',
              textCapitalization: TextCapitalization.characters,
              validator: (_) => null,
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _consent,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'I consent to ARTH encrypting and storing my PAN for account matching.',
                style: PaycheckType.body(),
              ),
              onChanged: (value) => setState(() => _consent = value ?? false),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving || !_consent ? null : _savePan,
              child: Text(_saving ? 'Saving…' : 'Save PAN'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _savePan() async {
    final pan = _pan.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(pan)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter a valid PAN, for example ABCDE1234F.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(accountProfileProvider.notifier).savePan(pan);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PAN stored securely.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deletePan() async {
    setState(() => _saving = true);
    try {
      await ref.read(accountProfileProvider.notifier).deletePan();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class ProfilePrivacyScreen extends ConsumerWidget {
  const ProfilePrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(authProvider);
    final documents = ref.watch(taxDocumentProvider).asData?.value ?? const [];
    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: const _ProfileAppBar(title: 'Data and permissions'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const _SectionTitle('Current access'),
          _ProfileGroup(
            children: [
              _ProfileRow(
                icon: Icons.folder_copy_outlined,
                title: 'Uploaded documents',
                detail: '${documents.length} stored · You can remove each one',
                onTap: () => context.push('/documents'),
              ),
              const _ProfileRow(
                icon: Icons.alternate_email_rounded,
                title: 'Gmail data',
                detail: 'No access granted',
                status: ProfileStatus.complete,
              ),
              const _ProfileRow(
                icon: Icons.account_balance_outlined,
                title: 'Bank data',
                detail: 'No access granted',
                status: ProfileStatus.complete,
                isLast: true,
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _SectionTitle('Account security'),
          _ProfileGroup(
            children: [
              _ProfileRow(
                icon: Icons.mail_outline_rounded,
                title: 'Account email',
                detail: account?.email ?? 'Unavailable',
                isLast: true,
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _SectionTitle('Session'),
          _ProfileGroup(
            children: [
              _ProfileRow(
                icon: Icons.logout_rounded,
                title: 'Sign out on this device',
                detail: 'Server data stays in your account',
                onTap: () => _confirmProfileSignOut(context, ref),
                isLast: true,
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _SectionTitle('Danger zone'),
          _ProfileGroup(
            children: [
              _ProfileRow(
                icon: Icons.delete_forever_outlined,
                title: 'Delete tax and paycheck data',
                detail: 'Permanent. Your login account remains.',
                status: ProfileStatus.danger,
                onTap: () => _confirmDeleteData(context, ref),
                isLast: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDeleteData(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete financial data?'),
        content: const Text(
          'Removes your tax profile and paycheck data. '
          'Documents must be deleted separately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await ref.read(userProfileProvider.notifier).clearAll();
              ref.read(paycheckProvider.notifier).clearUserData();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Financial data deleted.')),
                );
              }
            },
            child: const Text('Delete data'),
          ),
        ],
      ),
    );
  }
}

void _confirmProfileSignOut(BuildContext context, WidgetRef ref) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text(
        'This removes the account and its cached data from this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () async {
            Navigator.pop(dialogContext);
            await signOutDeviceAndRouteToAuth(context, ref);
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
      ],
    ),
  );
}

enum ProfileStatus { complete, action, optional, unavailable, danger }

class _IdentityHeader extends StatelessWidget {
  final String name;
  final String email;
  final String initials;
  final VoidCallback onEdit;

  const _IdentityHeader({
    required this.name,
    required this.email,
    required this.initials,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: PaycheckColors.ink,
            shape: BoxShape.circle,
          ),
          child: Text(
            initials,
            style: PaycheckType.heading(color: Colors.white)
                .copyWith(fontSize: 20),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: PaycheckType.title()),
              const SizedBox(height: 4),
              Text(
                email.isEmpty ? 'Add your account email' : email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Edit personal details',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    );
  }
}

class _CompletenessPanel extends StatelessWidget {
  final int completion;

  const _CompletenessPanel({required this.completion});

  @override
  Widget build(BuildContext context) {
    final progress = completion / 8;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PaycheckColors.contractSoft,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: PaycheckColors.contract.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  completion == 8
                      ? 'Profile complete'
                      : 'Improve result accuracy',
                  style: PaycheckType.bodyStrong(),
                ),
              ),
              Text(
                '$completion of 8',
                style: PaycheckType.utility(color: PaycheckColors.contract),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            completion == 8
                ? 'Core identity, income, and evidence are on file.'
                : 'Add salary values, PAN, or documents.',
            style: PaycheckType.utility(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: PaycheckColors.paper,
              valueColor: const AlwaysStoppedAnimation(PaycheckColors.contract),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const _ProfileAppBar({required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/paycheck/you');
          }
        },
      ),
      title: Text(title, style: PaycheckType.heading()),
      centerTitle: false,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text, style: PaycheckType.heading()),
    );
  }
}

class _FormSectionTitle extends StatelessWidget {
  final String text;

  const _FormSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: PaycheckType.heading()),
    );
  }
}

class _ProfileGroup extends StatelessWidget {
  final List<Widget> children;

  const _ProfileGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        borderRadius: AppRadius.card,
        border: Border.all(color: PaycheckColors.line),
      ),
      child: Column(children: children),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  final ProfileStatus? status;
  final bool isLast;

  const _ProfileRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
    this.status,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (status) {
      ProfileStatus.complete => PaycheckColors.matched,
      ProfileStatus.action => PaycheckColors.claim,
      ProfileStatus.optional => PaycheckColors.inkSoft,
      ProfileStatus.unavailable => PaycheckColors.pending,
      ProfileStatus.danger => Colors.red.shade700,
      null => PaycheckColors.inkSoft,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: const Radius.circular(16),
        bottom: isLast ? const Radius.circular(16) : Radius.zero,
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: PaycheckColors.line)),
        ),
        child: Row(
          children: [
            Icon(icon, color: statusColor, size: 23),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: PaycheckType.bodyStrong()),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PaycheckType.body(color: PaycheckColors.inkSoft),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: PaycheckColors.inkSoft,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? prefixText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  const _ProfileTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.prefixText,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
      ),
      child: Text(
        value.isEmpty ? 'No email available' : value,
        style: PaycheckType.body(color: PaycheckColors.inkSoft),
      ),
    );
  }
}
