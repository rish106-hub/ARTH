import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/user_profile_provider.dart';
import '../theme/app_theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSignUp = true;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailCtrl.text.trim().toLowerCase();
      final password = _passwordCtrl.text;

      final account = _isSignUp
          ? await ref.read(authProvider.notifier).signUp(
                name: _nameCtrl.text.trim(),
                email: email,
                password: password,
              )
          : await ref
              .read(authProvider.notifier)
              .signIn(email: email, password: password);

      ref.read(userProfileProvider.notifier).applyAccountIdentity(account);
      // Server is source of truth — load fetches the user's profile from the
      // server first. Returns true if a saved profile exists (onboarding done).
      final hasProfile = await ref.read(userProfileProvider.notifier).load();
      if (!mounted) return;
      context.go(hasProfile ? '/gap-reveal' : '/welcome');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('409')) {
      return 'An account with this email already exists.';
    }
    if (raw.contains('401')) return 'Incorrect email or password.';
    if (raw.contains('429')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    if (raw.contains('400') && _isSignUp) {
      return 'Use 12+ characters with uppercase, lowercase, and a number.';
    }
    if (raw.contains('413')) {
      return 'That request was too large. Please try again.';
    }
    if (raw.contains('TimeoutException') ||
        raw.contains('Failed host lookup') ||
        raw.contains('Connection refused') ||
        raw.contains('Network is unreachable') ||
        raw.contains('SocketException')) {
      return 'Cannot reach the server. Check your connection and try again.';
    }
    return 'Authentication failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final headline = _isSignUp ? 'Create your account.' : 'Sign in.';
    final subhead = _isSignUp
        ? 'Use email and password to securely save your tax profile.'
        : 'Sign in to load your saved tax profile and calculations.';

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 56),
                Center(
                  child: Text(
                    '₹',
                    style: TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w900,
                      color: AppColors.gold,
                      height: 1,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .scale(begin: const Offset(0.7, 0.7)),
                ),
                const SizedBox(height: 28),
                Text(
                  headline,
                  style: AppTextStyles.h1(color: AppColors.textPrimary),
                )
                    .animate(delay: 200.ms)
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: 0.2, end: 0),
                const SizedBox(height: 8),
                Text(
                  subhead,
                  style: AppTextStyles.body(color: AppColors.textSecondary),
                ).animate(delay: 300.ms).fadeIn(duration: 500.ms),
                const SizedBox(height: 40),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isSignUp) ...[
                        _InputField(
                          controller: _nameCtrl,
                          label: 'Full name',
                          hint: 'Saswataduity Bhuin',
                          keyboardType: TextInputType.name,
                          textCapitalization: TextCapitalization.words,
                          validator: (v) {
                            if (!_isSignUp) return null;
                            if (v == null || v.trim().length < 2) {
                              return 'Enter at least 2 characters';
                            }
                            return null;
                          },
                        ).animate(delay: 360.ms).fadeIn(duration: 350.ms),
                        const SizedBox(height: 16),
                      ],
                      _InputField(
                        controller: _emailCtrl,
                        label: 'Email address',
                        hint: 'you@example.com',
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || !_emailRegex.hasMatch(v.trim())) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                      ).animate(delay: 420.ms).fadeIn(duration: 350.ms),
                      const SizedBox(height: 16),
                      _InputField(
                        controller: _passwordCtrl,
                        label: 'Password',
                        hint: _isSignUp
                            ? '12+ chars, Aa, 0-9'
                            : 'Enter your password',
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        validator: (v) {
                          final value = v ?? '';
                          if (!_isSignUp && value.length < 8) {
                            return 'Password must be at least 8 characters';
                          }
                          if (_isSignUp &&
                              !RegExp(
                                r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{12,}$',
                              ).hasMatch(value)) {
                            return 'Use 12+ chars with Aa and 0-9';
                          }
                          return null;
                        },
                      ).animate(delay: 480.ms).fadeIn(duration: 350.ms),
                      const SizedBox(height: 28),
                      _AuthErrorText(message: _errorMessage),
                      const SizedBox(height: 16),
                      _SubmitButton(
                        loading: _loading,
                        label: _isSignUp ? 'Sign up' : 'Sign in',
                        onPressed: _submit,
                      ).animate(delay: 540.ms).fadeIn(duration: 350.ms),
                      const SizedBox(height: 18),
                      if (_isSignUp)
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  setState(() {
                                    _isSignUp = false;
                                    _errorMessage = null;
                                  });
                                },
                          child: Text(
                            'Returning user? Click here to sign in',
                            style: AppTextStyles.bodyMedium(
                              color: AppColors.gold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  setState(() {
                                    _isSignUp = true;
                                    _errorMessage = null;
                                  });
                                },
                          child: Text(
                            'New here? Create an account',
                            style: AppTextStyles.bodyMedium(
                              color: AppColors.gold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Server-backed account. Passwords are never stored in plaintext.',
                        style: AppTextStyles.caption(
                          color: AppColors.textSecondary.withValues(alpha: 0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                    ],
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

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.validator,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?) validator;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF9E9E9E),
            fontSize: 12,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          obscureText: obscureText,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          cursorColor: AppColors.gold,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffixIcon,
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 16,
            ),
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF5252)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFFF5252),
                width: 1.5,
              ),
            ),
            errorStyle: const TextStyle(color: Color(0xFFFF5252), fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _AuthErrorText extends StatelessWidget {
  final String? message;

  const _AuthErrorText({required this.message});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: message == null
          ? const SizedBox(key: ValueKey('empty-error'), height: 0)
          : ConstrainedBox(
              key: const ValueKey('visible-error'),
              constraints: const BoxConstraints(minHeight: 36),
              child: Center(
                child: Text(
                  message!,
                  style: const TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final bool loading;
  final String label;
  final VoidCallback onPressed;

  const _SubmitButton({
    required this.loading,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.gold.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.black,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}
