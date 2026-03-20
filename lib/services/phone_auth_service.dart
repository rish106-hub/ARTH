import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
  /// Returns the Firebase [User] on success, throws [FirebaseAuthException] on
  /// invalid / expired code, or [StateError] if sendOtp was never called.
  Future<User?> verifyOtp(String smsCode) async {
    if (_verificationId == null) {
      throw StateError('No verificationId — call sendOtp first.');
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: smsCode.trim(),
    );

    final userCred = await _signInOrLink(credential);
    return userCred.user;
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
        // If linking fails (e.g. phone already used), fall back to direct sign-in
        if (kDebugMode) debugPrint('[PhoneAuth] link failed (${e.code}), signing in directly');
        return await _auth.signInWithCredential(credential);
      }
    }
    return await _auth.signInWithCredential(credential);
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
