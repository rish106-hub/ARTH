import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../models/user_profile.dart';
import '../models/tax_rule_set.dart';
import '../models/payslip_tax_prefill.dart';
import '../providers/tax_document_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/tax_year_provider.dart';
import '../providers/user_profile_provider.dart';
import '../widgets/premium_ui.dart';
import '../widgets/question_progress_bar.dart';
import '../widgets/tax_journey_scene.dart';
import '../widgets/employer_picker.dart';

/// The diagnostic's question steps. The flow shows a gated SUBSET of these
/// (doctor-style): deduction steps are skipped when the new regime is a clear
/// win, and HRA is skipped for the self-employed.
enum _QStep {
  ctc,
  employment,
  business,
  regime,
  city,
  rent,
  hra,
  eightyC,
  homeLoan,
  nps,
  health,
  educationLoan,
  donations,
  extraDeductions,
  otherIncome,
  age,
}

extension _QStepX on _QStep {
  /// Stable index into the illustration set (`_JourneySnapshot.forStep`), which
  /// is keyed to a question's MEANING, not its position in the gated list.
  int get visualIndex => switch (this) {
        _QStep.ctc => 0,
        _QStep.employment => 1,
        _QStep.business => 1,
        _QStep.regime => 1,
        _QStep.city => 2,
        _QStep.rent => 3,
        _QStep.hra => 4,
        _QStep.eightyC => 5,
        _QStep.homeLoan => 6,
        _QStep.nps => 7,
        _QStep.health => 8,
        _QStep.educationLoan => 9,
        _QStep.donations => 10,
        _QStep.extraDeductions => 8,
        _QStep.otherIncome => 0,
        _QStep.age => 11,
      };
}

/// Whether the old-regime deduction questions are worth asking. When the new
/// regime already makes tax zero (income within the rebate + standard-deduction
/// band) there is nothing the old regime can beat, so we skip them.
bool _needsDeductionInputs(UserProfile p, TaxRuleSet? rs) {
  switch (p.regimePreference) {
    case RegimePreference.oldRegime:
      return true;
    case RegimePreference.newRegime:
      return false;
    case RegimePreference.auto:
      final rebateLimit = rs?.newRegime.rebate87ALimit ?? 1200000;
      final sd = p.employmentType == EmploymentType.salaried
          ? (rs?.newRegime.standardDeduction ?? 75000)
          : 0;
      return p.annualCTC > rebateLimit + sd;
  }
}

/// Fields of the latest confirmed offer letter, tagged with `__documentId`, or
/// null. Watches the document list so a newly-confirmed offer triggers a
/// rebuild.
Map<String, dynamic>? _confirmedOfferLetterFields(WidgetRef ref) {
  final docs = ref.watch(taxDocumentProvider).asData?.value;
  if (docs == null) return null;
  final offers = docs
      .where((d) =>
          d.active &&
          d.documentType == 'offerLetter' &&
          !d.isPayslip &&
          d.parsed &&
          d.confirmedFields.isNotEmpty)
      .toList()
    ..sort((a, b) => (b.reviewedAt ?? b.createdAt ?? DateTime(1970))
        .compareTo(a.reviewedAt ?? a.createdAt ?? DateTime(1970)));
  if (offers.isEmpty) return null;
  return {...offers.first.confirmedFields, '__documentId': offers.first.id};
}

/// The ordered, gated list of steps for the current profile.
List<_QStep> _visibleSteps(UserProfile p, TaxRuleSet? rs) {
  final steps = <_QStep>[_QStep.ctc, _QStep.employment];
  if (p.employmentType == EmploymentType.selfEmployed) {
    steps.add(_QStep.business); // presumptive income
  }
  steps.add(_QStep.regime);
  if (_needsDeductionInputs(p, rs)) {
    steps.add(_QStep.city);
    steps.add(_QStep.rent);
    if (p.employmentType == EmploymentType.salaried) {
      steps.add(_QStep.hra); // self-employed cannot claim HRA
    }
    steps.addAll(const [
      _QStep.eightyC,
      _QStep.homeLoan,
      _QStep.nps,
      _QStep.health,
      _QStep.educationLoan,
      _QStep.donations,
      _QStep.extraDeductions, // 80U / 80DD / 80DDB / 80EEB
    ]);
  }
  // Other income (capital gains, rent, misc) is taxed under BOTH regimes, so
  // it is always asked.
  steps.add(_QStep.otherIncome);
  steps.add(_QStep.age);
  return steps;
}

class QuestionsScreen extends ConsumerStatefulWidget {
  final bool paycheckMode;

  const QuestionsScreen({super.key, this.paycheckMode = false});

  @override
  ConsumerState<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends ConsumerState<QuestionsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<double> _slideAnim;
  late UserProfile _entryProfile;
  int _pos = 0; // position within the gated visible-steps list
  bool _finishing = false;
  String? _appliedPayslipId;
  String? _appliedForm16Id;
  String? _appliedOfferId;
  String? _appliedProofKey;

  List<_QStep> _currentSteps() {
    final p = ref.read(userProfileProvider);
    final rs = ref.read(activeTaxRuleSetProvider).asData?.value;
    return _visibleSteps(p, rs);
  }

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut);
    _slideCtrl.value = 1.0;
    _entryProfile = ref.read(userProfileProvider);
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.lightImpact();
    // Recompute against the latest profile: the answer just given (e.g. regime
    // choice, employment type) may have added or removed later steps.
    final steps = _currentSteps();
    if (_pos < steps.length - 1) {
      setState(() => _pos++);
      _slideCtrl.reset();
      _slideCtrl.forward();
    } else {
      _finish();
    }
  }

  Future<void> _prev() async {
    if (_pos > 0) {
      HapticFeedback.lightImpact();
      setState(() => _pos--);
      _slideCtrl.reset();
      _slideCtrl.forward();
    } else {
      await _exitDiagnostic();
    }
  }

  Future<void> _exitDiagnostic() async {
    HapticFeedback.lightImpact();
    await ref.read(userProfileProvider.notifier).restoreDraft(_entryProfile);
    final complete =
        await ref.read(userProfileProvider.notifier).isOnboardingComplete();
    if (!mounted) return;
    if (widget.paycheckMode) {
      context.go('/paycheck/you');
    } else {
      context.go(complete ? '/profile' : '/discover');
    }
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    try {
      await ref.read(userProfileProvider.notifier).save();
      ref.invalidate(completedTaxProfileProvider);
      ref.invalidate(taxResultProvider);
      await computeAndSyncCurrentTaxResult(ref);
      if (mounted) {
        context.go(
          widget.paycheckMode ? '/tax-plan/results' : '/gap-reveal',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Tax plan build failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not build your tax plan. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _finishing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final payslipPrefill = ref.watch(payslipTaxPrefillProvider);
    final form16Prefill = ref.watch(form16TaxPrefillProvider);
    if (payslipPrefill != null &&
        _appliedPayslipId != payslipPrefill.documentId) {
      _appliedPayslipId = payslipPrefill.documentId;
      Future<void>.microtask(() {
        if (!mounted) return;
        ref
            .read(userProfileProvider.notifier)
            .applyPayslipPrefill(payslipPrefill);
      });
    }
    // Form 16 is the authoritative annual statement — apply after the payslip
    // so its true annual gross wins, while the payslip's granular basic/HRA/80C
    // values are preserved.
    if (form16Prefill != null && _appliedForm16Id != form16Prefill.documentId) {
      _appliedForm16Id = form16Prefill.documentId;
      Future<void>.microtask(() {
        if (!mounted) return;
        ref
            .read(userProfileProvider.notifier)
            .applyForm16Prefill(form16Prefill);
      });
    }
    // Offer letter fills income/employer only when there is no payslip or
    // Form 16 (which are both more authoritative).
    if (payslipPrefill == null && form16Prefill == null) {
      final offer = _confirmedOfferLetterFields(ref);
      final offerId = offer?['__documentId']?.toString();
      if (offer != null && offerId != null && _appliedOfferId != offerId) {
        _appliedOfferId = offerId;
        Future<void>.microtask(() {
          if (!mounted) return;
          ref
              .read(userProfileProvider.notifier)
              .applyConfirmedOfferLetter(offer);
        });
      }
    }
    // Proof documents fill any remaining gaps (rent, premium, loan interest,
    // donation, 80C) without overriding the sources above.
    final proofPrefill = ref.watch(proofPrefillProvider);
    if (proofPrefill != null) {
      final key = proofPrefill.values.toString();
      if (_appliedProofKey != key) {
        _appliedProofKey = key;
        Future<void>.microtask(() {
          if (!mounted) return;
          ref
              .read(userProfileProvider.notifier)
              .applyProofPrefill(proofPrefill);
        });
      }
    }

    if (_finishing) {
      return const _BuildingPlanScreen();
    }

    final ruleSet = ref.watch(activeTaxRuleSetProvider).asData?.value;
    final steps = _visibleSteps(profile, ruleSet);
    final pos = _pos.clamp(0, steps.length - 1);
    final current = steps[pos];
    final meta = _DiagnosticMeta.forQStep(current);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _exitDiagnostic();
        }
      },
      child: ArthScaffold(
        child: SafeArea(
          child: Column(
            children: [
              // Progress bar + back
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_rounded,
                            size: 18,
                            color: PaycheckColors.textSecondary,
                          ),
                          onPressed: _prev,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: QuestionProgressBar(
                            current: pos,
                            total: steps.length,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: _ChapterMarker(meta: meta, step: current.visualIndex),
              ),

              const SizedBox(height: 22),

              // Question content — slides in
              Expanded(
                child: AnimatedBuilder(
                  animation: _slideAnim,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, 16 * (1 - _slideAnim.value)),
                    child: Opacity(opacity: _slideAnim.value, child: child),
                  ),
                  child: _QuestionVisualScope(
                    step: current.visualIndex,
                    profile: profile,
                    meta: meta,
                    child: _buildStep(context, profile, current),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, UserProfile p, _QStep step) {
    switch (step) {
      case _QStep.ctc:
        return _Q01CTC(
          profile: p,
          payslipPrefill: ref.read(payslipTaxPrefillProvider),
          onNext: _next,
        );
      case _QStep.employment:
        return _Q02Employment(
          profile: p,
          payslipPrefill: ref.read(payslipTaxPrefillProvider),
          onNext: _next,
        );
      case _QStep.business:
        return _QBusiness(profile: p, onNext: _next);
      case _QStep.regime:
        return _QRegime(profile: p, onNext: _next);
      case _QStep.city:
        return _Q03City(profile: p, onNext: _next);
      case _QStep.rent:
        return _Q04Rent(profile: p, onNext: _next);
      case _QStep.hra:
        return _Q05HRA(
          profile: p,
          payslipPrefill: ref.read(payslipTaxPrefillProvider),
          onNext: _next,
        );
      case _QStep.eightyC:
        return _Q06EightyC(profile: p, onNext: _next);
      case _QStep.homeLoan:
        return _Q07HomeLoan(profile: p, onNext: _next);
      case _QStep.nps:
        return _Q08NPS(profile: p, onNext: _next);
      case _QStep.health:
        return _Q09HealthInsurance(profile: p, onNext: _next);
      case _QStep.educationLoan:
        return _Q10EducationLoan(profile: p, onNext: _next);
      case _QStep.donations:
        return _Q11Donations(profile: p, onNext: _next);
      case _QStep.extraDeductions:
        return _QExtraDeductions(profile: p, onNext: _next);
      case _QStep.otherIncome:
        return _QOtherIncome(profile: p, onNext: _next);
      case _QStep.age:
        return _Q12Age(profile: p, onNext: _next);
    }
  }
}

class _QuestionVisualScope extends InheritedWidget {
  final int step;
  final UserProfile profile;
  final _DiagnosticMeta meta;

  const _QuestionVisualScope({
    required this.step,
    required this.profile,
    required this.meta,
    required super.child,
  });

  static _QuestionVisualScope of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_QuestionVisualScope>()!;
  }

  @override
  bool updateShouldNotify(_QuestionVisualScope oldWidget) {
    return step != oldWidget.step ||
        profile != oldWidget.profile ||
        meta != oldWidget.meta;
  }
}

class _DiagnosticMeta {
  final String title;
  final String helper;
  final Color color;

  const _DiagnosticMeta({
    required this.title,
    required this.helper,
    required this.color,
  });

  static _DiagnosticMeta forQStep(_QStep step) {
    switch (step) {
      case _QStep.ctc:
      case _QStep.employment:
      case _QStep.business:
      case _QStep.regime:
      case _QStep.otherIncome:
        return const _DiagnosticMeta(
          title: 'Income profile',
          helper: 'First, the shape of your income.',
          color: PaycheckColors.gold,
        );
      case _QStep.city:
      case _QStep.rent:
      case _QStep.hra:
        return const _DiagnosticMeta(
          title: 'Housing and rent',
          helper: 'Next, where and how you live.',
          color: PaycheckColors.teal,
        );
      case _QStep.eightyC:
      case _QStep.homeLoan:
      case _QStep.nps:
      case _QStep.health:
      case _QStep.educationLoan:
      case _QStep.donations:
      case _QStep.extraDeductions:
        return const _DiagnosticMeta(
          title: 'Deductions scan',
          helper: 'Now we check the deductions that apply to you.',
          color: PaycheckColors.info,
        );
      case _QStep.age:
        return const _DiagnosticMeta(
          title: 'Final checks',
          helper: 'A few final details before the result.',
          color: PaycheckColors.amber,
        );
    }
  }
}

class _ChapterMarker extends StatelessWidget {
  final _DiagnosticMeta meta;
  final int step;

  const _ChapterMarker({required this.meta, required this.step});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: AppMotion.medium,
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(meta.title,
                  style: PaycheckType.sectionLabel(
                    color: PaycheckColors.textPrimary,
                  )),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: AppMotion.medium,
                child: Text(
                  meta.helper,
                  key: ValueKey(step ~/ 3),
                  style: PaycheckType.caption(
                    color: PaycheckColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BuildingPlanScreen extends StatefulWidget {
  const _BuildingPlanScreen();

  @override
  State<_BuildingPlanScreen> createState() => _BuildingPlanScreenState();
}

class _BuildingPlanScreenState extends State<_BuildingPlanScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ArthScaffold(
      showAmbientGlow: false,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final value = reduceMotion ? 1.0 : _controller.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    'Building your first plan.',
                    style: PaycheckType.h1().copyWith(fontSize: 40),
                  ),
                  const SizedBox(height: 34),
                  _BuildStep(
                    label: 'Compare tax regimes',
                    complete: value > 0.25,
                  ),
                  _BuildStep(
                    label: 'Check deduction gaps',
                    complete: value > 0.55,
                  ),
                  _BuildStep(
                    label: 'Choose the next action',
                    complete: value > 0.82,
                  ),
                  const Spacer(flex: 2),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BuildStep extends StatelessWidget {
  final String label;
  final bool complete;

  const _BuildStep({required this.label, required this.complete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          AnimatedContainer(
            duration: AppMotion.fast,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: complete ? PaycheckColors.primary : PaycheckColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(
              complete ? Icons.check_rounded : Icons.more_horiz_rounded,
              size: 17,
              color: complete ? Colors.white : PaycheckColors.textMuted,
            ),
          ),
          const SizedBox(width: 14),
          Text(label, style: PaycheckType.bodyMedium()),
        ],
      ),
    );
  }
}

// ─── Q00: Name ────────────────────────────────────────────────────────────────
class _Q00Name extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _Q00Name({required this.profile, required this.onNext});

  @override
  ConsumerState<_Q00Name> createState() => _Q00NameState();
}

class _Q00NameState extends ConsumerState<_Q00Name> {
  late TextEditingController _textCtrl;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.profile.name);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    ref
        .read(userProfileProvider.notifier)
        .updateField((p) => p.copyWith(name: value.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: "What's your name?",
      microCopy: "This helps us personalize your report.",
      content: TextField(
        controller: _textCtrl,
        onChanged: _onTextChanged,
        decoration: InputDecoration(
          hintText: 'Enter your name',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: PaycheckColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: PaycheckColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: PaycheckColors.gold, width: 2),
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
        style: PaycheckType.body(
          color: PaycheckColors.textPrimary,
        ).copyWith(fontSize: 16),
        cursorColor: PaycheckColors.gold,
      ),
      onNext: widget.onNext,
      canProceed: _textCtrl.text.trim().isNotEmpty,
    );
  }
}

// ─── Q00: Email ───────────────────────────────────────────────────────────────
class _Q00Email extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _Q00Email({required this.profile, required this.onNext});

  @override
  ConsumerState<_Q00Email> createState() => _Q00EmailState();
}

class _Q00EmailState extends ConsumerState<_Q00Email> {
  late TextEditingController _textCtrl;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.profile.email);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    ref
        .read(userProfileProvider.notifier)
        .updateField((p) => p.copyWith(email: value.trim()));
  }

  bool _isValidEmail(String email) {
    return email.contains('@') && email.contains('.') && email.length > 5;
  }

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: "What's your email?",
      microCopy: "We'll send your report here. No spam.",
      content: TextField(
        controller: _textCtrl,
        onChanged: _onTextChanged,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          hintText: 'your.email@domain.com',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: PaycheckColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: PaycheckColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: PaycheckColors.gold, width: 2),
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
        style: PaycheckType.body(
          color: PaycheckColors.textPrimary,
        ).copyWith(fontSize: 16),
        cursorColor: PaycheckColors.gold,
      ),
      onNext: widget.onNext,
      canProceed: _isValidEmail(_textCtrl.text.trim()),
    );
  }
}

// ─── SHARED QUESTION SCAFFOLD ─────────────────────────────────────────────────
class _QLayout extends StatelessWidget {
  final String question;
  final String? microCopy;
  final Widget content;
  final VoidCallback? onNext;
  final bool canProceed;
  final String nextLabel;

  const _QLayout({
    required this.question,
    this.microCopy,
    required this.content,
    this.onNext,
    this.canProceed = true, // ignore: unused_element_parameter
    this.nextLabel = 'Continue', // ignore: unused_element_parameter
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final visual = _QuestionVisualScope.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final visualHeight = bottomInset > 0
        ? 0.0
        : screenHeight < 760
            ? 174.0
            : 218.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: PaycheckType.h1().copyWith(fontSize: 32, height: 1.08),
          ),
          if (microCopy != null) ...[
            const SizedBox(height: 8),
            Text(
              microCopy!,
              style: PaycheckType.caption(color: PaycheckColors.textSecondary),
            ),
          ],
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.standard,
            height: visualHeight,
            child: visualHeight == 0
                ? const SizedBox.shrink()
                : TaxJourneyScene(
                    step: visual.step,
                    profile: visual.profile,
                    chapter: visual.meta.title,
                    helper: visual.meta.helper,
                    accent: visual.meta.color,
                    height: visualHeight,
                  ),
          ),
          SizedBox(height: visualHeight == 0 ? 8 : 18),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(bottom: bottomInset + 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: content,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (onNext != null)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: AppButtons.primaryGold,
                onPressed: canProceed ? onNext : null,
                child: Text(nextLabel),
              ),
            ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _ResponsiveAmount extends StatelessWidget {
  final String value;

  const _ResponsiveAmount(this.value);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          maxLines: 1,
          style: PaycheckType.displaySmall(color: PaycheckColors.gold),
        ),
      ),
    );
  }
}

class _PayslipSourceNote extends StatelessWidget {
  const _PayslipSourceNote({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PaycheckColors.success.withValues(alpha: 0.08),
        borderRadius: AppRadius.card,
        border: Border.all(color: PaycheckColors.success.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_outlined,
            color: PaycheckColors.success,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PaycheckType.bodyMedium()),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: PaycheckType.micro(color: PaycheckColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Q01: Annual CTC ──────────────────────────────────────────────────────────
class _Q01CTC extends ConsumerStatefulWidget {
  final UserProfile profile;
  final PayslipTaxPrefill? payslipPrefill;
  final VoidCallback onNext;
  const _Q01CTC({
    required this.profile,
    required this.payslipPrefill,
    required this.onNext,
  });

  @override
  ConsumerState<_Q01CTC> createState() => _Q01CTCState();
}

class _Q01CTCState extends ConsumerState<_Q01CTC> {
  late double _value; // in Lakhs (1.0 – 60.0)
  late TextEditingController _textCtrl;
  @override
  void initState() {
    super.initState();
    _value = (widget.profile.annualCTC / 100000).clamp(1.0, 60.0);
    // Text field stores LAKHS so user types "15" for ₹15L — no premature clamping
    _textCtrl = TextEditingController(text: _value.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _Q01CTC oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.annualCTC != widget.profile.annualCTC &&
        widget.payslipPrefill?.annualGrossSalary != null) {
      _value = (widget.profile.annualCTC / 100000).clamp(1.0, 60.0);
      _textCtrl.text = _value.toStringAsFixed(1);
    }
  }

  /// Called on every keystroke. Accepts lakhs (e.g. user types "15" = ₹15L).
  void _onTextChanged(String raw) {
    // Strip trailing decimal point so "2." parses as 2.0 instead of null.
    final stripped = raw.trim().replaceAll(RegExp(r'\.$'), '');
    final val = double.tryParse(stripped);

    // Always call setState so the display text re-renders from the text field.
    setState(() {
      if (val != null && val > 0) {
        _value = val.clamp(1.0, 60.0); // slider position only (display)
      }
      // If input is empty / mid-typing, _value holds the last valid slider
      // position — slider stays put, display shows raw typed value.
    });

    // Persist the TRUE typed amount — the slider range does not cap real income.
    if (val != null && val > 0) {
      ref.read(userProfileProvider.notifier).updateField(
            (p) => p.copyWith(annualCTC: (val * 100000).round()),
          );
    }
  }

  /// Called on blur/submit.
  void _onTextSubmitted(String raw) {
    final parsed = double.tryParse(raw.trim());
    final val = (parsed != null && parsed > 0) ? parsed : _value;
    setState(() => _value = val.clamp(1.0, 60.0));
    _textCtrl.text = val.toStringAsFixed(1);
    ref
        .read(userProfileProvider.notifier)
        .updateField((p) => p.copyWith(annualCTC: (val * 100000).round()));
  }

  void _onSliderChanged(double v) {
    setState(() {
      _value = v;
    });
    // Update text field to show lakhs — won't trigger onChanged
    _textCtrl.text = v.toStringAsFixed(1);
    ref
        .read(userProfileProvider.notifier)
        .updateField((p) => p.copyWith(annualCTC: (v * 100000).round()));
  }

  @override
  Widget build(BuildContext context) {
    // Display mirrors the raw text field — strip trailing dot so "2." shows as 2.0.
    final rawParsed = double.tryParse(
      _textCtrl.text.trim().replaceAll(RegExp(r'\.$'), ''),
    );
    final displayLakhs =
        (rawParsed != null && rawParsed > 0) ? rawParsed : _value;
    final displayText = '₹ ${displayLakhs.toStringAsFixed(1)} Lakhs / year';
    return _QLayout(
      question: 'What is your annual CTC?',
      microCopy: 'Your gross salary package (CTC). Approximate is fine.',
      onNext: widget.onNext,
      content: Column(
        children: [
          if (widget.payslipPrefill?.annualGrossSalary != null) ...[
            _PayslipSourceNote(
              title: 'Annual salary prefilled',
              detail:
                  'Based on ${widget.payslipPrefill!.payPeriod}. This is monthly gross x 12, so adjust it if your CTC includes bonuses or employer benefits.',
            ),
            const SizedBox(height: 18),
          ],
          // Live display — updates on every setState
          Center(
            child: Column(
              children: [
                _ResponsiveAmount(displayText),
                const SizedBox(height: 6),
                Text(
                  'Gross Annual Salary (CTC)',
                  style: PaycheckType.caption(color: PaycheckColors.textSecondary),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Text input — value in Lakhs, suffix "L"
          TextField(
            controller: _textCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: PaycheckType.body(),
            decoration: InputDecoration(
              labelText: 'Enter in Lakhs',
              labelStyle: PaycheckType.caption(color: PaycheckColors.textSecondary),
              suffixText: 'L',
              suffixStyle: PaycheckType.body(color: PaycheckColors.gold),
              hintText: '15.0',
              hintStyle: PaycheckType.body(color: PaycheckColors.textMuted),
              helperText: 'Type 15 for ₹15 Lakhs  (min ₹1L)',
              helperStyle: PaycheckType.micro(color: PaycheckColors.textMuted),
              filled: true,
              fillColor: PaycheckColors.bgCard,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: PaycheckColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: PaycheckColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: PaycheckColors.gold, width: 1.5),
              ),
            ),
            onChanged: _onTextChanged,
            onSubmitted: _onTextSubmitted,
            onEditingComplete: () {
              _onTextSubmitted(_textCtrl.text);
              FocusScope.of(context).unfocus();
            },
          ),

          const SizedBox(height: 16),

          // Slider — synced with _value
          Slider(
            value: _value,
            min: 1,
            max: 60,
            divisions: 118, // 0.5L steps from 1L to 60L
            label: '₹${_value.toStringAsFixed(1)}L',
            onChanged: _onSliderChanged,
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('₹1L', style: PaycheckType.micro()),
              Text('₹60L', style: PaycheckType.micro()),
            ],
          ),

          const SizedBox(height: 24),
          _SlabIndicator(ctcLakhs: _value),
        ],
      ),
    );
  }
}

class _SlabIndicator extends StatelessWidget {
  final double ctcLakhs;
  const _SlabIndicator({required this.ctcLakhs});

  @override
  Widget build(BuildContext context) {
    String bracket;
    Color color;
    if (ctcLakhs <= 7.5) {
      bracket = 'New regime: likely zero tax (rebate applies)';
      color = PaycheckColors.success;
    } else if (ctcLakhs <= 12) {
      bracket = 'New regime: 87A rebate may apply. Compare both regimes.';
      color = PaycheckColors.teal;
    } else if (ctcLakhs <= 15) {
      bracket = 'Close call — old vs new regime depends on deductions';
      color = PaycheckColors.amber;
    } else {
      bracket = 'Old regime likely better if you have deductions';
      color = PaycheckColors.gold;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppRadius.card,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(bracket, style: PaycheckType.micro(color: color)),
          ),
        ],
      ),
    );
  }
}

// ─── Q02: Employment Type ─────────────────────────────────────────────────────
class _Q02Employment extends ConsumerWidget {
  final UserProfile profile;
  final PayslipTaxPrefill? payslipPrefill;
  final VoidCallback onNext;
  const _Q02Employment({
    required this.profile,
    required this.payslipPrefill,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _QLayout(
      question: 'Are you salaried or self-employed?',
      onNext: onNext,
      content: Column(
        children: [
          if (payslipPrefill?.employerName != null) ...[
            _PayslipSourceNote(
              title: 'Employer found in your payslip',
              detail: payslipPrefill!.employerName!,
            ),
            const SizedBox(height: 14),
          ],
          SelectChip(
            label: 'Salaried Employee',
            icon: Icons.work_outline_rounded,
            selected: profile.employmentType == EmploymentType.salaried,
            fullWidth: true,
            onTap: () {
              ref.read(userProfileProvider.notifier).updateField(
                    (p) => p.copyWith(employmentType: EmploymentType.salaried),
                  );
            },
          ),
          if (profile.employmentType == EmploymentType.salaried) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const Key('select_employer'),
              style: AppButtons.outlineGold,
              onPressed: () async {
                final employer = await showEmployerPicker(
                  context,
                  currentValue: profile.employerName,
                );
                if (employer == null) return;
                ref.read(userProfileProvider.notifier).updateField(
                      (p) => p.copyWith(employerName: employer),
                    );
              },
              icon: const Icon(Icons.business_outlined),
              label: Text(
                profile.employerName.isEmpty
                    ? 'Add your employer'
                    : profile.employerName,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SelectChip(
            label: 'Self-Employed / Freelancer',
            icon: Icons.receipt_long_outlined,
            selected: profile.employmentType == EmploymentType.selfEmployed,
            fullWidth: true,
            onTap: () {
              ref.read(userProfileProvider.notifier).updateField(
                    (p) =>
                        p.copyWith(employmentType: EmploymentType.selfEmployed),
                  );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Q03: City ───────────────────────────────────────────────────────────────
// ─── Regime preference (gates the deduction questions) ──────────────────────
class _QRegime extends ConsumerWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _QRegime({required this.profile, required this.onNext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rs = ref.watch(activeTaxRuleSetProvider).asData?.value;
    final rebateLimit = rs?.newRegime.rebate87ALimit ?? 1200000;
    final sd = profile.employmentType == EmploymentType.salaried
        ? (rs?.newRegime.standardDeduction ?? 75000)
        : 0;
    final nilCap = rebateLimit + sd;
    final autoLikelyNew = profile.annualCTC <= nilCap;

    void set(RegimePreference pref) {
      ref
          .read(userProfileProvider.notifier)
          .updateField((p) => p.copyWith(regimePreference: pref));
    }

    Widget option(RegimePreference pref, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SelectChip(
            label: label,
            selected: profile.regimePreference == pref,
            fullWidth: true,
            onTap: () => set(pref),
          ),
        );

    return _QLayout(
      question: 'How should we pick your tax regime?',
      microCopy: 'The new regime is the default. We only ask about deductions '
          'if the old regime could actually save you more.',
      onNext: onNext,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            option(RegimePreference.auto, 'Recommend for me (compare both)'),
            option(RegimePreference.newRegime,
                'New regime — simplest, fewer questions'),
            option(RegimePreference.oldRegime,
                'Old regime — I have deductions to claim'),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PaycheckColors.gold.withValues(alpha: 0.07),
                borderRadius: AppRadius.card,
              ),
              child: Text(
                autoLikelyNew
                    ? 'At your income, the new regime likely makes tax ₹0 — we can '
                        'skip the deduction questions entirely.'
                    : 'At your income the old regime can still win with strong '
                        'deductions, so we will ask a few targeted questions.',
                style: PaycheckType.micro(color: PaycheckColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Q03City extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _Q03City({required this.profile, required this.onNext});

  @override
  ConsumerState<_Q03City> createState() => _Q03CityState();
}

class _Q03CityState extends ConsumerState<_Q03City> {
  final _search = TextEditingController();
  String _query = '';

  // Fallback only — the authoritative metro list comes from the active year's
  // rule set (FY2026-27 expanded it from 4 to 8 cities). Used if the rule set
  // has not finished loading.
  static const _fallbackMetros = [
    'Delhi',
    'Mumbai',
    'Chennai',
    'Kolkata',
    'Bengaluru',
    'Hyderabad',
    'Pune',
    'Ahmedabad',
  ];
  static const _cities = [
    'Delhi',
    'Mumbai',
    'Chennai',
    'Kolkata',
    'Bengaluru',
    'Hyderabad',
    'Pune',
    'Ahmedabad',
    'Jaipur',
    'Lucknow',
    'Durgapur',
    'Indore',
    'Bhopal',
    'Chandigarh',
    'Kochi',
    'Surat',
    'Nagpur',
    'Coimbatore',
    'Visakhapatnam',
    'Vadodara',
    'Patna',
    'Bhubaneswar',
    'Gurugram',
    'Noida',
    'Ranchi',
    'Guwahati',
    'Dehradun',
    'Mysuru',
  ];

  List<String> get _filtered => _cities
      .where((c) => c.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    final ruleSet = ref.watch(activeTaxRuleSetProvider).asData?.value;
    bool isMetroOf(String city) =>
        ruleSet?.isHraMetro(city) ?? _fallbackMetros.contains(city);
    return _QLayout(
      question: 'Which city do you live in?',
      microCopy: 'Metro cities get higher HRA benefit.',
      onNext: widget.profile.city.trim().isNotEmpty ? widget.onNext : null,
      content: Column(
        children: [
          TextField(
            controller: _search,
            style: PaycheckType.body(),
            decoration: InputDecoration(
              hintText: 'Search city...',
              hintStyle: PaycheckType.body(color: PaycheckColors.textSecondary),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: PaycheckColors.textSecondary,
                size: 20,
              ),
              filled: true,
              fillColor: PaycheckColors.bgCard,
              border: const OutlineInputBorder(
                borderRadius: AppRadius.card,
                borderSide: BorderSide(color: PaycheckColors.border),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: AppRadius.card,
                borderSide: BorderSide(color: PaycheckColors.border),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: AppRadius.card,
                borderSide: BorderSide(color: PaycheckColors.gold, width: 1.5),
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          ListView.builder(
            itemCount: _filtered.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (_, i) {
              final city = _filtered[i];
              final isMetro = isMetroOf(city);
              final selected = widget.profile.city == city;
              return GestureDetector(
                onTap: () {
                  ref.read(userProfileProvider.notifier).updateField(
                        (p) => p.copyWith(city: city, isMetroCity: isMetro),
                      );
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? PaycheckColors.gold.withValues(alpha: 0.1)
                        : PaycheckColors.bgCard,
                    borderRadius: AppRadius.card,
                    border: Border.all(
                      color: selected ? PaycheckColors.gold : PaycheckColors.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          city,
                          style: PaycheckType.body(
                            color: selected
                                ? PaycheckColors.gold
                                : PaycheckColors.textPrimary,
                          ),
                        ),
                      ),
                      if (isMetro)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: PaycheckColors.teal.withValues(alpha: 0.15),
                            borderRadius: AppRadius.pill,
                          ),
                          child: Text(
                            'Metro',
                            style: PaycheckType.micro(color: PaycheckColors.teal),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_query.trim().length >= 2 &&
              !_cities.any(
                (city) => city.toLowerCase() == _query.trim().toLowerCase(),
              ))
            ListTile(
              key: const Key('use_custom_city'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.add_location_alt_outlined),
              title: Text('Use “${_query.trim()}”'),
              subtitle: const Text('Save a city not listed above'),
              onTap: () {
                final city = _query.trim();
                ref.read(userProfileProvider.notifier).updateField(
                      (profile) => profile.copyWith(
                        city: city,
                        isMetroCity: isMetroOf(city),
                      ),
                    );
              },
            ),
        ],
      ),
    );
  }
}

// ─── Q04: Rent ───────────────────────────────────────────────────────────────
class _Q04Rent extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _Q04Rent({required this.profile, required this.onNext});

  @override
  ConsumerState<_Q04Rent> createState() => _Q04RentState();
}

class _Q04RentState extends ConsumerState<_Q04Rent> {
  bool? _paysRent;
  double _rentK = 15; // in thousands (5.0 – 200.0)
  late TextEditingController _rentTextCtrl;

  @override
  void initState() {
    super.initState();
    _paysRent = widget.profile.paysRent ? true : null;
    _rentK = (widget.profile.monthlyRent / 1000).clamp(1.0, 200.0);
    // Text field shows value in thousands so user types "15" for ₹15K/month
    _rentTextCtrl = TextEditingController(text: _rentK.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _rentTextCtrl.dispose();
    super.dispose();
  }

  /// Text field accepts thousands. "15" = ₹15,000/month.
  void _onRentTextChanged(String raw) {
    final stripped = raw.trim().replaceAll(RegExp(r'\.$'), '');
    final val = double.tryParse(stripped);

    // Always rebuild so display mirrors the text field instantly.
    setState(() {
      if (val != null && val > 0) {
        _rentK = val.clamp(1.0, 200.0); // slider position only
      }
    });

    // Persist the true rent — the slider range does not cap it.
    if (val != null && val > 0) {
      ref.read(userProfileProvider.notifier).updateField(
            (p) => p.copyWith(monthlyRent: (val * 1000).round()),
          );
    }
  }

  void _onRentTextSubmitted(String raw) {
    final parsed = double.tryParse(raw.trim());
    final val = (parsed != null && parsed > 0) ? parsed : _rentK;
    setState(() => _rentK = val.clamp(1.0, 200.0));
    _rentTextCtrl.text = val.toStringAsFixed(0);
    ref
        .read(userProfileProvider.notifier)
        .updateField((p) => p.copyWith(monthlyRent: (val * 1000).round()));
  }

  void _onRentSliderChanged(double v) {
    setState(() => _rentK = v);
    // Update text to show thousands — won't trigger onChanged
    _rentTextCtrl.text = v.toStringAsFixed(0);
    ref
        .read(userProfileProvider.notifier)
        .updateField((p) => p.copyWith(monthlyRent: (v * 1000).round()));
  }

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: 'Do you pay rent?',
      onNext: _paysRent != null ? widget.onNext : null,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectChip(
            label: 'Yes, I pay rent',
            selected: _paysRent == true,
            fullWidth: true,
            onTap: () {
              setState(() => _paysRent = true);
              ref
                  .read(userProfileProvider.notifier)
                  .updateField((p) => p.copyWith(paysRent: true));
            },
          ),
          const SizedBox(height: 12),
          SelectChip(
            label: 'No, own / stay with family',
            selected: _paysRent == false,
            fullWidth: true,
            onTap: () {
              setState(() => _paysRent = false);
              ref.read(userProfileProvider.notifier).updateField(
                    (p) => p.copyWith(paysRent: false, monthlyRent: 0),
                  );
            },
          ),
          if (_paysRent == true) ...[
            const SizedBox(height: 28),
            Text('How much rent per month?', style: PaycheckType.h3()),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final rawR = double.tryParse(
                  _rentTextCtrl.text.trim().replaceAll(RegExp(r'\.$'), ''),
                );
                final displayK = (rawR != null && rawR > 0) ? rawR : _rentK;
                return _ResponsiveAmount(
                  '₹ ${NumberFormat('#,##,##0', 'en_IN').format((displayK * 1000).round())} / month',
                );
              },
            ),
            const SizedBox(height: 12),
            // Text input — value in thousands so "15" = ₹15,000/month
            TextField(
              controller: _rentTextCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: PaycheckType.body(),
              decoration: InputDecoration(
                labelText: 'Enter in Thousands',
                labelStyle: PaycheckType.caption(
                  color: PaycheckColors.textSecondary,
                ),
                suffixText: 'K / mo',
                suffixStyle: PaycheckType.body(color: PaycheckColors.gold),
                hintText: '15',
                hintStyle: PaycheckType.body(color: PaycheckColors.textMuted),
                helperText: 'Type 15 for ₹15,000/month',
                helperStyle: PaycheckType.micro(color: PaycheckColors.textMuted),
                filled: true,
                fillColor: PaycheckColors.bgCard,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: PaycheckColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: PaycheckColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: PaycheckColors.gold,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: _onRentTextChanged,
              onSubmitted: _onRentTextSubmitted,
              onEditingComplete: () {
                _onRentTextSubmitted(_rentTextCtrl.text);
                FocusScope.of(context).unfocus();
              },
            ),
            const SizedBox(height: 8),
            Slider(
              value: _rentK.clamp(1.0, 200.0),
              min: 1,
              max: 200,
              divisions: 199,
              label: '₹${_rentK.toStringAsFixed(0)}K',
              onChanged: _onRentSliderChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₹1K', style: PaycheckType.micro()),
                Text('₹2,00,000', style: PaycheckType.micro()),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Q05: HRA ────────────────────────────────────────────────────────────────
class _Q05HRA extends ConsumerWidget {
  final UserProfile profile;
  final PayslipTaxPrefill? payslipPrefill;
  final VoidCallback onNext;
  const _Q05HRA({
    required this.profile,
    required this.payslipPrefill,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _QLayout(
      question: 'Does your employer give you HRA?',
      microCopy: 'Check your payslip. It\'s listed separately.',
      onNext: onNext,
      content: Column(
        children: [
          if (payslipPrefill?.annualHraReceived != null) ...[
            _PayslipSourceNote(
              title: 'HRA already confirmed',
              detail:
                  '${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(payslipPrefill!.annualHraReceived)} per year from ${payslipPrefill!.payPeriod}.',
            ),
            const SizedBox(height: 14),
          ],
          SelectChip(
            label: 'Yes, HRA is in my salary',
            selected: profile.hasHRA,
            fullWidth: true,
            onTap: () {
              ref
                  .read(userProfileProvider.notifier)
                  .updateField((p) => p.copyWith(hasHRA: true));
            },
          ),
          const SizedBox(height: 12),
          SelectChip(
            label: 'No HRA / Not sure',
            selected: !profile.hasHRA,
            fullWidth: true,
            onTap: () {
              ref
                  .read(userProfileProvider.notifier)
                  .updateField((p) => p.copyWith(hasHRA: false));
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PaycheckColors.bgCard,
              borderRadius: AppRadius.card,
              border: Border.all(color: PaycheckColors.border),
            ),
            child: Text(
              'If you don\'t receive HRA but pay rent, you may still be able to claim deduction under Section 80GG.',
              style: PaycheckType.micro(color: PaycheckColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Q06: 80C ────────────────────────────────────────────────────────────────
class _Q06EightyC extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _Q06EightyC({required this.profile, required this.onNext});

  @override
  ConsumerState<_Q06EightyC> createState() => _Q06EightyCState();
}

class _Q06EightyCState extends ConsumerState<_Q06EightyC> {
  late double
      _value; // slider 0.0–15.0 (represents 0–₹1,50,000 in steps of ₹10K)
  late TextEditingController _textCtrl;
  final _fmt = NumberFormat('#,##,##0', 'en_IN');

  @override
  void initState() {
    super.initState();
    _value = (widget.profile.invested80C / 10000).clamp(0.0, 15.0);
    // Text field shows raw rupees; user types "100000" for ₹1L
    _textCtrl = TextEditingController(text: _invested.toString());
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  int get _invested => (_value * 10000).round();
  int get _remaining => (150000 - _invested).clamp(0, 150000);

  /// Don't clamp during typing. Only update slider once value ≥ ₹10,000.
  void _onTextChanged(String raw) {
    final stripped = raw.replaceAll(',', '').replaceAll(' ', '');
    final val = int.tryParse(stripped);
    if (val == null || val < 0) return;
    // Update slider/display only when ≥ ₹10K so partial typing doesn't snap to 0
    final v = (val / 10000.0).clamp(0.0, 15.0);
    setState(() => _value = v);
    ref
        .read(userProfileProvider.notifier)
        .updateField((p) => p.copyWith(invested80C: val.clamp(0, 150000)));
  }

  void _onTextSubmitted(String raw) {
    final val = int.tryParse(raw.replaceAll(',', '').trim()) ?? _invested;
    final clamped = val.clamp(0, 150000);
    final v = clamped / 10000.0;
    setState(() => _value = v);
    _textCtrl.text = clamped.toString();
    ref
        .read(userProfileProvider.notifier)
        .updateField((p) => p.copyWith(invested80C: clamped));
  }

  void _onSliderChanged(double v) {
    setState(() => _value = v);
    // Update text with full rupee amount — won't trigger onChanged
    _textCtrl.text = _invested.toString();
    ref
        .read(userProfileProvider.notifier)
        .updateField((p) => p.copyWith(invested80C: _invested));
  }

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: 'How much have you invested in 80C?',
      microCopy:
          'Includes: ELSS, PPF, EPF (yours + employer), LIC, NSC, tax-saving FD.',
      onNext: widget.onNext,
      content: Column(
        children: [
          if (ref.watch(payslipTaxPrefillProvider)?.annualEligible80C !=
              null) ...[
            _PayslipSourceNote(
              title: 'Prefilled from your payslip',
              detail:
                  '₹${_fmt.format(ref.watch(payslipTaxPrefillProvider)!.annualEligible80C)} of PF / insurance detected. Add any extra 80C like ELSS, PPF or tuition fees.',
            ),
            const SizedBox(height: 16),
          ],
          Center(
            child: Column(
              children: [
                Text(
                  '₹ ${_fmt.format(_invested)} invested',
                  style: PaycheckType.h2(color: PaycheckColors.gold),
                ),
                const SizedBox(height: 4),
                if (_remaining > 0)
                  Text(
                    '₹ ${_fmt.format(_remaining)} remaining in 80C limit',
                    style: PaycheckType.caption(color: PaycheckColors.amber),
                  )
                else
                  Text(
                    '80C fully utilised',
                    style: PaycheckType.caption(color: PaycheckColors.success),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Text input — accepts raw rupees (0 – 1,50,000)
          TextField(
            controller: _textCtrl,
            keyboardType: TextInputType.number,
            style: PaycheckType.body(),
            decoration: InputDecoration(
              labelText: 'Enter amount in ₹',
              labelStyle: PaycheckType.caption(color: PaycheckColors.textSecondary),
              prefixText: '₹ ',
              prefixStyle: PaycheckType.body(color: PaycheckColors.gold),
              hintText: '1,50,000',
              hintStyle: PaycheckType.body(color: PaycheckColors.textMuted),
              helperText: 'Max ₹1,50,000 under 80C',
              helperStyle: PaycheckType.micro(color: PaycheckColors.textMuted),
              filled: true,
              fillColor: PaycheckColors.bgCard,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: PaycheckColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: PaycheckColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: PaycheckColors.gold, width: 1.5),
              ),
            ),
            onChanged: _onTextChanged,
            onSubmitted: _onTextSubmitted,
            onEditingComplete: () {
              _onTextSubmitted(_textCtrl.text);
              FocusScope.of(context).unfocus();
            },
          ),
          const SizedBox(height: 12),

          Slider(
            value: _value,
            min: 0,
            max: 15,
            divisions: 30,
            label: '₹${_invested ~/ 1000}K',
            onChanged: _onSliderChanged,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('₹0', style: PaycheckType.micro()),
              Text('₹1,50,000', style: PaycheckType.micro()),
            ],
          ),
          const SizedBox(height: 16),

          // 80C utilisation bar
          _EightyCBar(invested: _invested),
        ],
      ),
    );
  }
}

class _EightyCBar extends StatelessWidget {
  final int invested;
  const _EightyCBar({required this.invested});

  @override
  Widget build(BuildContext context) {
    final pct = (invested / 150000).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('80C utilisation', style: PaycheckType.micro()),
            const Spacer(),
            Text('₹1,50,000 limit', style: PaycheckType.micro()),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: AppRadius.pill,
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: PaycheckColors.bgSurface,
            valueColor: AlwaysStoppedAnimation<Color>(
              pct >= 1.0 ? PaycheckColors.success : PaycheckColors.gold,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Q07: Home Loan ───────────────────────────────────────────────────────────
class _Q07HomeLoan extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _Q07HomeLoan({required this.profile, required this.onNext});

  @override
  ConsumerState<_Q07HomeLoan> createState() => _Q07HomeLoanState();
}

class _Q07HomeLoanState extends ConsumerState<_Q07HomeLoan> {
  bool? _hasLoan;
  PropertyType? _type;
  double _interestL = 1.0; // in lakhs
  late TextEditingController _interestTextCtrl;

  @override
  void initState() {
    super.initState();
    _hasLoan = widget.profile.hasHomeLoan ? true : null;
    _type = widget.profile.propertyType;
    _interestL = (widget.profile.homeLoanInterest / 100000).clamp(0.25, 5.0);
    _interestTextCtrl = TextEditingController(
      text: (_interestL * 100000).round().toString(),
    );
  }

  @override
  void dispose() {
    _interestTextCtrl.dispose();
    super.dispose();
  }

  void _onInterestTextChanged(String raw) {
    final stripped = raw.replaceAll(',', '').replaceAll(' ', '');
    final val = int.tryParse(stripped);
    if (val != null && val >= 0) {
      // Slider position is clamped for display; the persisted value is the
      // true amount (the engine applies the ₹2L / let-out statutory caps).
      setState(() => _interestL = (val / 100000).clamp(0.25, 5.0));
      ref.read(userProfileProvider.notifier).updateField(
            (p) => p.copyWith(homeLoanInterest: val),
          );
    }
  }

  void _onInterestSliderChanged(double v) {
    setState(() => _interestL = v);
    _interestTextCtrl.text = (v * 100000).round().toString();
    ref.read(userProfileProvider.notifier).updateField(
          (p) => p.copyWith(homeLoanInterest: (_interestL * 100000).round()),
        );
  }

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: 'Do you have a home loan?',
      onNext: _hasLoan != null ? widget.onNext : null,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectChip(
              label: 'Yes, I have a home loan',
              selected: _hasLoan == true,
              fullWidth: true,
              onTap: () {
                setState(() => _hasLoan = true);
                ref
                    .read(userProfileProvider.notifier)
                    .updateField((p) => p.copyWith(hasHomeLoan: true));
              },
            ),
            const SizedBox(height: 12),
            SelectChip(
              label: 'No home loan',
              selected: _hasLoan == false,
              fullWidth: true,
              onTap: () {
                setState(() {
                  _hasLoan = false;
                  _type = null;
                });
                ref.read(userProfileProvider.notifier).updateField(
                      (p) => p.copyWith(
                        hasHomeLoan: false,
                        homeLoanInterest: 0,
                        propertyType: null,
                      ),
                    );
              },
            ),
            if (_hasLoan == true) ...[
              const SizedBox(height: 24),
              Text(
                'Is the property self-occupied or let out?',
                style: PaycheckType.h3(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SelectChip(
                      label: 'Self-occupied',
                      selected: _type == PropertyType.selfOccupied,
                      fullWidth: true,
                      onTap: () {
                        setState(() => _type = PropertyType.selfOccupied);
                        ref.read(userProfileProvider.notifier).updateField(
                              (p) => p.copyWith(
                                propertyType: PropertyType.selfOccupied,
                              ),
                            );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectChip(
                      label: 'Let out / Rented',
                      selected: _type == PropertyType.letOut,
                      fullWidth: true,
                      onTap: () {
                        setState(() => _type = PropertyType.letOut);
                        ref.read(userProfileProvider.notifier).updateField(
                              (p) =>
                                  p.copyWith(propertyType: PropertyType.letOut),
                            );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Annual home loan interest paid?',
                style: PaycheckType.h3(),
              ),
              const SizedBox(height: 8),
              _ResponsiveAmount(
                '₹ ${(_interestL * 100000).round().toString().replaceAllMapped(RegExp(r'(\d{1,2})(?=(\d{2})+(?!\d))'), (m) => '${m[1]},')}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _interestTextCtrl,
                keyboardType: TextInputType.number,
                style: PaycheckType.body(),
                decoration: InputDecoration(
                  hintText: 'Enter amount (₹)',
                  hintStyle: PaycheckType.body(color: PaycheckColors.textSecondary),
                  prefixText: '₹ ',
                  prefixStyle: PaycheckType.body(color: PaycheckColors.gold),
                  filled: true,
                  fillColor: PaycheckColors.bgCard,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: PaycheckColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: PaycheckColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: PaycheckColors.gold,
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: _onInterestTextChanged,
              ),
              Slider(
                value: _interestL,
                min: 0.25,
                max: 5.0,
                divisions: 19,
                label: '₹${_interestL.toStringAsFixed(1)}L',
                onChanged: _onInterestSliderChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Q08: NPS ─────────────────────────────────────────────────────────────────
class _Q08NPS extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _Q08NPS({required this.profile, required this.onNext});

  @override
  ConsumerState<_Q08NPS> createState() => _Q08NPSState();
}

class _Q08NPSState extends ConsumerState<_Q08NPS> {
  int? _choice; // 0=yes, 1=no, 2=not sure
  double _extraK = 0;
  final TextEditingController _npsTextCtrl = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    if (widget.profile.hasNPS || widget.profile.npsExtraContribution > 0) {
      _choice = 0;
    }
    _extraK = (widget.profile.npsExtraContribution / 1000).clamp(0.0, 50.0);
    _npsTextCtrl.text = (_extraK * 1000).round().toString();
  }

  @override
  void dispose() {
    _npsTextCtrl.dispose();
    super.dispose();
  }

  void _onNpsTextChanged(String raw) {
    final stripped = raw.replaceAll(',', '').replaceAll(' ', '');
    final val = int.tryParse(stripped);
    if (val != null) {
      final k = (val / 1000).clamp(0.0, 50.0);
      setState(() => _extraK = k);
      ref.read(userProfileProvider.notifier).updateField(
            (p) => p.copyWith(npsExtraContribution: (k * 1000).round()),
          );
    }
  }

  void _onNpsSliderChanged(double v) {
    setState(() => _extraK = v);
    _npsTextCtrl.text = (v * 1000).round().toString();
    ref.read(userProfileProvider.notifier).updateField(
          (p) => p.copyWith(npsExtraContribution: (_extraK * 1000).round()),
        );
  }

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: 'Do you have NPS (National Pension System)?',
      onNext: _choice != null ? widget.onNext : null,
      content: SingleChildScrollView(
        child: Column(
          children: [
            if (ref.watch(payslipTaxPrefillProvider)?.annualEmployeeNps !=
                null) ...[
              const _PayslipSourceNote(
                title: 'Prefilled from your payslip',
                detail:
                    'NPS contribution detected on your payslip. Confirm or adjust the amount below.',
              ),
              const SizedBox(height: 16),
            ],
            SelectChip(
              label: 'Yes — I have NPS Tier-1',
              selected: _choice == 0,
              fullWidth: true,
              onTap: () {
                setState(() => _choice = 0);
                ref
                    .read(userProfileProvider.notifier)
                    .updateField((p) => p.copyWith(hasNPS: true));
              },
            ),
            const SizedBox(height: 10),
            SelectChip(
              label: 'No NPS',
              selected: _choice == 1,
              fullWidth: true,
              onTap: () {
                setState(() {
                  _choice = 1;
                  _extraK = 0;
                });
                ref.read(userProfileProvider.notifier).updateField(
                      (p) => p.copyWith(hasNPS: false, npsExtraContribution: 0),
                    );
              },
            ),
            const SizedBox(height: 10),
            SelectChip(
              label: 'Not sure what NPS is',
              selected: _choice == 2,
              fullWidth: true,
              onTap: () {
                setState(() {
                  _choice = 2;
                  _extraK = 0;
                });
                ref.read(userProfileProvider.notifier).updateField(
                      (p) => p.copyWith(hasNPS: false, npsExtraContribution: 0),
                    );
              },
            ),
            if (_choice == 2) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: PaycheckColors.gold.withValues(alpha: 0.07),
                  borderRadius: AppRadius.card,
                  border: Border.all(
                    color: PaycheckColors.gold.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What is NPS?',
                      style: PaycheckType.bodyMedium(color: PaycheckColors.gold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'National Pension System (NPS) is a government-backed retirement savings scheme. Opening an NPS Tier-1 account and contributing ₹50,000/year gives you an EXTRA ₹50,000 deduction under Section 80CCD(1B) — over and above your 80C limit.',
                      style: PaycheckType.micro(
                        color: PaycheckColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_choice == 0) ...[
              const SizedBox(height: 20),
              Text(
                'How much extra did you contribute beyond 80C?',
                style: PaycheckType.h3(),
              ),
              const SizedBox(height: 4),
              Text(
                '(Voluntary contribution over and above 80CCE limit)',
                style: PaycheckType.micro(),
              ),
              const SizedBox(height: 12),
              _ResponsiveAmount('₹ ${(_extraK * 1000).round()} extra'),
              const SizedBox(height: 12),
              TextField(
                controller: _npsTextCtrl,
                keyboardType: TextInputType.number,
                style: PaycheckType.body(),
                decoration: InputDecoration(
                  hintText: 'Enter amount (₹)',
                  hintStyle: PaycheckType.body(color: PaycheckColors.textSecondary),
                  prefixText: '₹ ',
                  prefixStyle: PaycheckType.body(color: PaycheckColors.gold),
                  filled: true,
                  fillColor: PaycheckColors.bgCard,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: PaycheckColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: PaycheckColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: PaycheckColors.gold,
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: _onNpsTextChanged,
              ),
              Slider(
                value: _extraK,
                min: 0,
                max: 50,
                divisions: 50,
                label: '₹${_extraK.round()}K',
                onChanged: _onNpsSliderChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Q09: Health Insurance ────────────────────────────────────────────────────
class _Q09HealthInsurance extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _Q09HealthInsurance({required this.profile, required this.onNext});

  @override
  ConsumerState<_Q09HealthInsurance> createState() =>
      _Q09HealthInsuranceState();
}

class _Q09HealthInsuranceState extends ConsumerState<_Q09HealthInsurance> {
  late bool _self;
  late bool _parents;
  late bool _parentsAbove60;
  final _selfPremiumCtrl = TextEditingController();
  final _parentsPremiumCtrl = TextEditingController();
  final _preventiveCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _self = widget.profile.hasHealthInsuranceSelf;
    _parents = widget.profile.hasHealthInsuranceParents;
    _parentsAbove60 = widget.profile.parentsAbove60;
    if (widget.profile.healthInsuranceSelfPremium != null) {
      _selfPremiumCtrl.text =
          widget.profile.healthInsuranceSelfPremium.toString();
    }
    if (widget.profile.healthInsuranceParentsPremium != null) {
      _parentsPremiumCtrl.text =
          widget.profile.healthInsuranceParentsPremium.toString();
    }
    if (widget.profile.preventiveHealthCheckup != null) {
      _preventiveCtrl.text = widget.profile.preventiveHealthCheckup.toString();
    }
  }

  @override
  void dispose() {
    _selfPremiumCtrl.dispose();
    _parentsPremiumCtrl.dispose();
    _preventiveCtrl.dispose();
    super.dispose();
  }

  int? _amount(TextEditingController c) {
    final v = int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), ''));
    return (v == null || v <= 0) ? null : v;
  }

  void _update() {
    ref.read(userProfileProvider.notifier).updateField(
          (p) => p.copyWith(
            hasHealthInsuranceSelf: _self,
            hasHealthInsuranceParents: _parents,
            parentsAbove60: _parentsAbove60,
            // Premiums drive the actual 80D deduction; clear them when the
            // corresponding cover is deselected.
            healthInsuranceSelfPremium:
                _self ? _amount(_selfPremiumCtrl) : null,
            healthInsuranceParentsPremium:
                _parents ? _amount(_parentsPremiumCtrl) : null,
            preventiveHealthCheckup: _amount(_preventiveCtrl),
          ),
        );
  }

  Widget _premiumField({
    required TextEditingController controller,
    required String label,
    String? helper,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PaycheckType.h3()),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(helper,
              style: PaycheckType.micro(color: PaycheckColors.textSecondary)),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: PaycheckType.body(),
          decoration: InputDecoration(
            hintText: 'Annual premium (₹)',
            hintStyle: PaycheckType.body(color: PaycheckColors.textSecondary),
            prefixText: '₹ ',
            prefixStyle: PaycheckType.body(color: PaycheckColors.gold),
            filled: true,
            fillColor: PaycheckColors.bgCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: PaycheckColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: PaycheckColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: PaycheckColors.gold, width: 1.5),
            ),
          ),
          onChanged: (_) => _update(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: 'Health insurance — who is covered?',
      microCopy: 'Select all that apply, then add the premiums you pay.',
      onNext: widget.onNext,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tap to select:', style: PaycheckType.caption()),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                MultiSelectChip(
                  label: 'Self / family',
                  selected: _self,
                  onTap: () {
                    setState(() => _self = !_self);
                    _update();
                  },
                ),
                MultiSelectChip(
                  label: 'Parents',
                  selected: _parents,
                  onTap: () {
                    setState(() => _parents = !_parents);
                    _update();
                  },
                ),
                MultiSelectChip(
                  label: 'No insurance',
                  selected: !_self && !_parents,
                  onTap: () {
                    setState(() {
                      _self = false;
                      _parents = false;
                    });
                    _update();
                  },
                ),
              ],
            ),
            if (_self) ...[
              const SizedBox(height: 24),
              _premiumField(
                controller: _selfPremiumCtrl,
                label: 'Annual premium for you / family',
                helper: widget.profile.ageAbove60
                    ? 'Deductible up to ₹50,000 (senior).'
                    : 'Deductible up to ₹25,000 under 80D.',
              ),
              const SizedBox(height: 16),
              _premiumField(
                controller: _preventiveCtrl,
                label: 'Preventive health check-up (optional)',
                helper: 'Up to ₹5,000, counted within the limit above.',
              ),
            ],
            if (_parents) ...[
              const SizedBox(height: 24),
              Text('Are your parents above 60?', style: PaycheckType.h3()),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SelectChip(
                      label: 'Yes (60+)',
                      selected: _parentsAbove60,
                      fullWidth: true,
                      onTap: () {
                        setState(() => _parentsAbove60 = true);
                        _update();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectChip(
                      label: 'No',
                      selected: !_parentsAbove60,
                      fullWidth: true,
                      onTap: () {
                        setState(() => _parentsAbove60 = false);
                        _update();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _premiumField(
                controller: _parentsPremiumCtrl,
                label: 'Annual premium for parents',
                helper: _parentsAbove60
                    ? 'Deductible up to ₹50,000 (senior parents).'
                    : 'Deductible up to ₹25,000 under 80D.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Q10: Education Loan ──────────────────────────────────────────────────────
class _Q10EducationLoan extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _Q10EducationLoan({required this.profile, required this.onNext});

  @override
  ConsumerState<_Q10EducationLoan> createState() => _Q10EducationLoanState();
}

class _Q10EducationLoanState extends ConsumerState<_Q10EducationLoan> {
  bool? _hasLoan;
  double _year = 1;
  double _interestK = 20;
  final TextEditingController _edLoanTextCtrl = TextEditingController(
    text: '20000',
  );

  @override
  void initState() {
    super.initState();
    final interest = widget.profile.educationLoanInterest;
    _hasLoan = widget.profile.hasEducationLoan || interest > 0 ? true : null;
    _year = widget.profile.educationLoanRepaymentYear.clamp(1, 8).toDouble();
    _interestK = interest > 0 ? (interest / 1000).clamp(5.0, 200.0) : 20.0;
    _edLoanTextCtrl.text = (_interestK * 1000).round().toString();
  }

  @override
  void dispose() {
    _edLoanTextCtrl.dispose();
    super.dispose();
  }

  void _onEdLoanTextChanged(String raw) {
    final stripped = raw.replaceAll(',', '').replaceAll(' ', '');
    final val = int.tryParse(stripped);
    if (val != null && val >= 0) {
      // Slider position clamps for display only; 80E has no upper limit, so the
      // persisted interest is the true amount typed.
      setState(() => _interestK = (val / 1000).clamp(5.0, 200.0));
      ref.read(userProfileProvider.notifier).updateField(
            (p) => p.copyWith(educationLoanInterest: val),
          );
    }
  }

  void _onEdLoanSliderChanged(double v) {
    setState(() => _interestK = v);
    _edLoanTextCtrl.text = (v * 1000).round().toString();
    ref.read(userProfileProvider.notifier).updateField(
          (p) => p.copyWith(educationLoanInterest: (_interestK * 1000).round()),
        );
  }

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: 'Do you have an education loan?',
      onNext: _hasLoan != null ? widget.onNext : null,
      content: SingleChildScrollView(
        child: Column(
          children: [
            SelectChip(
              label: 'Yes, paying EMIs',
              selected: _hasLoan == true,
              fullWidth: true,
              onTap: () {
                setState(() => _hasLoan = true);
                ref
                    .read(userProfileProvider.notifier)
                    .updateField((p) => p.copyWith(hasEducationLoan: true));
              },
            ),
            const SizedBox(height: 12),
            SelectChip(
              label: 'No education loan',
              selected: _hasLoan == false,
              fullWidth: true,
              onTap: () {
                setState(() => _hasLoan = false);
                ref.read(userProfileProvider.notifier).updateField(
                      (p) => p.copyWith(
                        hasEducationLoan: false,
                        educationLoanRepaymentYear: 1,
                        educationLoanInterest: 0,
                      ),
                    );
              },
            ),
            if (_hasLoan == true) ...[
              const SizedBox(height: 24),
              Text(
                'Which year of repayment are you in?',
                style: PaycheckType.h3(),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Year ${_year.round()} of 8',
                  style: PaycheckType.h2(color: PaycheckColors.gold),
                ),
              ),
              Slider(
                value: _year,
                min: 1,
                max: 8,
                divisions: 7,
                label: 'Year ${_year.round()}',
                onChanged: (v) {
                  setState(() => _year = v);
                  ref.read(userProfileProvider.notifier).updateField(
                        (p) => p.copyWith(
                          educationLoanRepaymentYear: _year.round(),
                        ),
                      );
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Approximate annual interest paid?',
                style: PaycheckType.h3(),
              ),
              const SizedBox(height: 4),
              Text(
                '80E allows full interest deduction — no upper limit!',
                style: PaycheckType.micro(color: PaycheckColors.success),
              ),
              const SizedBox(height: 8),
              _ResponsiveAmount('₹ ${(_interestK * 1000).round()} / year'),
              const SizedBox(height: 12),
              TextField(
                controller: _edLoanTextCtrl,
                keyboardType: TextInputType.number,
                style: PaycheckType.body(),
                decoration: InputDecoration(
                  hintText: 'Enter amount (₹)',
                  hintStyle: PaycheckType.body(color: PaycheckColors.textSecondary),
                  prefixText: '₹ ',
                  prefixStyle: PaycheckType.body(color: PaycheckColors.gold),
                  filled: true,
                  fillColor: PaycheckColors.bgCard,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: PaycheckColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: PaycheckColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: PaycheckColors.gold,
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: _onEdLoanTextChanged,
              ),
              Slider(
                value: _interestK,
                min: 5,
                max: 200,
                divisions: 39,
                label: '₹${_interestK.round()}K',
                onChanged: _onEdLoanSliderChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Q11: Donations ───────────────────────────────────────────────────────────
class _Q11Donations extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _Q11Donations({required this.profile, required this.onNext});

  @override
  ConsumerState<_Q11Donations> createState() => _Q11DonationsState();
}

class _Q11DonationsState extends ConsumerState<_Q11Donations> {
  bool? _hasDonations;
  final TextEditingController _donationTextCtrl = TextEditingController();
  DonationCategory? _category;
  bool _inCash = false;

  static const _categoryOptions = <(DonationCategory, String, String)>[
    (
      DonationCategory.hundredNoLimit,
      'PM CARES / PMNRF / Defence Fund',
      '100% deductible, no income limit',
    ),
    (
      DonationCategory.hundredWithLimit,
      'Government / local authority fund',
      '100% deductible, capped at 10% of income',
    ),
    (
      DonationCategory.fiftyNoLimit,
      'Approved national fund',
      '50% deductible, no income limit',
    ),
    (
      DonationCategory.fiftyWithLimit,
      'NGO / charitable / temple trust (80G)',
      '50% deductible, capped at 10% of income',
    ),
  ];

  @override
  void initState() {
    super.initState();
    final amount = widget.profile.donationAmount;
    _hasDonations = widget.profile.hasDonations || amount > 0 ? true : null;
    _category = widget.profile.donationCategory;
    _inCash = widget.profile.donationInCash;
    if (amount > 0) _donationTextCtrl.text = amount.toString();
  }

  @override
  void dispose() {
    _donationTextCtrl.dispose();
    super.dispose();
  }

  int get _amount =>
      int.tryParse(_donationTextCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
      0;

  void _update() {
    ref.read(userProfileProvider.notifier).updateField(
          (p) => p.copyWith(
            hasDonations: _hasDonations == true,
            donationAmount: _amount,
            donationCategory: _category,
            donationInCash: _inCash,
          ),
        );
  }

  bool get _cashBlocked => _inCash && _amount > 2000;

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: 'Did you make any donations this year?',
      microCopy: 'PM Relief Fund, NGOs, temple trusts with 80G certificate.',
      onNext: _hasDonations != null ? widget.onNext : null,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectChip(
              label: 'Yes — PM Relief / NGO / temple',
              selected: _hasDonations == true,
              fullWidth: true,
              onTap: () {
                setState(() => _hasDonations = true);
                _update();
              },
            ),
            const SizedBox(height: 12),
            SelectChip(
              label: 'No / Not sure',
              selected: _hasDonations == false,
              fullWidth: true,
              onTap: () {
                setState(() => _hasDonations = false);
                ref.read(userProfileProvider.notifier).updateField(
                      (p) => p.copyWith(hasDonations: false, donationAmount: 0),
                    );
              },
            ),
            if (_hasDonations == true) ...[
              const SizedBox(height: 24),
              Text('Amount donated', style: PaycheckType.h3()),
              const SizedBox(height: 8),
              TextField(
                controller: _donationTextCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: PaycheckType.body(),
                decoration: InputDecoration(
                  hintText: 'Enter amount (₹)',
                  hintStyle: PaycheckType.body(color: PaycheckColors.textSecondary),
                  prefixText: '₹ ',
                  prefixStyle: PaycheckType.body(color: PaycheckColors.gold),
                  filled: true,
                  fillColor: PaycheckColors.bgCard,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: PaycheckColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: PaycheckColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: PaycheckColors.gold, width: 1.5),
                  ),
                ),
                onChanged: (_) => setState(_update),
              ),
              const SizedBox(height: 20),
              Text('What kind of donation?', style: PaycheckType.h3()),
              const SizedBox(height: 4),
              Text(
                'This decides how much is deductible under 80G.',
                style: PaycheckType.micro(color: PaycheckColors.textSecondary),
              ),
              const SizedBox(height: 12),
              ..._categoryOptions.map(
                (opt) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectChip(
                    label: '${opt.$2}  ·  ${opt.$3}',
                    selected: _category == opt.$1,
                    fullWidth: true,
                    onTap: () {
                      setState(() => _category = opt.$1);
                      _update();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('How did you pay?', style: PaycheckType.h3()),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SelectChip(
                      label: 'Digital / cheque',
                      selected: !_inCash,
                      fullWidth: true,
                      onTap: () {
                        setState(() => _inCash = false);
                        _update();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectChip(
                      label: 'Cash',
                      selected: _inCash,
                      fullWidth: true,
                      onTap: () {
                        setState(() => _inCash = true);
                        _update();
                      },
                    ),
                  ),
                ],
              ),
              if (_cashBlocked) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PaycheckColors.alert.withValues(alpha: 0.1),
                    borderRadius: AppRadius.card,
                  ),
                  child: Text(
                    'Cash donations above ₹2,000 are not eligible for 80G. '
                    'Pay digitally or by cheque to claim this deduction.',
                    style: PaycheckType.micro(color: PaycheckColors.alert),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Shared amount field ────────────────────────────────────────────────────
class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.helper,
  });
  final TextEditingController controller;
  final String label;
  final String? helper;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PaycheckType.bodyMedium()),
        if (helper != null) ...[
          const SizedBox(height: 2),
          Text(helper!,
              style: PaycheckType.micro(color: PaycheckColors.textSecondary)),
        ],
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: PaycheckType.body(),
          decoration: InputDecoration(
            hintText: 'Amount (₹)',
            hintStyle: PaycheckType.body(color: PaycheckColors.textSecondary),
            prefixText: '₹ ',
            prefixStyle: PaycheckType.body(color: PaycheckColors.gold),
            filled: true,
            fillColor: PaycheckColors.bgCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: PaycheckColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: PaycheckColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: PaycheckColors.gold, width: 1.5),
            ),
          ),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

int _parseAmount(TextEditingController c) =>
    int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

// ─── Business (self-employed presumptive income) ────────────────────────────
class _QBusiness extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _QBusiness({required this.profile, required this.onNext});
  @override
  ConsumerState<_QBusiness> createState() => _QBusinessState();
}

class _QBusinessState extends ConsumerState<_QBusiness> {
  late BusinessPresumption _scheme;
  final _receipts = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scheme = widget.profile.businessPresumption;
    if (widget.profile.businessGrossReceipts > 0) {
      _receipts.text = widget.profile.businessGrossReceipts.toString();
    }
  }

  @override
  void dispose() {
    _receipts.dispose();
    super.dispose();
  }

  void _update() {
    ref.read(userProfileProvider.notifier).updateField(
          (p) => p.copyWith(
            businessPresumption: _scheme,
            businessGrossReceipts: _parseAmount(_receipts),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final rate = _scheme == BusinessPresumption.profession44ADA
        ? 0.50
        : _scheme == BusinessPresumption.business44AD
            ? 0.08
            : 0.0;
    final presumptive = (_parseAmount(_receipts) * rate).round();
    return _QLayout(
      question: 'How do you earn your self-employed income?',
      microCopy: 'Presumptive schemes tax a fixed share of your receipts.',
      onNext: widget.onNext,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final opt in const [
              (
                BusinessPresumption.profession44ADA,
                'Profession (44ADA) — 50% taxable',
              ),
              (
                BusinessPresumption.business44AD,
                'Small business (44AD) — 8% taxable',
              ),
              (
                BusinessPresumption.none,
                'Regular books — I will enter net income as CTC',
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SelectChip(
                  label: opt.$2,
                  selected: _scheme == opt.$1,
                  fullWidth: true,
                  onTap: () {
                    setState(() => _scheme = opt.$1);
                    _update();
                  },
                ),
              ),
            if (_scheme != BusinessPresumption.none) ...[
              const SizedBox(height: 12),
              _AmountField(
                controller: _receipts,
                label: 'Annual gross receipts / turnover',
                onChanged: () => setState(_update),
              ),
              const SizedBox(height: 10),
              Text(
                'Taxable business income ≈ ₹${NumberFormat('#,##,##0', 'en_IN').format(presumptive)}',
                style: PaycheckType.micro(color: PaycheckColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Other income (capital gains, rent, misc) ───────────────────────────────
class _QOtherIncome extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _QOtherIncome({required this.profile, required this.onNext});
  @override
  ConsumerState<_QOtherIncome> createState() => _QOtherIncomeState();
}

class _QOtherIncomeState extends ConsumerState<_QOtherIncome> {
  final _stcg = TextEditingController();
  final _ltcgEq = TextEditingController();
  final _ltcgOther = TextEditingController();
  final _rent = TextEditingController();
  final _rentInterest = TextEditingController();
  final _other = TextEditingController();

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    void seed(TextEditingController c, int v) {
      if (v > 0) c.text = v.toString();
    }

    seed(_stcg, p.stcgEquity111A);
    seed(_ltcgEq, p.ltcgEquity112A);
    seed(_ltcgOther, p.ltcgOther112);
    seed(_rent, p.rentalIncomeAnnual);
    seed(_rentInterest, p.letOutHomeLoanInterest);
    seed(_other, p.otherSlabIncome);
  }

  @override
  void dispose() {
    for (final c in [
      _stcg,
      _ltcgEq,
      _ltcgOther,
      _rent,
      _rentInterest,
      _other
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _update() {
    ref.read(userProfileProvider.notifier).updateField(
          (p) => p.copyWith(
            stcgEquity111A: _parseAmount(_stcg),
            ltcgEquity112A: _parseAmount(_ltcgEq),
            ltcgOther112: _parseAmount(_ltcgOther),
            rentalIncomeAnnual: _parseAmount(_rent),
            letOutHomeLoanInterest: _parseAmount(_rentInterest),
            otherSlabIncome: _parseAmount(_other),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: 'Any income beyond your salary?',
      microCopy: 'Leave blank if none. These are taxed under both regimes.',
      onNext: widget.onNext,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _residentRow(),
            const SizedBox(height: 18),
            _AmountField(
              controller: _stcg,
              label: 'Short-term equity gains (STCG)',
              helper: 'Listed shares/funds held < 1 year — taxed at 20%.',
              onChanged: _update,
            ),
            const SizedBox(height: 14),
            _AmountField(
              controller: _ltcgEq,
              label: 'Long-term equity gains (LTCG)',
              helper: 'Listed shares/funds held > 1 year — 12.5% above ₹1.25L.',
              onChanged: _update,
            ),
            const SizedBox(height: 14),
            _AmountField(
              controller: _ltcgOther,
              label: 'Other long-term gains (property, gold…)',
              helper: 'Taxed at 12.5%.',
              onChanged: _update,
            ),
            const SizedBox(height: 14),
            _AmountField(
              controller: _rent,
              label: 'Annual rent received (let-out property)',
              onChanged: _update,
            ),
            const SizedBox(height: 14),
            _AmountField(
              controller: _rentInterest,
              label: 'Interest on that property loan',
              onChanged: _update,
            ),
            const SizedBox(height: 14),
            _AmountField(
              controller: _other,
              label: 'Other income (freelance, misc)',
              onChanged: _update,
            ),
          ],
        ),
      ),
    );
  }

  Widget _residentRow() {
    Widget chip(ResidentialStatus s, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SelectChip(
            label: label,
            selected: widget.profile.residentialStatus == s,
            onTap: () => ref
                .read(userProfileProvider.notifier)
                .updateField((p) => p.copyWith(residentialStatus: s)),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Residential status', style: PaycheckType.bodyMedium()),
        const SizedBox(height: 8),
        Wrap(
          children: [
            chip(ResidentialStatus.resident, 'Resident'),
            chip(ResidentialStatus.rnor, 'RNOR'),
            chip(ResidentialStatus.nonResident, 'NRI'),
          ],
        ),
      ],
    );
  }
}

// ─── Extra deductions (80U / 80DD / 80DDB / 80EEB / 80CCH) ───────────────────
class _QExtraDeductions extends ConsumerStatefulWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _QExtraDeductions({required this.profile, required this.onNext});
  @override
  ConsumerState<_QExtraDeductions> createState() => _QExtraDeductionsState();
}

class _QExtraDeductionsState extends ConsumerState<_QExtraDeductions> {
  late DisabilityLevel _self;
  late DisabilityLevel _dependent;
  late bool _ddbSenior;
  final _ddb = TextEditingController();
  final _ev = TextEditingController();

  @override
  void initState() {
    super.initState();
    _self = widget.profile.selfDisability;
    _dependent = widget.profile.dependentDisability;
    _ddbSenior = widget.profile.criticalIllnessPatientSenior;
    if ((widget.profile.criticalIllnessExpense ?? 0) > 0) {
      _ddb.text = widget.profile.criticalIllnessExpense.toString();
    }
    if (widget.profile.evLoanInterest > 0) {
      _ev.text = widget.profile.evLoanInterest.toString();
    }
  }

  @override
  void dispose() {
    _ddb.dispose();
    _ev.dispose();
    super.dispose();
  }

  void _update() {
    final ddb = _parseAmount(_ddb);
    ref.read(userProfileProvider.notifier).updateField(
          (p) => p.copyWith(
            selfDisability: _self,
            dependentDisability: _dependent,
            criticalIllnessExpense: ddb > 0 ? ddb : null,
            criticalIllnessPatientSenior: _ddbSenior,
            evLoanInterest: _parseAmount(_ev),
          ),
        );
  }

  Widget _levelRow(String title, DisabilityLevel value,
      ValueChanged<DisabilityLevel> onPick) {
    Widget chip(DisabilityLevel l, String label) => Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: SelectChip(
            label: label,
            selected: value == l,
            onTap: () => onPick(l),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: PaycheckType.bodyMedium()),
        const SizedBox(height: 8),
        Wrap(children: [
          chip(DisabilityLevel.none, 'None'),
          chip(DisabilityLevel.moderate, '40–79%'),
          chip(DisabilityLevel.severe, '80%+'),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: 'Disability, illness or an EV loan?',
      microCopy: 'Skip anything that does not apply.',
      onNext: widget.onNext,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _levelRow('Disability — you (80U)', _self, (l) {
              setState(() => _self = l);
              _update();
            }),
            const SizedBox(height: 16),
            _levelRow('Disability — a dependent (80DD)', _dependent, (l) {
              setState(() => _dependent = l);
              _update();
            }),
            const SizedBox(height: 16),
            _AmountField(
              controller: _ddb,
              label: 'Medical spend on a specified illness (80DDB)',
              onChanged: () => setState(_update),
            ),
            if (_parseAmount(_ddb) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectChip(
                  label: 'Patient is a senior citizen (higher ₹1L cap)',
                  selected: _ddbSenior,
                  onTap: () {
                    setState(() => _ddbSenior = !_ddbSenior);
                    _update();
                  },
                ),
              ),
            const SizedBox(height: 16),
            _AmountField(
              controller: _ev,
              label: 'EV loan interest (80EEB)',
              helper: 'Only for loans sanctioned Apr 2019 – Mar 2023.',
              onChanged: _update,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Q12: Age ─────────────────────────────────────────────────────────────────
class _Q12Age extends ConsumerWidget {
  final UserProfile profile;
  final VoidCallback onNext;
  const _Q12Age({required this.profile, required this.onNext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _QLayout(
      question: 'How old are you?',
      microCopy: 'Affects your tax slabs, rebates, and eligible deductions.',
      onNext: onNext,
      content: Column(
        children: [
          for (final age in AgeGroup.values) ...[
            SelectChip(
              label: age.label,
              selected: profile.ageGroup == age,
              fullWidth: true,
              onTap: () {
                ref
                    .read(userProfileProvider.notifier)
                    .updateField((p) => p.copyWith(ageGroup: age));
              },
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
