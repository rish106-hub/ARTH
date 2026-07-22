import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user_profile.dart';
import '../theme/app_theme.dart';

class TaxJourneyScene extends StatefulWidget {
  final int step;
  final UserProfile profile;
  final String chapter;
  final String helper;
  final Color accent;

  const TaxJourneyScene({
    super.key,
    required this.step,
    required this.profile,
    required this.chapter,
    required this.helper,
    required this.accent,
  });

  @override
  State<TaxJourneyScene> createState() => _TaxJourneySceneState();
}

class _TaxJourneySceneState extends State<TaxJourneyScene> {
  bool _showWhy = false;

  @override
  void didUpdateWidget(covariant TaxJourneyScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step) _showWhy = false;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _JourneySnapshot.forStep(widget.step, widget.profile);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      label:
          _showWhy ? 'Close why this matters' : 'Open why this answer matters',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.card,
          onTap: () => setState(() => _showWhy = !_showWhy),
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : AppMotion.medium,
            height: 156,
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: AppRadius.card,
              border: Border.all(
                color: _showWhy
                    ? widget.accent.withValues(alpha: 0.55)
                    : AppColors.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textPrimary.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : AppMotion.medium,
              switchInCurve: AppMotion.standard,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _showWhy
                  ? _WhyPanel(
                      key: ValueKey('why-${widget.step}'),
                      chapter: widget.chapter,
                      helper: widget.helper,
                      accent: widget.accent,
                    )
                  : _SnapshotPanel(
                      key: ValueKey('snapshot-${widget.step}'),
                      step: widget.step,
                      profile: widget.profile,
                      snapshot: snapshot,
                      chapter: widget.chapter,
                      accent: widget.accent,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SnapshotPanel extends StatelessWidget {
  final int step;
  final UserProfile profile;
  final _JourneySnapshot snapshot;
  final String chapter;
  final Color accent;

  const _SnapshotPanel({
    super.key,
    required this.step,
    required this.profile,
    required this.snapshot,
    required this.chapter,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        chapter.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.sectionLabel(color: accent)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: accent,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  snapshot.label,
                  style: AppTextStyles.micro(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: double.infinity,
                  height: 26,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        snapshot.value,
                        maxLines: 1,
                        style: AppTextStyles.h2().copyWith(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 102,
            height: 124,
            decoration: const BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: AppRadius.card,
            ),
            child: _StepVisual(
              step: step,
              profile: profile,
              icon: snapshot.icon,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepVisual extends StatelessWidget {
  final int step;
  final UserProfile profile;
  final IconData icon;

  const _StepVisual({
    required this.step,
    required this.profile,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: switch (step) {
        0 => _IncomeBars(value: profile.annualCTC),
        1 => _EmploymentCard(
            salaried: profile.employmentType == EmploymentType.salaried,
          ),
        2 => const _CityLine(),
        3 => _HouseKey(active: profile.paysRent),
        4 => _ReceiptCheck(active: profile.hasHRA),
        5 => _LimitRing(value: profile.invested80C, maximum: 150000),
        6 => _HouseKey(active: profile.hasHomeLoan, loan: true),
        7 => _CoinStack(active: profile.hasNPS),
        8 => _ShieldCover(
            active: profile.hasHealthInsuranceSelf ||
                profile.hasHealthInsuranceParents,
          ),
        9 => _EducationStack(active: profile.hasEducationLoan),
        10 => _GivingReceipt(active: profile.hasDonations),
        _ => _FinalCheck(icon: icon),
      },
    );
  }
}

class _IncomeBars extends StatelessWidget {
  final int value;

  const _IncomeBars({required this.value});

  @override
  Widget build(BuildContext context) {
    final ratio = (value / 6000000).clamp(0.12, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('₹',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _Bar(height: 22 + 20 * ratio),
            const SizedBox(width: 6),
            _Bar(height: 34 + 28 * ratio),
            const SizedBox(width: 6),
            _Bar(height: 48 + 30 * ratio, dark: true),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double height;
  final bool dark;

  const _Bar({required this.height, this.dark = false});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: dark ? AppColors.textPrimary : AppColors.bgCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            border: dark ? null : Border.all(color: AppColors.border),
          ),
        ),
      );
}

class _EmploymentCard extends StatelessWidget {
  final bool salaried;

  const _EmploymentCard({required this.salaried});

  @override
  Widget build(BuildContext context) => Center(
        child: Transform.rotate(
          angle: -0.08,
          child: Container(
            width: 68,
            height: 88,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.textPrimary, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  salaried ? Icons.badge_outlined : Icons.storefront_outlined,
                  size: 24,
                ),
                const Spacer(),
                Container(height: 5, color: AppColors.textPrimary),
                const SizedBox(height: 5),
                Container(width: 32, height: 4, color: AppColors.border),
              ],
            ),
          ),
        ),
      );
}

class _CityLine extends StatelessWidget {
  const _CityLine();

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.bottomCenter,
        children: [
          const Positioned(
              top: 4, right: 3, child: Icon(Icons.location_on, size: 24)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _building(38, 18),
              _building(66, 24, dark: true),
              _building(49, 18),
            ],
          ),
        ],
      );

  Widget _building(double height, double width, {bool dark = false}) =>
      Container(
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: dark ? AppColors.textPrimary : AppColors.bgCard,
          border: Border.all(color: AppColors.textPrimary),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
      );
}

class _HouseKey extends StatelessWidget {
  final bool active;
  final bool loan;

  const _HouseKey({required this.active, this.loan = false});

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.house_outlined,
              size: 74,
              color: active ? AppColors.textPrimary : AppColors.textMuted),
          Positioned(
            right: 0,
            bottom: 10,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                  color: AppColors.textPrimary, shape: BoxShape.circle),
              child: Icon(loan ? Icons.percent_rounded : Icons.key_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      );
}

class _ReceiptCheck extends StatelessWidget {
  final bool active;

  const _ReceiptCheck({required this.active});

  @override
  Widget build(BuildContext context) => Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 60,
              height: 86,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  border: Border.all(color: AppColors.border)),
              child: Column(
                  children: List.generate(
                      4,
                      (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Container(
                                height: 4,
                                color: i == 0
                                    ? AppColors.textPrimary
                                    : AppColors.border),
                          ))),
            ),
            Positioned(
                right: -12,
                bottom: -5,
                child: Icon(active ? Icons.check_circle : Icons.remove_circle,
                    size: 32)),
          ],
        ),
      );
}

class _LimitRing extends StatelessWidget {
  final int value;
  final int maximum;

  const _LimitRing({required this.value, required this.maximum});

  @override
  Widget build(BuildContext context) {
    final progress = (value / maximum).clamp(0.0, 1.0);
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.square(
          dimension: 76,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 9,
            strokeCap: StrokeCap.round,
            backgroundColor: AppColors.bgCard,
            color: AppColors.textPrimary,
          ),
        ),
        Text('${(progress * 100).round()}%',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _CoinStack extends StatelessWidget {
  final bool active;

  const _CoinStack({required this.active});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.savings_outlined,
              size: 48,
              color: active ? AppColors.textPrimary : AppColors.textMuted),
          const SizedBox(height: 8),
          ...List.generate(
              3,
              (i) => Container(
                    width: 62 - i * 7,
                    height: 9,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: BoxDecoration(
                        color:
                            i == 0 ? AppColors.textPrimary : AppColors.bgCard,
                        borderRadius: AppRadius.pill,
                        border: Border.all(color: AppColors.textPrimary)),
                  )),
        ],
      );
}

class _ShieldCover extends StatelessWidget {
  final bool active;

  const _ShieldCover({required this.active});

  @override
  Widget build(BuildContext context) => Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.shield_outlined,
                size: 82,
                color: active ? AppColors.textPrimary : AppColors.textMuted),
            const Icon(Icons.add_rounded, size: 30),
          ],
        ),
      );
}

class _EducationStack extends StatelessWidget {
  final bool active;

  const _EducationStack({required this.active});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school_outlined,
              size: 49,
              color: active ? AppColors.textPrimary : AppColors.textMuted),
          const SizedBox(height: 8),
          Container(width: 70, height: 9, color: AppColors.textPrimary),
          const SizedBox(height: 4),
          Container(width: 58, height: 8, color: AppColors.bgCard),
        ],
      );
}

class _GivingReceipt extends StatelessWidget {
  final bool active;

  const _GivingReceipt({required this.active});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 66,
          height: 94,
          decoration: BoxDecoration(
              color: AppColors.bgCard,
              border: Border.all(color: AppColors.textPrimary)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(active ? Icons.favorite : Icons.favorite_border, size: 32),
              const SizedBox(height: 11),
              Container(width: 36, height: 5, color: AppColors.textPrimary),
              const SizedBox(height: 5),
              Container(width: 26, height: 4, color: AppColors.border),
            ],
          ),
        ),
      );
}

class _FinalCheck extends StatelessWidget {
  final IconData icon;

  const _FinalCheck({required this.icon});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
              color: AppColors.textPrimary, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 38),
        ),
      );
}

class _WhyPanel extends StatelessWidget {
  final String chapter;
  final String helper;
  final Color accent;

  const _WhyPanel({
    super.key,
    required this.chapter,
    required this.helper,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: AppRadius.card,
            ),
            child: const Icon(
              Icons.auto_awesome_outlined,
              size: 19,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Why $chapter matters',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.h3().copyWith(fontSize: 16),
                      ),
                    ),
                    Icon(Icons.close_rounded, size: 17, color: accent),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  helper,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.micro(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneySnapshot {
  final String label;
  final String value;
  final IconData icon;

  const _JourneySnapshot({
    required this.label,
    required this.value,
    required this.icon,
  });

  static final _money = NumberFormat.decimalPattern('en_IN');

  static String _rupees(int value) => '₹${_money.format(value)}';

  static _JourneySnapshot forStep(int step, UserProfile profile) {
    switch (step) {
      case 0:
        return _JourneySnapshot(
          label: 'Income base',
          value: '${_rupees(profile.annualCTC)} a year',
          icon: Icons.receipt_long_outlined,
        );
      case 1:
        return _JourneySnapshot(
          label: 'How you earn',
          value: profile.employmentType == EmploymentType.salaried
              ? 'Salaried income'
              : 'Independent income',
          icon: Icons.work_outline_rounded,
        );
      case 2:
        return _JourneySnapshot(
          label: 'Your tax city',
          value: profile.isMetroCity
              ? '${profile.city} · Metro HRA'
              : '${profile.city} · Non-metro HRA',
          icon: Icons.location_city_outlined,
        );
      case 3:
        return _JourneySnapshot(
          label: 'Rent trail',
          value: profile.paysRent
              ? '${_rupees(profile.monthlyRent)} each month'
              : 'No rent added',
          icon: Icons.key_outlined,
        );
      case 4:
        return _JourneySnapshot(
          label: 'Payslip signal',
          value: profile.hasHRA ? 'HRA found' : 'No HRA recorded',
          icon: Icons.home_work_outlined,
        );
      case 5:
        return _JourneySnapshot(
          label: '80C folder',
          value: '${_rupees(profile.invested80C)} of ₹1,50,000',
          icon: Icons.folder_copy_outlined,
        );
      case 6:
        return _JourneySnapshot(
          label: 'Property trail',
          value: profile.hasHomeLoan
              ? '${_rupees(profile.homeLoanInterest)} interest'
              : 'No home loan added',
          icon: Icons.house_outlined,
        );
      case 7:
        return _JourneySnapshot(
          label: 'Retirement pocket',
          value: profile.hasNPS
              ? '${_rupees(profile.npsExtraContribution)} extra NPS'
              : 'No extra NPS added',
          icon: Icons.savings_outlined,
        );
      case 8:
        final covered =
            profile.hasHealthInsuranceSelf || profile.hasHealthInsuranceParents;
        return _JourneySnapshot(
          label: 'Health cover',
          value: covered ? 'Policy cover found' : 'No cover added yet',
          icon: Icons.health_and_safety_outlined,
        );
      case 9:
        return _JourneySnapshot(
          label: 'Education interest',
          value: profile.hasEducationLoan
              ? '${_rupees(profile.educationLoanInterest)} recorded'
              : 'No education loan',
          icon: Icons.school_outlined,
        );
      case 10:
        return _JourneySnapshot(
          label: 'Giving record',
          value: profile.hasDonations
              ? '${_rupees(profile.donationAmount)} donated'
              : 'No donations added',
          icon: Icons.volunteer_activism_outlined,
        );
      default:
        return _JourneySnapshot(
          label: 'Final profile check',
          value: 'Age band: ${profile.ageGroup.label}',
          icon: Icons.verified_outlined,
        );
    }
  }
}
