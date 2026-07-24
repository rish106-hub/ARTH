import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../models/payslip_tax_prefill.dart';
import '../providers/tax_document_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/user_profile_provider.dart';
import '../widgets/premium_ui.dart';
import '../widgets/question_progress_bar.dart';
import '../widgets/tax_journey_scene.dart';
import '../widgets/employer_picker.dart';

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
  int _step = 0; // 0–11 tax questions only
  bool _finishing = false;
  String? _appliedPayslipId;

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
    if (_step < 11) {
      setState(() => _step++);
      _slideCtrl.reset();
      _slideCtrl.forward();
    } else {
      _finish();
    }
  }

  Future<void> _prev() async {
    if (_step > 0) {
      HapticFeedback.lightImpact();
      setState(() => _step--);
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

    if (_finishing) {
      return const _BuildingPlanScreen();
    }

    final meta = _DiagnosticMeta.forStep(_step);

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
                            color: AppColors.textSecondary,
                          ),
                          onPressed: _prev,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: QuestionProgressBar(current: _step, total: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: _ChapterMarker(meta: meta, step: _step),
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
                    step: _step,
                    profile: profile,
                    meta: meta,
                    child: _buildStep(context, profile, _step),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, UserProfile p, int step) {
    switch (step) {
      case 0:
        return _Q01CTC(
          profile: p,
          payslipPrefill: ref.read(payslipTaxPrefillProvider),
          onNext: _next,
        );
      case 1:
        return _Q02Employment(
          profile: p,
          payslipPrefill: ref.read(payslipTaxPrefillProvider),
          onNext: _next,
        );
      case 2:
        return _Q03City(profile: p, onNext: _next);
      case 3:
        return _Q04Rent(profile: p, onNext: _next);
      case 4:
        return _Q05HRA(
          profile: p,
          payslipPrefill: ref.read(payslipTaxPrefillProvider),
          onNext: _next,
        );
      case 5:
        return _Q06EightyC(profile: p, onNext: _next);
      case 6:
        return _Q07HomeLoan(profile: p, onNext: _next);
      case 7:
        return _Q08NPS(profile: p, onNext: _next);
      case 8:
        return _Q09HealthInsurance(profile: p, onNext: _next);
      case 9:
        return _Q10EducationLoan(profile: p, onNext: _next);
      case 10:
        return _Q11Donations(profile: p, onNext: _next);
      case 11:
        return _Q12Age(profile: p, onNext: _next);
      default:
        return const SizedBox.shrink();
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

  static _DiagnosticMeta forStep(int step) {
    if (step <= 2) {
      return const _DiagnosticMeta(
        title: 'Income profile',
        helper: 'First, the shape of your income.',
        color: AppColors.gold,
      );
    }
    if (step <= 4) {
      return const _DiagnosticMeta(
        title: 'Housing and rent',
        helper: 'Next, where and how you live.',
        color: AppColors.teal,
      );
    }
    if (step <= 8) {
      return const _DiagnosticMeta(
        title: 'Deductions scan',
        helper: 'Now we check the deductions that apply to you.',
        color: AppColors.info,
      );
    }
    return const _DiagnosticMeta(
      title: 'Final checks',
      helper: 'A few final details before the result.',
      color: AppColors.amber,
    );
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
                  style: AppTextStyles.sectionLabel(
                    color: AppColors.textPrimary,
                  )),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: AppMotion.medium,
                child: Text(
                  meta.helper,
                  key: ValueKey(step ~/ 3),
                  style: AppTextStyles.caption(
                    color: AppColors.textSecondary,
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
                    style: AppTextStyles.h1().copyWith(fontSize: 40),
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
              color: complete ? AppColors.primary : AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(
              complete ? Icons.check_rounded : Icons.more_horiz_rounded,
              size: 17,
              color: complete ? Colors.white : AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 14),
          Text(label, style: AppTextStyles.bodyMedium()),
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
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.gold, width: 2),
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
        style: AppTextStyles.body(
          color: AppColors.textPrimary,
        ).copyWith(fontSize: 16),
        cursorColor: AppColors.gold,
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
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.gold, width: 2),
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
        style: AppTextStyles.body(
          color: AppColors.textPrimary,
        ).copyWith(fontSize: 16),
        cursorColor: AppColors.gold,
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
            style: AppTextStyles.h1().copyWith(fontSize: 32, height: 1.08),
          ),
          if (microCopy != null) ...[
            const SizedBox(height: 8),
            Text(
              microCopy!,
              style: AppTextStyles.caption(color: AppColors.textSecondary),
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
          style: AppTextStyles.displaySmall(color: AppColors.gold),
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
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_outlined,
            color: AppColors.success,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium()),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: AppTextStyles.micro(color: AppColors.textSecondary),
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
      if (val != null && val >= 1.0) {
        _value = val.clamp(1.0, 60.0); // keep slider in sync
      }
      // If input is empty / below min / mid-typing, _value holds the last
      // valid position — slider stays put, display shows raw typed value.
    });

    // Persist to profile only when value is in valid range.
    if (val != null && val >= 1.0) {
      final clamped = val.clamp(1.0, 60.0);
      ref.read(userProfileProvider.notifier).updateField(
            (p) => p.copyWith(annualCTC: (clamped * 100000).round()),
          );
    }
  }

  /// Called on blur/submit — snap to valid range.
  void _onTextSubmitted(String raw) {
    final val = double.tryParse(raw.trim()) ?? _value;
    final clamped = val.clamp(1.0, 60.0);
    setState(() => _value = clamped);
    _textCtrl.text = clamped.toStringAsFixed(1);
    ref
        .read(userProfileProvider.notifier)
        .updateField((p) => p.copyWith(annualCTC: (clamped * 100000).round()));
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
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Text input — value in Lakhs, suffix "L"
          TextField(
            controller: _textCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTextStyles.body(),
            decoration: InputDecoration(
              labelText: 'Enter in Lakhs',
              labelStyle: AppTextStyles.caption(color: AppColors.textSecondary),
              suffixText: 'L',
              suffixStyle: AppTextStyles.body(color: AppColors.gold),
              hintText: '15.0',
              hintStyle: AppTextStyles.body(color: AppColors.textMuted),
              helperText: 'Type 15 for ₹15 Lakhs  (min ₹1L)',
              helperStyle: AppTextStyles.micro(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.bgCard,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
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
              Text('₹1L', style: AppTextStyles.micro()),
              Text('₹60L', style: AppTextStyles.micro()),
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
      color = AppColors.success;
    } else if (ctcLakhs <= 12) {
      bracket = 'New regime: 87A rebate may apply. Compare both regimes.';
      color = AppColors.teal;
    } else if (ctcLakhs <= 15) {
      bracket = 'Close call — old vs new regime depends on deductions';
      color = AppColors.amber;
    } else {
      bracket = 'Old regime likely better if you have deductions';
      color = AppColors.gold;
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
            child: Text(bracket, style: AppTextStyles.micro(color: color)),
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

  static const _metros = ['Delhi', 'Mumbai', 'Chennai', 'Kolkata'];
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
    return _QLayout(
      question: 'Which city do you live in?',
      microCopy: 'Metro cities get higher HRA benefit.',
      onNext: widget.profile.city.trim().isNotEmpty ? widget.onNext : null,
      content: Column(
        children: [
          TextField(
            controller: _search,
            style: AppTextStyles.body(),
            decoration: InputDecoration(
              hintText: 'Search city...',
              hintStyle: AppTextStyles.body(color: AppColors.textSecondary),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
              filled: true,
              fillColor: AppColors.bgCard,
              border: const OutlineInputBorder(
                borderRadius: AppRadius.card,
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: AppRadius.card,
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: AppRadius.card,
                borderSide: BorderSide(color: AppColors.gold, width: 1.5),
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
              final isMetro = _metros.contains(city);
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
                        ? AppColors.gold.withValues(alpha: 0.1)
                        : AppColors.bgCard,
                    borderRadius: AppRadius.card,
                    border: Border.all(
                      color: selected ? AppColors.gold : AppColors.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          city,
                          style: AppTextStyles.body(
                            color: selected
                                ? AppColors.gold
                                : AppColors.textPrimary,
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
                            color: AppColors.teal.withValues(alpha: 0.15),
                            borderRadius: AppRadius.pill,
                          ),
                          child: Text(
                            'Metro',
                            style: AppTextStyles.micro(color: AppColors.teal),
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
                        isMetroCity: false,
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
      if (val != null && val >= 1.0) {
        _rentK = val.clamp(1.0, 200.0);
      }
    });

    if (val != null && val >= 1.0) {
      final clamped = val.clamp(1.0, 200.0);
      ref.read(userProfileProvider.notifier).updateField(
            (p) => p.copyWith(monthlyRent: (clamped * 1000).round()),
          );
    }
  }

  void _onRentTextSubmitted(String raw) {
    final val = double.tryParse(raw.trim()) ?? _rentK;
    final clamped = val.clamp(1.0, 200.0);
    setState(() => _rentK = clamped);
    _rentTextCtrl.text = clamped.toStringAsFixed(0);
    ref
        .read(userProfileProvider.notifier)
        .updateField((p) => p.copyWith(monthlyRent: (clamped * 1000).round()));
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
            Text('How much rent per month?', style: AppTextStyles.h3()),
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
              style: AppTextStyles.body(),
              decoration: InputDecoration(
                labelText: 'Enter in Thousands',
                labelStyle: AppTextStyles.caption(
                  color: AppColors.textSecondary,
                ),
                suffixText: 'K / mo',
                suffixStyle: AppTextStyles.body(color: AppColors.gold),
                hintText: '15',
                hintStyle: AppTextStyles.body(color: AppColors.textMuted),
                helperText: 'Type 15 for ₹15,000/month',
                helperStyle: AppTextStyles.micro(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.bgCard,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppColors.gold,
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
                Text('₹1K', style: AppTextStyles.micro()),
                Text('₹2,00,000', style: AppTextStyles.micro()),
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
              color: AppColors.bgCard,
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'If you don\'t receive HRA but pay rent, you may still be able to claim deduction under Section 80GG.',
              style: AppTextStyles.micro(color: AppColors.textSecondary),
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
          Center(
            child: Column(
              children: [
                Text(
                  '₹ ${_fmt.format(_invested)} invested',
                  style: AppTextStyles.h2(color: AppColors.gold),
                ),
                const SizedBox(height: 4),
                if (_remaining > 0)
                  Text(
                    '₹ ${_fmt.format(_remaining)} remaining in 80C limit',
                    style: AppTextStyles.caption(color: AppColors.amber),
                  )
                else
                  Text(
                    '80C fully utilised',
                    style: AppTextStyles.caption(color: AppColors.success),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Text input — accepts raw rupees (0 – 1,50,000)
          TextField(
            controller: _textCtrl,
            keyboardType: TextInputType.number,
            style: AppTextStyles.body(),
            decoration: InputDecoration(
              labelText: 'Enter amount in ₹',
              labelStyle: AppTextStyles.caption(color: AppColors.textSecondary),
              prefixText: '₹ ',
              prefixStyle: AppTextStyles.body(color: AppColors.gold),
              hintText: '1,50,000',
              hintStyle: AppTextStyles.body(color: AppColors.textMuted),
              helperText: 'Max ₹1,50,000 under 80C',
              helperStyle: AppTextStyles.micro(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.bgCard,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
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
              Text('₹0', style: AppTextStyles.micro()),
              Text('₹1,50,000', style: AppTextStyles.micro()),
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
            Text('80C utilisation', style: AppTextStyles.micro()),
            const Spacer(),
            Text('₹1,50,000 limit', style: AppTextStyles.micro()),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: AppRadius.pill,
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: AppColors.bgSurface,
            valueColor: AlwaysStoppedAnimation<Color>(
              pct >= 1.0 ? AppColors.success : AppColors.gold,
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
    if (val != null) {
      final l = (val / 100000).clamp(0.25, 5.0);
      setState(() => _interestL = l);
      ref.read(userProfileProvider.notifier).updateField(
            (p) => p.copyWith(homeLoanInterest: (l * 100000).round()),
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
                style: AppTextStyles.h3(),
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
                style: AppTextStyles.h3(),
              ),
              const SizedBox(height: 8),
              _ResponsiveAmount(
                '₹ ${(_interestL * 100000).round().toString().replaceAllMapped(RegExp(r'(\d{1,2})(?=(\d{2})+(?!\d))'), (m) => '${m[1]},')}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _interestTextCtrl,
                keyboardType: TextInputType.number,
                style: AppTextStyles.body(),
                decoration: InputDecoration(
                  hintText: 'Enter amount (₹)',
                  hintStyle: AppTextStyles.body(color: AppColors.textSecondary),
                  prefixText: '₹ ',
                  prefixStyle: AppTextStyles.body(color: AppColors.gold),
                  filled: true,
                  fillColor: AppColors.bgCard,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.gold,
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
                  color: AppColors.gold.withValues(alpha: 0.07),
                  borderRadius: AppRadius.card,
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What is NPS?',
                      style: AppTextStyles.bodyMedium(color: AppColors.gold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'National Pension System (NPS) is a government-backed retirement savings scheme. Opening an NPS Tier-1 account and contributing ₹50,000/year gives you an EXTRA ₹50,000 deduction under Section 80CCD(1B) — over and above your 80C limit.',
                      style: AppTextStyles.micro(
                        color: AppColors.textSecondary,
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
                style: AppTextStyles.h3(),
              ),
              const SizedBox(height: 4),
              Text(
                '(Voluntary contribution over and above 80CCE limit)',
                style: AppTextStyles.micro(),
              ),
              const SizedBox(height: 12),
              _ResponsiveAmount('₹ ${(_extraK * 1000).round()} extra'),
              const SizedBox(height: 12),
              TextField(
                controller: _npsTextCtrl,
                keyboardType: TextInputType.number,
                style: AppTextStyles.body(),
                decoration: InputDecoration(
                  hintText: 'Enter amount (₹)',
                  hintStyle: AppTextStyles.body(color: AppColors.textSecondary),
                  prefixText: '₹ ',
                  prefixStyle: AppTextStyles.body(color: AppColors.gold),
                  filled: true,
                  fillColor: AppColors.bgCard,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.gold,
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

  @override
  void initState() {
    super.initState();
    _self = widget.profile.hasHealthInsuranceSelf;
    _parents = widget.profile.hasHealthInsuranceParents;
    _parentsAbove60 = widget.profile.parentsAbove60;
  }

  void _update() {
    ref.read(userProfileProvider.notifier).updateField(
          (p) => p.copyWith(
            hasHealthInsuranceSelf: _self,
            hasHealthInsuranceParents: _parents,
            parentsAbove60: _parentsAbove60,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: 'Health insurance — who is covered?',
      microCopy: 'Select all that apply.',
      onNext: widget.onNext,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tap to select:', style: AppTextStyles.caption()),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              MultiSelectChip(
                label: 'Self',
                selected: _self,
                onTap: () {
                  setState(() => _self = !_self);
                  _update();
                },
              ),
              MultiSelectChip(
                label: 'Spouse',
                selected: _self, // same policy
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
          if (_parents) ...[
            const SizedBox(height: 24),
            Text('Are your parents above 60?', style: AppTextStyles.h3()),
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
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.07),
                borderRadius: AppRadius.card,
              ),
              child: Text(
                _parentsAbove60
                    ? 'Senior parent coverage = ₹50,000 extra deduction under 80D.'
                    : 'Parent coverage = ₹25,000 deduction under 80D.',
                style: AppTextStyles.micro(color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
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
    if (val != null) {
      final k = (val / 1000).clamp(5.0, 200.0);
      setState(() => _interestK = k);
      ref.read(userProfileProvider.notifier).updateField(
            (p) => p.copyWith(educationLoanInterest: (k * 1000).round()),
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
                style: AppTextStyles.h3(),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Year ${_year.round()} of 8',
                  style: AppTextStyles.h2(color: AppColors.gold),
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
                style: AppTextStyles.h3(),
              ),
              const SizedBox(height: 4),
              Text(
                '80E allows full interest deduction — no upper limit!',
                style: AppTextStyles.micro(color: AppColors.success),
              ),
              const SizedBox(height: 8),
              _ResponsiveAmount('₹ ${(_interestK * 1000).round()} / year'),
              const SizedBox(height: 12),
              TextField(
                controller: _edLoanTextCtrl,
                keyboardType: TextInputType.number,
                style: AppTextStyles.body(),
                decoration: InputDecoration(
                  hintText: 'Enter amount (₹)',
                  hintStyle: AppTextStyles.body(color: AppColors.textSecondary),
                  prefixText: '₹ ',
                  prefixStyle: AppTextStyles.body(color: AppColors.gold),
                  filled: true,
                  fillColor: AppColors.bgCard,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.gold,
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
  double _amountK = 5;
  final TextEditingController _donationTextCtrl = TextEditingController(
    text: '5000',
  );

  @override
  void initState() {
    super.initState();
    final amount = widget.profile.donationAmount;
    _hasDonations = widget.profile.hasDonations || amount > 0 ? true : null;
    _amountK = amount > 0 ? (amount / 1000).clamp(0.5, 100.0) : 5.0;
    _donationTextCtrl.text = (_amountK * 1000).round().toString();
  }

  @override
  void dispose() {
    _donationTextCtrl.dispose();
    super.dispose();
  }

  void _onDonationTextChanged(String raw) {
    final stripped = raw.replaceAll(',', '').replaceAll(' ', '');
    final val = int.tryParse(stripped);
    if (val != null) {
      final k = (val / 1000).clamp(0.5, 100.0);
      setState(() => _amountK = k);
      ref
          .read(userProfileProvider.notifier)
          .updateField((p) => p.copyWith(donationAmount: (k * 1000).round()));
    }
  }

  void _onDonationSliderChanged(double v) {
    setState(() => _amountK = v);
    _donationTextCtrl.text = (v * 1000).round().toString();
    ref.read(userProfileProvider.notifier).updateField(
          (p) => p.copyWith(donationAmount: (_amountK * 1000).round()),
        );
  }

  @override
  Widget build(BuildContext context) {
    return _QLayout(
      question: 'Did you make any donations this year?',
      microCopy: 'PM Relief Fund, NGOs, temple trusts with 80G certificate.',
      onNext: _hasDonations != null ? widget.onNext : null,
      content: Column(
        children: [
          SelectChip(
            label: 'Yes — PM Relief / NGO / temple',
            selected: _hasDonations == true,
            fullWidth: true,
            onTap: () {
              setState(() => _hasDonations = true);
              ref
                  .read(userProfileProvider.notifier)
                  .updateField((p) => p.copyWith(hasDonations: true));
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
            Text('Approximate amount donated?', style: AppTextStyles.h3()),
            const SizedBox(height: 8),
            _ResponsiveAmount('₹ ${(_amountK * 1000).round()}'),
            const SizedBox(height: 12),
            TextField(
              controller: _donationTextCtrl,
              keyboardType: TextInputType.number,
              style: AppTextStyles.body(),
              decoration: InputDecoration(
                hintText: 'Enter amount (₹)',
                hintStyle: AppTextStyles.body(color: AppColors.textSecondary),
                prefixText: '₹ ',
                prefixStyle: AppTextStyles.body(color: AppColors.gold),
                filled: true,
                fillColor: AppColors.bgCard,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppColors.gold,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: _onDonationTextChanged,
            ),
            Slider(
              value: _amountK,
              min: 0.5,
              max: 100,
              divisions: 40,
              label: '₹${_amountK.round()}K',
              onChanged: _onDonationSliderChanged,
            ),
          ],
        ],
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
