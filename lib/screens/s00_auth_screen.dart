import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/server_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/premium_ui.dart';

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
      final hasProfile = await ref.read(userProfileProvider.notifier).load();
      if (!mounted) return;
      context.go(hasProfile ? '/gap-reveal' : '/welcome');
    } on ServerApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyServerError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyServerError(ServerApiException error) {
    final message = error.message.toLowerCase();
    if (error.statusCode == 404 &&
        (message.contains('application not found') ||
            message.contains('not found'))) {
      return 'ARTH server is not available right now. Please try again after the backend is restored.';
    }
    if (error.statusCode == 409) {
      return 'An account with this email already exists.';
    }
    if (error.statusCode == 401) return 'Incorrect email or password.';
    if (error.statusCode == 429) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    if (error.statusCode == 400 && _isSignUp) {
      return 'Use 12+ characters with uppercase, lowercase, and a number.';
    }
    if (error.statusCode == 413) {
      return 'That request was too large. Try again.';
    }
    if (error.statusCode >= 500) {
      return 'ARTH server had a problem. Please try again in a moment.';
    }
    return 'Authentication failed. Please try again.';
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
    if (raw.contains('413')) return 'That request was too large. Try again.';
    if (raw.contains('TimeoutException') ||
        raw.contains('Failed host lookup') ||
        raw.contains('Connection refused') ||
        raw.contains('Network is unreachable') ||
        raw.contains('SocketException')) {
      return 'Cannot reach ARTH. Check your connection and try again.';
    }
    return 'Authentication failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final headline =
        _isSignUp ? 'Enter your tax intelligence vault.' : 'Welcome back.';
    final subhead = _isSignUp
        ? 'Create a private ARTH account to sync your diagnostic and action plan.'
        : 'Sign in to restore your saved profile, progress, and results.';

    return ArthScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 28),
                    const _AuthHero()
                        .animate(target: reduceMotion ? 0 : 1)
                        .fadeIn(duration: 360.ms)
                        .slideY(begin: 0.08, end: 0),
                    const SizedBox(height: 24),
                    Text(headline, style: AppTextStyles.h1()),
                    const SizedBox(height: 8),
                    Text(
                      subhead,
                      style: AppTextStyles.body(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 18),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TrustBadge(
                          icon: Icons.badge_outlined,
                          label: 'No PAN required',
                        ),
                        TrustBadge(
                          icon: Icons.receipt_long_outlined,
                          label: 'No ITR upload',
                          color: AppColors.teal,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    PremiumGlassPanel(
                      elevated: true,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ModeSwitch(
                              isSignUp: _isSignUp,
                              onChanged: (value) {
                                if (_loading) return;
                                setState(() {
                                  _isSignUp = value;
                                  _errorMessage = null;
                                });
                              },
                            ),
                            const SizedBox(height: 18),
                            if (_isSignUp) ...[
                              _InputField(
                                controller: _nameCtrl,
                                label: 'Full name',
                                hint: 'Your name',
                                keyboardType: TextInputType.name,
                                textCapitalization: TextCapitalization.words,
                                validator: (v) {
                                  if (v == null || v.trim().length < 2) {
                                    return 'Enter at least 2 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                            ],
                            _InputField(
                              controller: _emailCtrl,
                              label: 'Email address',
                              hint: 'you@example.com',
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null ||
                                    !_emailRegex.hasMatch(v.trim())) {
                                  return 'Enter a valid email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            _InputField(
                              controller: _passwordCtrl,
                              label: 'Password',
                              hint: _isSignUp
                                  ? '12+ chars, Aa, 0-9'
                                  : 'Enter your password',
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
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
                            ),
                            const SizedBox(height: 16),
                            _AuthErrorText(message: _errorMessage),
                            const SizedBox(height: 14),
                            _SubmitButton(
                              loading: _loading,
                              label: _isSignUp
                                  ? 'Create secure account'
                                  : 'Sign in',
                              onPressed: _submit,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Passwords are hashed. Synced profile data can be deleted from Settings.',
                      textAlign: TextAlign.center,
                      style:
                          AppTextStyles.micro(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AuthHero extends StatelessWidget {
  const _AuthHero();

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      borderRadius: BorderRadius.circular(28),
      padding: const EdgeInsets.all(22),
      elevated: true,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
            ),
            child: const Center(
              child: Text(
                '₹',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: AppColors.gold,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ARTH', style: AppTextStyles.h3()),
                const SizedBox(height: 4),
                Text(
                  'Private tax gap intelligence for salaried India.',
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

class _ModeSwitch extends StatelessWidget {
  final bool isSignUp;
  final ValueChanged<bool> onChanged;

  const _ModeSwitch({required this.isSignUp, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: AppRadius.pill,
        border: Border.all(color: AppColors.glassStroke),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              label: 'Create',
              selected: isSignUp,
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _ModeButton(
              label: 'Sign in',
              selected: !isSignUp,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : Colors.transparent,
          borderRadius: AppRadius.pill,
        ),
        child: Text(
          label,
          style: AppTextStyles.bodyMedium(
            color: selected ? AppColors.ink : AppColors.textSecondary,
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
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      style: AppTextStyles.bodyMedium(),
      cursorColor: AppColors.gold,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
        labelStyle: AppTextStyles.caption(color: AppColors.textSecondary),
        hintStyle: AppTextStyles.body(color: AppColors.textMuted),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.22),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.alert),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.alert, width: 1.4),
        ),
        errorStyle: AppTextStyles.micro(color: AppColors.alert),
      ),
    );
  }
}

class _AuthErrorText extends StatelessWidget {
  final String? message;

  const _AuthErrorText({required this.message});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.fast,
      child: message == null
          ? const SizedBox(key: ValueKey('empty-error'), height: 0)
          : Container(
              key: const ValueKey('visible-error'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.alert.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.alert.withValues(alpha: 0.24)),
              ),
              child: Text(
                message!,
                style: AppTextStyles.caption(color: const Color(0xFFFF8A8A)),
                textAlign: TextAlign.center,
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
          foregroundColor: AppColors.ink,
          disabledBackgroundColor: AppColors.gold.withValues(alpha: 0.42),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.ink,
                ),
              )
            : Text(label, style: AppTextStyles.button(color: AppColors.ink)),
      ),
    );
  }
}
