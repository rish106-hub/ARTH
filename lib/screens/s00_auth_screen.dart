import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../models/user_account.dart';
import '../providers/auth_provider.dart';
import '../providers/feature_flags_provider.dart';
import '../widgets/glass_card.dart';

// ─── AUTH STEPS ───────────────────────────────────────────────────────────────
enum _AuthStep { details, otp }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  _AuthStep _step = _AuthStep.details;
  bool _biometricsEnabled = false;
  bool _biometricsAvailable = false;
  bool _loading = false;
  bool _isReturningUser = false;

  static final _phoneRegex = RegExp(r'^[6-9]\d{9}$');

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _checkReturningUser();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    final available = await ref.read(authProvider.notifier).hasBiometrics();
    if (mounted) setState(() => _biometricsAvailable = available);
  }

  /// If a saved account exists with this phone, pre-fill name (returning user).
  Future<void> _checkReturningUser() async {
    final existing = ref.read(authProvider);
    if (existing != null && existing.phone.isNotEmpty) {
      if (mounted) {
        setState(() {
          _nameCtrl.text = existing.name;
          _phoneCtrl.text = existing.phone;
          _isReturningUser = true;
        });
      }
    }
  }

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Full name is required';
    final trimmed = v.trim();
    if (trimmed.length < 2) return 'Enter a valid name';
    if (RegExp(r"""[<>"';&]""").hasMatch(trimmed)) return 'Invalid characters';
    return null;
  }

  String? _validatePhone(String? v) {
    if (v == null || v.isEmpty) return 'Mobile number is required';
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (!_phoneRegex.hasMatch(digits)) {
      return 'Enter a valid 10-digit Indian mobile number';
    }
    return null;
  }

  String? _validateOtp(String? v) {
    if (v == null || v.trim().length != 6) return 'Enter the 6-digit OTP';
    if (!RegExp(r'^\d{6}$').hasMatch(v.trim())) return 'OTP must be 6 digits';
    return null;
  }

  /// Step 1 — validate details and either send OTP or skip straight to account.
  Future<void> _onContinue() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      final otpEnabled =
          await ref.read(phoneOtpEnabledProvider.future).catchError((_) => false);

      if (otpEnabled) {
        // TODO: trigger Firebase Phone Auth SMS here when Firebase is restored.
        // await FirebaseAuth.instance.verifyPhoneNumber(phoneNumber: '+91${_phoneCtrl.text.trim()}', ...);
        if (mounted) setState(() => _step = _AuthStep.otp);
      } else {
        // OTP disabled — create / restore account directly
        await _finalizeAccount(otp: null);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Step 2 — verify OTP (currently bypassed until Firebase is live).
  Future<void> _onVerifyOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      // TODO: verify OTP with Firebase when live
      // await FirebaseAuth.instance.signInWithCredential(...)
      await _finalizeAccount(otp: _otpCtrl.text.trim());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finalizeAccount({required String? otp}) async {
    final phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    final account = UserAccount(
      name: _nameCtrl.text.trim(),
      phone: phone,
      incomeRange: '',
      biometricsEnabled: _biometricsEnabled,
      createdAt: DateTime.now(),
      authMethod: AuthMethod.manual,
    );

    await ref.read(authProvider.notifier).saveAccount(account);
    if (mounted) context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A0A), Color(0xFF141414)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: size.width * 0.06,
              vertical: 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: size.height * 0.04),
                _AuthHeader()
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .slideY(begin: -0.2),
                SizedBox(height: size.height * 0.05),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: _step == _AuthStep.details
                      ? _DetailsCard(key: const ValueKey('details'), state: this)
                      : _OtpCard(key: const ValueKey('otp'), state: this),
                )
                    .animate(delay: 100.ms)
                    .fadeIn(duration: 600.ms)
                    .slideY(begin: 0.1),
                SizedBox(height: size.height * 0.04),
                if (_step == _AuthStep.details)
                  Center(
                    child: TextButton(
                      onPressed: () {},
                      child: Text(
                        _isReturningUser
                            ? 'Not you? Clear account'
                            : 'Already have an account? Sign in',
                        style: AppTextStyles.caption(
                            color: AppColors.textSecondary),
                      ),
                    ),
                  ).animate(delay: 700.ms).fadeIn(duration: 400.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── DETAILS CARD (Step 1) ────────────────────────────────────────────────────
class _DetailsCard extends StatelessWidget {
  final _AuthScreenState state;
  const _DetailsCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      blur: 16,
      padding: const EdgeInsets.all(28),
      child: Form(
        key: state._formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state._isReturningUser ? 'Welcome back' : 'Create your account',
              style: AppTextStyles.h2(),
            ),
            const SizedBox(height: 6),
            Text(
              state._isReturningUser
                  ? 'Verify your number to access your tax data.'
                  : 'Your number is your identity. No PAN needed to start.',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),

            // Full Name
            _GlassInputField(
              controller: state._nameCtrl,
              label: 'Full Name',
              hint: 'Your name',
              validator: state._validateName,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
            ).animate(delay: 200.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: 16),

            // Phone Number
            _GlassInputField(
              controller: state._phoneCtrl,
              label: 'Mobile Number',
              hint: '9876543210',
              validator: state._validatePhone,
              keyboardType: TextInputType.phone,
              prefixText: '+91  ',
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
            ).animate(delay: 300.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: 8),
            _OtpStatusBadge()
                .animate(delay: 350.ms)
                .fadeIn(duration: 300.ms),

            const SizedBox(height: 16),

            // Biometrics toggle
            if (state._biometricsAvailable)
              _BiometricsToggle(
                value: state._biometricsEnabled,
                onChanged: (v) =>
                    state.setState(() => state._biometricsEnabled = v),
              ).animate(delay: 400.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: 28),

            // Continue / Send OTP button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: AppButtons.primaryGold,
                onPressed: state._loading ? null : state._onContinue,
                child: state._loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Text(state._isReturningUser ? 'Sign In' : 'Continue'),
              ),
            ).animate(delay: 500.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: 16),
            _GoogleSignInButton().animate(delay: 600.ms).fadeIn(duration: 400.ms),
          ],
        ),
      ),
    );
  }
}

// ─── OTP CARD (Step 2) ────────────────────────────────────────────────────────
class _OtpCard extends StatelessWidget {
  final _AuthScreenState state;
  const _OtpCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final maskedPhone = state._phoneCtrl.text.isNotEmpty
        ? '••••••${state._phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '').substring(6)}'
        : '';

    return GlassCard(
      blur: 16,
      padding: const EdgeInsets.all(28),
      child: Form(
        key: state._formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => state.setState(() => state._step = _AuthStep.details),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.gold, size: 22),
                ),
                const SizedBox(width: 12),
                Text('Verify OTP', style: AppTextStyles.h2()),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'We sent a 6-digit code to +91 $maskedPhone',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),

            _GlassInputField(
              controller: state._otpCtrl,
              label: 'One-Time Password',
              hint: '• • • • • •',
              validator: state._validateOtp,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: AppButtons.primaryGold,
                onPressed: state._loading ? null : state._onVerifyOtp,
                child: state._loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text('Verify & Continue'),
              ),
            ),

            const SizedBox(height: 12),

            Center(
              child: TextButton(
                onPressed: state._loading ? null : state._onContinue,
                child: Text(
                  'Resend OTP',
                  style: AppTextStyles.caption(color: AppColors.gold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── OTP STATUS BADGE ─────────────────────────────────────────────────────────
/// Shows whether OTP verification is active or skipped (feature-flagged).
class _OtpStatusBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otpEnabled = ref.watch(phoneOtpEnabledProvider).valueOrNull ?? false;
    return Row(
      children: [
        Icon(
          otpEnabled ? Icons.verified_rounded : Icons.info_outline_rounded,
          size: 12,
          color: otpEnabled ? AppColors.teal : AppColors.textMuted,
        ),
        const SizedBox(width: 5),
        Text(
          otpEnabled
              ? 'OTP will be sent via SMS'
              : 'OTP verification coming soon — account created locally',
          style: AppTextStyles.micro(
              color: otpEnabled ? AppColors.teal : AppColors.textMuted),
        ),
      ],
    );
  }
}

// ─── AUTH HEADER ─────────────────────────────────────────────────────────────
class _AuthHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '₹',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: AppColors.gold,
                height: 1,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'ARTH',
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: 6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Not a rupee less. Not a rupee more.',
          style: AppTextStyles.micro(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ─── GLASS INPUT FIELD ────────────────────────────────────────────────────────
class _GlassInputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final String? prefixText;

  const _GlassInputField({
    required this.controller,
    required this.label,
    required this.hint,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.prefixText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.caption(color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          style: AppTextStyles.body(),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.body(color: AppColors.textMuted),
            prefixText: prefixText,
            prefixStyle: AppTextStyles.body(color: AppColors.textSecondary),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.04),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.alert, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.alert, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── BIOMETRICS TOGGLE ────────────────────────────────────────────────────────
class _BiometricsToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _BiometricsToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.fingerprint_rounded,
            color: value ? AppColors.gold : AppColors.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Enable Face / Fingerprint Unlock',
                    style: AppTextStyles.bodyMedium()),
                Text('Use biometrics to open ARTH faster',
                    style:
                        AppTextStyles.micro(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.gold,
            inactiveTrackColor: AppColors.bgSurface,
          ),
        ],
      ),
    );
  }
}

// ─── GOOGLE SIGN-IN (FEATURE-FLAGGED V2) ─────────────────────────────────────
class _GoogleSignInButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_GoogleSignInButton> createState() =>
      _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<_GoogleSignInButton> {
  bool _loading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _loading = true);
    try {
      final account =
          await ref.read(googleAuthServiceProvider).signInWithGoogle();
      if (account != null && mounted) {
        await ref.read(authProvider.notifier).saveAccount(account);
        if (mounted) context.go('/welcome');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled =
        ref.watch(googleSignInEnabledProvider).valueOrNull ?? false;

    if (isEnabled) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          onPressed: _loading ? null : _handleGoogleSignIn,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.gold),
                )
              : const Icon(Icons.g_mobiledata_rounded, size: 22),
          label: Text(_loading ? 'Signing in…' : 'Continue with Google'),
        ),
      );
    }

    // Feature flag off — greyed out with V2 badge
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 0.4,
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
              ),
              onPressed: null,
              icon: const Icon(Icons.g_mobiledata_rounded, size: 22),
              label: const Text('Continue with Google'),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'V2',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
