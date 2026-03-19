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

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _nameCtrl = TextEditingController();
  final _panCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _biometricsEnabled = false;
  bool _biometricsAvailable = false;
  bool _loading = false;

  static final _panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final available = await ref.read(authProvider.notifier).hasBiometrics();
    if (mounted) setState(() => _biometricsAvailable = available);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _panCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Full name is required';
    if (v.trim().length < 2) return 'Enter a valid name';
    return null;
  }

  String? _validatePan(String? v) {
    if (v == null || v.isEmpty) return 'PAN Card is required';
    if (!_panRegex.hasMatch(v.toUpperCase())) {
      return 'Enter a valid PAN (e.g. AAAAA9999A)';
    }
    return null;
  }

  Future<void> _createAccount() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);

    final rawPan = _panCtrl.text.trim().toUpperCase();
    final account = UserAccount(
      name: _nameCtrl.text.trim(),
      panCard: UserAccount.maskPan(rawPan),
      incomeRange: '',
      biometricsEnabled: _biometricsEnabled,
      createdAt: DateTime.now(),
    );

    await ref.read(authProvider.notifier).saveAccount(account);

    if (mounted) {
      setState(() => _loading = false);
      context.go('/welcome');
    }
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

                // Logo + wordmark
                _AuthHeader()
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .slideY(begin: -0.2),

                SizedBox(height: size.height * 0.05),

                // Main glass card
                GlassCard(
                  blur: 16,
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create your account',
                          style: AppTextStyles.h2(),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Secured and synced to your private ARTH account.',
                          style: AppTextStyles.caption(
                              color: AppColors.textSecondary),
                        ),

                        const SizedBox(height: 28),

                        // Full Name field
                        _GlassInputField(
                          controller: _nameCtrl,
                          label: 'Full Name',
                          hint: 'As on your PAN card',
                          validator: _validateName,
                          keyboardType: TextInputType.name,
                          textCapitalization: TextCapitalization.words,
                        ).animate(delay: 200.ms).fadeIn(duration: 400.ms),

                        const SizedBox(height: 16),

                        // PAN field
                        _GlassInputField(
                          controller: _panCtrl,
                          label: 'PAN Card',
                          hint: 'AAAAA9999A',
                          validator: _validatePan,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            UpperCaseTextFormatter(),
                            LengthLimitingTextInputFormatter(10),
                          ],
                        ).animate(delay: 300.ms).fadeIn(duration: 400.ms),

                        const SizedBox(height: 20),

                        // Biometrics toggle
                        if (_biometricsAvailable)
                          _BiometricsToggle(
                            value: _biometricsEnabled,
                            onChanged: (v) =>
                                setState(() => _biometricsEnabled = v),
                          ).animate(delay: 400.ms).fadeIn(duration: 400.ms),

                        const SizedBox(height: 28),

                        // Create Account button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: AppButtons.primaryGold,
                            onPressed: _loading ? null : _createAccount,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Text('Create Account'),
                          ),
                        ).animate(delay: 500.ms).fadeIn(duration: 400.ms),

                        const SizedBox(height: 16),

                        // Google sign-in (disabled, coming soon)
                        _GoogleSignInButton()
                            .animate(delay: 600.ms)
                            .fadeIn(duration: 400.ms),
                      ],
                    ),
                  ),
                ).animate(delay: 100.ms).fadeIn(duration: 600.ms).slideY(begin: 0.1),

                SizedBox(height: size.height * 0.04),

                // Already have account
                Center(
                  child: TextButton(
                    onPressed: () {
                      // Future use — non-functional
                    },
                    child: Text(
                      'Already have an account? Sign in',
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

  const _GlassInputField({
    required this.controller,
    required this.label,
    required this.hint,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption(color: AppColors.textSecondary),
        ),
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
            filled: true,
            fillColor: Colors.white.withOpacity(0.04),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withOpacity(0.1)),
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
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
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
                Text(
                  'Enable Face / Fingerprint Unlock',
                  style: AppTextStyles.bodyMedium(),
                ),
                Text(
                  'Use biometrics to open ARTH faster',
                  style: AppTextStyles.micro(color: AppColors.textSecondary),
                ),
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

// ─── GOOGLE SIGN-IN (FEATURE-FLAGGED) ────────────────────────────────────────
/// Reads the `google_sign_in_enabled` Remote Config flag.
/// When true: active button wired to GoogleAuthService.
/// When false: greyed-out "Coming Soon" badge (default until you flip the flag).
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
    final isEnabled = ref.watch(googleSignInEnabledProvider).valueOrNull ?? false;

    if (isEnabled) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

    // Feature flag off — show disabled button with Coming Soon badge
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Coming Soon',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── UPPERCASE TEXT FORMATTER ─────────────────────────────────────────────────
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
