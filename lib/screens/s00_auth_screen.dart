import 'package:firebase_auth/firebase_auth.dart';
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
enum _AuthStep {
  details,     // Step 1 — name + phone number
  otp,         // Step 2 — OTP verification (phone or Google flow)
  googlePhone, // Step 2b — add phone number after Google sign-in
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _nameCtrl           = TextEditingController();
  final _phoneCtrl          = TextEditingController();
  final _otpCtrl            = TextEditingController();
  final _formKey            = GlobalKey<FormState>();
  final _otpFormKey         = GlobalKey<FormState>();
  final _googlePhoneFormKey = GlobalKey<FormState>();

  _AuthStep _step               = _AuthStep.details;
  bool _biometricsEnabled       = false;
  bool _biometricsAvailable     = false;
  bool _loading                 = false;
  bool _isReturningUser         = false;
  String? _errorMessage;
  int  _resendSeconds           = 0;
  bool _canResend               = false;

  // Holds the Google-signed-in account until phone is verified
  UserAccount? _pendingGoogleAccount;

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

  Future<void> _checkReturningUser() async {
    final existing = ref.read(authProvider);
    if (existing != null && existing.phone.isNotEmpty) {
      if (mounted) {
        setState(() {
          _nameCtrl.text  = existing.name;
          _phoneCtrl.text = existing.phone.replaceAll(RegExp(r'\D'), '');
          _isReturningUser = true;
        });
      }
    }
  }

  void _setError(String? msg) {
    if (mounted) setState(() => _errorMessage = msg);
  }

  // ── Validators ─────────────────────────────────────────────────────────────
  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Full name is required';
    if (v.trim().length < 2) return 'Enter a valid name';
    if (RegExp(r"""[<>"';&]""").hasMatch(v.trim())) return 'Invalid characters';
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

  // ── Step 1: Continue — sends OTP via Firebase Phone Auth ──────────────────
  Future<void> _onContinue() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _setError(null);
    setState(() => _loading = true);

    try {
      final phone = '+91${_phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '')}';

      await ref.read(phoneAuthServiceProvider).sendOtp(
        phoneNumber: phone,
        onCodeSent: (_) {
          if (mounted) {
            setState(() {
              _step = _AuthStep.otp;
              _otpCtrl.clear();
            });
            _startResendTimer();
          }
        },
        onError: (msg) => _setError(msg),
        onAutoVerified: () async {
          // Android auto-read SMS — finalize immediately without OTP entry
          final fbUser = FirebaseAuth.instance.currentUser;
          if (fbUser != null && mounted) {
            await _finalizeManualAccount(uid: fbUser.uid);
          }
        },
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Step 2: Verify OTP (manual phone flow) ─────────────────────────────────
  Future<void> _onVerifyOtp() async {
    if (!(_otpFormKey.currentState?.validate() ?? false)) return;
    _setError(null);
    setState(() => _loading = true);

    try {
      final user = await ref
          .read(phoneAuthServiceProvider)
          .verifyOtp(_otpCtrl.text.trim());

      if (user == null) {
        _setError('Verification failed. Please try again.');
        return;
      }

      if (_pendingGoogleAccount != null) {
        await _saveGoogleAccountWithPhone(user);
      } else {
        await _finalizeManualAccount(uid: user.uid);
      }
    } on FirebaseAuthException catch (e) {
      _setError(_mapOtpError(e.code));
    } on StateError catch (e) {
      // verificationId expired (e.g. hot-restart between steps)
      _setError(e.message);
    } catch (e) {
      // PlatformException or other — show the real message for easier debugging
      final msg = e.toString().replaceFirst('Exception: ', '');
      _setError(msg.isNotEmpty ? msg : 'Verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Google Sign-In ─────────────────────────────────────────────────────────
  Future<void> _onGoogleSignIn() async {
    _setError(null);
    setState(() => _loading = true);

    try {
      final account =
          await ref.read(googleAuthServiceProvider).signInWithGoogle();
      if (account == null) return; // user cancelled

      // Google account already has phone number (rare) — go directly
      if (account.phone.isNotEmpty) {
        await ref.read(authProvider.notifier).saveAccount(account);
        if (mounted) context.go('/welcome');
        return;
      }

      // No phone yet — collect it in Step 2b
      if (mounted) {
        setState(() {
          _pendingGoogleAccount = account;
          _nameCtrl.text = account.name;
          _phoneCtrl.clear();
          _step = _AuthStep.googlePhone;
        });
      }
    } catch (_) {
      _setError('Google Sign-In failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Step 2b: Google user adds phone → send OTP ─────────────────────────────
  Future<void> _onGooglePhoneContinue() async {
    if (!(_googlePhoneFormKey.currentState?.validate() ?? false)) return;
    _setError(null);
    setState(() => _loading = true);

    try {
      final phone =
          '+91${_phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '')}';

      await ref.read(phoneAuthServiceProvider).sendOtp(
        phoneNumber: phone,
        onCodeSent: (_) {
          if (mounted) {
            setState(() {
              _step = _AuthStep.otp;
              _otpCtrl.clear();
            });
            _startResendTimer();
          }
        },
        onError: (msg) => _setError(msg),
        onAutoVerified: () async {
          final fbUser = FirebaseAuth.instance.currentUser;
          if (fbUser != null && _pendingGoogleAccount != null && mounted) {
            await _saveGoogleAccountWithPhone(fbUser);
          }
        },
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Future<void> _finalizeManualAccount({required String uid}) async {
    final account = UserAccount(
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), ''),
      incomeRange: '',
      biometricsEnabled: _biometricsEnabled,
      createdAt: DateTime.now(),
      uid: uid,
      authMethod: AuthMethod.manual,
    );
    await ref.read(authProvider.notifier).saveAccount(account);
    if (mounted) context.go('/welcome');
  }

  Future<void> _saveGoogleAccountWithPhone(User fbUser) async {
    final phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    final updated = _pendingGoogleAccount!.copyWith(
      phone: phone,
      biometricsEnabled: _biometricsEnabled,
    );
    await ref.read(authProvider.notifier).saveAccount(updated);
    if (mounted) context.go('/welcome');
  }

  void _startResendTimer() {
    setState(() {
      _resendSeconds = 30;
      _canResend = false;
    });
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) _canResend = true;
      });
      return _resendSeconds > 0;
    });
  }

  Future<void> _onResendOtp() async {
    if (!_canResend) return;
    _setError(null);
    setState(() => _loading = true);
    try {
      final phone =
          '+91${_phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '')}';
      await ref.read(phoneAuthServiceProvider).resendOtp(
        phoneNumber: phone,
        onCodeSent: (_) {
          if (mounted) {
            setState(() => _otpCtrl.clear());
            _startResendTimer();
          }
        },
        onError: (msg) => _setError(msg),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapOtpError(String code) {
    switch (code) {
      case 'invalid-verification-code':
        return 'Incorrect OTP. Please check and try again.';
      case 'session-expired':
        return 'OTP expired. Tap Resend to get a new one.';
      case 'credential-already-in-use':
        return 'This number is already linked to another account.';
      default:
        return 'Verification failed ($code). Please try again.';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
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

                if (_errorMessage != null) ...[
                  _ErrorBanner(message: _errorMessage!)
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .slideY(begin: -0.1),
                  const SizedBox(height: 12),
                ],

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: switch (_step) {
                    _AuthStep.details => _DetailsCard(
                        key: const ValueKey('details'), state: this),
                    _AuthStep.googlePhone => _GooglePhoneCard(
                        key: const ValueKey('googlePhone'), state: this),
                    _AuthStep.otp => _OtpCard(
                        key: const ValueKey('otp'), state: this),
                  },
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

// ─── ERROR BANNER ─────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.alert.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.alert.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.alert, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: AppTextStyles.caption(color: AppColors.alert)),
          ),
        ],
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

            _GlassInputField(
              controller: state._nameCtrl,
              label: 'Full Name',
              hint: 'Your name',
              validator: state._validateName,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
            ).animate(delay: 200.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: 16),

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

            if (state._biometricsAvailable) ...[
              const SizedBox(height: 16),
              _BiometricsToggle(
                value: state._biometricsEnabled,
                onChanged: (v) =>
                    state.setState(() => state._biometricsEnabled = v),
              ).animate(delay: 400.ms).fadeIn(duration: 400.ms),
            ],

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: AppButtons.primaryGold,
                onPressed: state._loading ? null : state._onContinue,
                child: state._loading
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : Text(state._isReturningUser ? 'Send OTP' : 'Continue'),
              ),
            ).animate(delay: 500.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: 16),
            _OrDivider().animate(delay: 560.ms).fadeIn(duration: 300.ms),
            const SizedBox(height: 16),

            _GoogleSignInButton(
              onTap: state._onGoogleSignIn,
              loading: state._loading,
            ).animate(delay: 600.ms).fadeIn(duration: 400.ms),
          ],
        ),
      ),
    );
  }
}

// ─── GOOGLE PHONE CARD (Step 2b) ──────────────────────────────────────────────
class _GooglePhoneCard extends StatelessWidget {
  final _AuthScreenState state;
  const _GooglePhoneCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final name = state._pendingGoogleAccount?.name ?? '';

    return GlassCard(
      blur: 16,
      padding: const EdgeInsets.all(28),
      child: Form(
        key: state._googlePhoneFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => state.setState(() {
                    state._step = _AuthStep.details;
                    state._pendingGoogleAccount = null;
                  }),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.gold, size: 22),
                ),
                const SizedBox(width: 12),
                Text('One more step', style: AppTextStyles.h2()),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Hi $name 👋  Add your mobile number so we can verify your identity with OTP.',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),

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
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: AppButtons.primaryGold,
                onPressed:
                    state._loading ? null : state._onGooglePhoneContinue,
                child: state._loading
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text('Send OTP'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── OTP CARD (Step 2 / 2b) ───────────────────────────────────────────────────
class _OtpCard extends StatelessWidget {
  final _AuthScreenState state;
  const _OtpCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final digits = state._phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    final masked = digits.length >= 4
        ? '••••••${digits.substring(digits.length - 4)}'
        : digits;
    final isGoogleFlow = state._pendingGoogleAccount != null;

    return GlassCard(
      blur: 16,
      padding: const EdgeInsets.all(28),
      child: Form(
        key: state._otpFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => state.setState(() {
                    state._step = isGoogleFlow
                        ? _AuthStep.googlePhone
                        : _AuthStep.details;
                    state._otpCtrl.clear();
                  }),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.gold, size: 22),
                ),
                const SizedBox(width: 12),
                Text('Verify OTP', style: AppTextStyles.h2()),
              ],
            ),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: AppTextStyles.caption(color: AppColors.textSecondary),
                children: [
                  const TextSpan(text: 'We sent a 6-digit code to '),
                  TextSpan(
                    text: '+91 $masked',
                    style:
                        AppTextStyles.caption(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            _OtpInputField(
              controller: state._otpCtrl,
              validator: state._validateOtp,
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: AppButtons.primaryGold,
                onPressed:
                    state._loading ? null : state._onVerifyOtp,
                child: state._loading
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text('Verify & Continue'),
              ),
            ),

            const SizedBox(height: 16),

            Center(
              child: state._canResend
                  ? TextButton(
                      onPressed:
                          state._loading ? null : state._onResendOtp,
                      child: Text('Resend OTP',
                          style: AppTextStyles.caption(
                              color: AppColors.gold)),
                    )
                  : Text(
                      'Resend in ${state._resendSeconds}s',
                      style: AppTextStyles.caption(
                          color: AppColors.textMuted),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── OTP INPUT FIELD ──────────────────────────────────────────────────────────
class _OtpInputField extends StatelessWidget {
  final TextEditingController controller;
  final String? Function(String?)? validator;
  const _OtpInputField({required this.controller, this.validator});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      autofocus: true,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      style: const TextStyle(
        fontFamily: 'SpaceGrotesk',
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: 16,
      ),
      decoration: InputDecoration(
        hintText: '------',
        hintStyle: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: 24,
          color: AppColors.textMuted,
          letterSpacing: 12,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
          borderSide:
              const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.alert, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.alert, width: 1.5),
        ),
      ),
    );
  }
}

// ─── OR DIVIDER ───────────────────────────────────────────────────────────────
class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Divider(
                color: Colors.white.withValues(alpha: 0.1), height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or',
              style: AppTextStyles.micro(color: AppColors.textMuted)),
        ),
        Expanded(
            child: Divider(
                color: Colors.white.withValues(alpha: 0.1), height: 1)),
      ],
    );
  }
}

// ─── OTP STATUS BADGE ─────────────────────────────────────────────────────────
class _OtpStatusBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        const Icon(Icons.verified_rounded, size: 12, color: AppColors.teal),
        const SizedBox(width: 5),
        Text(
          'OTP will be sent via SMS to verify your number',
          style: AppTextStyles.micro(color: AppColors.teal),
        ),
      ],
    );
  }
}

// ─── AUTH HEADER ──────────────────────────────────────────────────────────────
class _AuthHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
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
            const Text(
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
              borderSide:
                  const BorderSide(color: AppColors.gold, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.alert, width: 1),
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
          Icon(Icons.fingerprint_rounded,
              color: value ? AppColors.gold : AppColors.textSecondary,
              size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Enable Face / Fingerprint Unlock',
                    style: AppTextStyles.bodyMedium()),
                Text('Use biometrics to open ARTH faster',
                    style: AppTextStyles.micro(
                        color: AppColors.textSecondary)),
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

// ─── GOOGLE SIGN-IN BUTTON ────────────────────────────────────────────────────
class _GoogleSignInButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool loading;
  const _GoogleSignInButton({required this.onTap, required this.loading});

  @override
  Widget build(BuildContext context) {
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
        onPressed: loading ? null : onTap,
        icon: loading
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.gold))
            : Image.asset(
                'assets/images/google_logo.png',
                width: 20,
                height: 20,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.g_mobiledata_rounded,
                  size: 24,
                  color: AppColors.textPrimary,
                ),
              ),
        label: Text(loading ? 'Signing in…' : 'Continue with Google'),
      ),
    );
  }
}
