import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../providers/auth_provider.dart';
import '../services/server_api_service.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../utils/session_cleanup.dart';
import '../widgets/premium_ui.dart';
import '../widgets/arth_brand_mark.dart';
import '../widgets/auth_motion_scene.dart';

class AuthScreen extends ConsumerStatefulWidget {
  final bool initialSignUp;

  const AuthScreen({super.key, this.initialSignUp = true});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late bool _isSignUp;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _emailErrorMessage;
  String? _googleErrorMessage;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.initialSignUp;
  }

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
      _emailErrorMessage = null;
    });

    try {
      final email = _emailCtrl.text.trim().toLowerCase();
      final password = _passwordCtrl.text;

      await prepareForAuthentication(ref);

      final account = _isSignUp
          ? await ref.read(authProvider.notifier).signUp(
                name: _nameCtrl.text.trim(),
                email: email,
                password: password,
              )
          : await ref
              .read(authProvider.notifier)
              .signIn(email: email, password: password);

      await hydrateAuthenticatedAccount(ref, account);
      if (!mounted) return;
      context.go(_isSignUp ? '/paycheck-setup' : '/paycheck');
    } on ServerApiException catch (e) {
      if (!mounted) return;
      setState(() => _emailErrorMessage = _friendlyServerError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _emailErrorMessage = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _loading = true;
      _googleErrorMessage = null;
    });
    try {
      await prepareForAuthentication(ref);
      final account = await ref.read(authProvider.notifier).signInWithGoogle();
      await hydrateAuthenticatedAccount(ref, account);
      if (!mounted) return;
      context.go('/paycheck');
    } on ServerApiException catch (error) {
      if (mounted) {
        setState(() => _googleErrorMessage = _friendlyServerError(error));
      }
    } on GoogleSignInException catch (error) {
      debugPrint(
        '[GoogleSignIn] ${error.code}: ${error.description ?? 'no description'}',
      );
      if (mounted) {
        setState(() => _googleErrorMessage = _googleSignInError(error));
      }
    } catch (error) {
      debugPrint('[GoogleSignIn] unexpected error: $error');
      if (mounted) {
        setState(() => _googleErrorMessage =
            'Google sign-in failed before reaching ARTH. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _googleSignInError(GoogleSignInException error) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled =>
        'Google did not complete sign-in. If you selected an account, this build may still need an updated OAuth client.',
      GoogleSignInExceptionCode.clientConfigurationError =>
        'Google sign-in is not configured for this Android build.',
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google Play Services could not complete sign-in on this device.',
      GoogleSignInExceptionCode.interrupted =>
        'Google sign-in was interrupted. Please try again.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'Google sign-in cannot open on this device right now.',
      _ => 'Google sign-in failed before reaching ARTH. Please try again.',
    };
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
    if (error.statusCode == 503 ||
        error.code == 'backend_temporarily_unavailable') {
      return 'ARTH is still connecting to its secure database. We retried once; please try again in a moment.';
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
    final headline = _isSignUp ? 'Know what reached you.' : 'Welcome back.';
    final subhead = _isSignUp
        ? 'Keep your offer letter, payslips, and confirmed pay in one private record.'
        : 'Sign in to continue reviewing your pay evidence.';

    return ArthScaffold(
      showAmbientGlow: false,
      padding: const EdgeInsets.symmetric(horizontal: 22),
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
                    const SizedBox(height: 20),
                    _AuthHero(isSignUp: _isSignUp),
                    const SizedBox(height: 28),
                    Text(
                      headline,
                      style: PaycheckType.h1().copyWith(
                        fontSize: 40,
                        height: 1.04,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subhead,
                      style: PaycheckType.body(
                          color: PaycheckColors.textSecondary),
                    ),
                    const SizedBox(height: 28),
                    Form(
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
                                _emailErrorMessage = null;
                                _googleErrorMessage = null;
                              });
                            },
                          ),
                          const SizedBox(height: 22),
                          _GoogleButton(
                            loading: _loading,
                            onPressed: _submitGoogle,
                          ),
                          const SizedBox(height: 10),
                          _AuthErrorText(message: _googleErrorMessage),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'or use email',
                                  style: PaycheckType.micro(),
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
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
                                color: PaycheckColors.textSecondary,
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
                          _AuthErrorText(message: _emailErrorMessage),
                          const SizedBox(height: 14),
                          _SubmitButton(
                            loading: _loading,
                            label: _isSignUp ? 'Sign up' : 'Sign in',
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'ARTH stores your answers so you can continue later.',
                      textAlign: TextAlign.center,
                      style: PaycheckType.micro(
                          color: PaycheckColors.textSecondary),
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
  final bool isSignUp;

  const _AuthHero({required this.isSignUp});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ArthBrandMark(size: 42),
        const SizedBox(height: 20),
        AuthMotionScene(isSignUp: isSignUp),
      ],
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
        color: PaycheckColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              label: 'Sign up',
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
          color: selected ? PaycheckColors.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: PaycheckType.bodyMedium(
            color: selected ? Colors.white : PaycheckColors.textSecondary,
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
      style: PaycheckType.bodyMedium(),
      cursorColor: PaycheckColors.gold,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
        labelStyle: PaycheckType.caption(color: PaycheckColors.textSecondary),
        hintStyle: PaycheckType.body(color: PaycheckColors.textMuted),
        filled: true,
        fillColor: PaycheckColors.bgCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: PaycheckColors.border),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: PaycheckColors.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: PaycheckColors.gold, width: 1.4),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: PaycheckColors.alert),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: PaycheckColors.alert, width: 1.4),
        ),
        errorStyle: PaycheckType.micro(color: PaycheckColors.alert),
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
                color: PaycheckColors.alert.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: PaycheckColors.alert.withValues(alpha: 0.24)),
              ),
              child: Text(
                message!,
                style: PaycheckType.caption(color: PaycheckColors.alert),
                textAlign: TextAlign.center,
              ),
            ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _GoogleButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: PaycheckColors.textPrimary,
          backgroundColor: PaycheckColors.surface,
          side: const BorderSide(color: PaycheckColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Image.asset(
          'assets/images/google_logo.png',
          width: 20,
          height: 20,
        ),
        label: Text('Continue with Google', style: PaycheckType.bodyMedium()),
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
          backgroundColor: PaycheckColors.gold,
          foregroundColor: Colors.white,
          disabledBackgroundColor: PaycheckColors.gold.withValues(alpha: 0.42),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: PaycheckColors.ink,
                ),
              )
            : Text(label, style: PaycheckType.button(color: Colors.white)),
      ),
    );
  }
}
