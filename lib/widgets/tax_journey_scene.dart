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
            height: 148,
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
            child: Stack(
              children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.16,
                    child: Image.asset(
                      'assets/images/tax_journey.png',
                      fit: BoxFit.cover,
                      alignment: Alignment(
                        -0.9 + (widget.step / 11) * 1.8,
                        0.15,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.bgCard.withValues(alpha: 0.58),
                  ),
                ),
                AnimatedSwitcher(
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
                          snapshot: snapshot,
                          chapter: widget.chapter,
                          accent: widget.accent,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SnapshotPanel extends StatelessWidget {
  final int step;
  final _JourneySnapshot snapshot;
  final String chapter;
  final Color accent;

  const _SnapshotPanel({
    super.key,
    required this.step,
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
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(snapshot.icon, size: 15, color: accent),
                    ),
                    const SizedBox(width: 8),
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
                      size: 16,
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
          const SizedBox(width: 14),
          _JourneyDial(step: step, accent: accent),
        ],
      ),
    );
  }
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

class _JourneyDial extends StatelessWidget {
  final int step;
  final Color accent;

  const _JourneyDial({required this.step, required this.accent});

  @override
  Widget build(BuildContext context) {
    final progress = (step + 1) / 12;
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              backgroundColor: AppColors.bgSurface,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(progress * 100).round()}%',
                style: AppTextStyles.h3(color: accent),
              ),
              Text(
                'mapped',
                style: AppTextStyles.micro(color: AppColors.textSecondary),
              ),
            ],
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
