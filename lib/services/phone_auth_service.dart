import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Handles Firebase Phone Auth — send OTP + verify OTP.
///
/// Flow:
///   1. Call [sendOtp] with +91XXXXXXXXXX
///   2. Firebase sends SMS; [onCodeSent] fires with a verificationId
///   3. User enters 6-digit code → call [verifyOtp]
///   4. On Android, SMS auto-read may trigger [onAutoVerified] — handle it
///      to skip the manual entry step.
class PhoneAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _verificationId;
  int? _forceResendingToken;

  // ── Send OTP ──────────────────────────────────────────────────────────────
  Future<void> sendOtp({
    required String phoneNumber, // must include country code, e.g. +919876543210
    required void Function(String verificationId) onCodeSent,
    required void Function(String errorMessage) onError,
    void Function()? onAutoVerified, // called when Android auto-reads SMS
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: _forceResendingToken,
        timeout: const Duration(seconds: 60),

        // ── Auto-verification (SMS auto-read on Android) ───────────────────
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (kDebugMode) debugPrint('[PhoneAuth] Auto-verified');
          try {
            await _signInOrLink(credential);
            onAutoVerified?.call();
          } catch (e) {
            onError('Auto-verification failed: $e');
          }
        },

        // ── SMS sent successfully ──────────────────────────────────────────
        codeSent: (String verificationId, int? resendToken) {
          if (kDebugMode) debugPrint('[PhoneAuth] OTP sent');
          _verificationId = verificationId;
          _forceResendingToken = resendToken;
          onCodeSent(verificationId);
        },

        // ── Failure ───────────────────────────────────────────────────────
        verificationFailed: (FirebaseAuthException e) {
          if (kDebugMode) debugPrint('[PhoneAuth] verificationFailed: ${e.code} — ${e.message}');
          final msg = _mapError(e.code);
          onError(msg);
        },

        // ── Auto-retrieval timed out ───────────────────────────────────────
        codeAutoRetrievalTimeout: (String verificationId) {
          if (kDebugMode) debugPrint('[PhoneAuth] Auto-retrieval timeout');
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PhoneAuth] sendOtp exception: $e');
      onError('Failed to send OTP. Check your number and try again.');
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────
  /// Returns the Firebase [User] on success.
  /// Throws [FirebaseAuthException] on invalid/expired code,
  /// [StateError] if [sendOtp] was never called,
  /// or [Exception] with a readable message for platform-layer failures.
  Future<User?> verifyOtp(String smsCode) async {
    if (_verificationId == null) {
      throw StateError('Session expired. Please go back and request a new OTP.');
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: smsCode.trim(),
    );

    try {
      final userCred = await _signInOrLink(credential);
      return userCred.user;
    } on PlatformException catch (e) {
      throw Exception(_platformErrorMessage(e));
    }
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────
  Future<void> resendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String errorMessage) onError,
  }) =>
      sendOtp(
        phoneNumber: phoneNumber,
        onCodeSent: onCodeSent,
        onError: onError,
      );

  // ── Internal ──────────────────────────────────────────────────────────────
  Future<UserCredential> _signInOrLink(AuthCredential credential) async {
    final current = _auth.currentUser;
    // Link anonymous account → phone (preserves Firestore data / UID)
    if (current != null && current.isAnonymous) {
      try {
        return await current.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        // Only fall back to direct sign-in when the phone is already linked elsewhere
        const fallbackCodes = {
          'credential-already-in-use',
          'provider-already-linked',
          'account-exists-with-different-credential',
        };
        if (fallbackCodes.contains(e.code)) {
          if (kDebugMode) debugPrint('[PhoneAuth] link fallback (${e.code}), signing in directly');
          return await _auth.signInWithCredential(credential);
        }
        rethrow; // e.g. invalid-verification-code, session-expired → propagate
      }
    }
    return await _auth.signInWithCredential(credential);
  }

  /// Converts a PlatformException (native layer error) into a readable message.
  String _platformErrorMessage(PlatformException e) {
    if (kDebugMode) debugPrint('[PhoneAuth] PlatformException: ${e.code} — ${e.message}');
    final code = e.code.toLowerCase();
    if (code.contains('network')) return 'No internet connection. Please check your network.';
    if (code.contains('quota')) return 'SMS quota exceeded. Please try again later.';
    if (code.contains('app-not-authorized') || code.contains('not_authorized')) {
      return 'App not authorized for Phone Auth. Check SHA-1 in Firebase Console.';
    }
    if (code.contains('too-many-requests') || code.contains('too_many')) {
      return 'Too many attempts. Please wait and try again.';
    }
    return 'Verification error (${e.code}). Please try again.';
  }

  String _mapError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'Invalid phone number. Use a 10-digit Indian mobile number.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      case 'invalid-verification-code':
        return 'Incorrect OTP. Please check and try again.';
      case 'session-expired':
        return 'OTP expired. Please request a new one.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      case 'app-not-authorized':
        return 'App not authorized. Contact support.';
      default:
        return 'Verification failed ($code). Please try again.';
    }
  }

  void reset() {
    _verificationId = null;
    _forceResendingToken = null;
  }
}
