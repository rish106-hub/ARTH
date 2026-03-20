import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_account.dart';

/// Handles Google Sign-In, gated behind a Remote Config feature flag.
///
/// To enable Google Sign-In in production:
///   Firebase Console → Remote Config → set `google_sign_in_enabled` = true
///
/// SHA-1 fingerprint must be added to Firebase project Android app settings.
class GoogleAuthService {
  static const _flagKey = 'google_sign_in_enabled';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // ── Feature flag ─────────────────────────────────────────────────────────
  /// Returns true only when Remote Config has explicitly enabled Google Sign-In.
  /// Defaults to false so the button is always disabled until you flip the flag.
  Future<bool> isEnabled() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.fetchAndActivate();
      return rc.getBool(_flagKey);
    } catch (_) {
      return false;
    }
  }

  // ── Sign in with Google ───────────────────────────────────────────────────
  /// Returns a [UserAccount] populated with Google profile info + Firebase UID,
  /// or null on failure / user cancellation.
  Future<UserAccount?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // user cancelled

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final fbUser = userCredential.user;
      if (fbUser == null) return null;

      return UserAccount(
        name: fbUser.displayName ?? googleUser.displayName ?? 'ARTH User',
        phone: '', // Phone not provided by Google — user adds it later
        incomeRange: '',
        biometricsEnabled: false,
        createdAt: DateTime.now(),
        uid: fbUser.uid,
        email: fbUser.email,
        authMethod: AuthMethod.google,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[GoogleAuth] signInWithGoogle failed: $e');
      return null;
    }
  }

  // ── Link anonymous → Google ───────────────────────────────────────────────
  /// Links an existing anonymous Firebase account to Google (preserves UID
  /// and all Firestore data already synced under the anonymous account).
  Future<UserAccount?> linkAnonymousToGoogle(UserAccount current) async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final linkedCredential =
          await _auth.currentUser?.linkWithCredential(credential);
      final fbUser = linkedCredential?.user ?? _auth.currentUser;
      if (fbUser == null) return null;

      return current.copyWith(
        email: fbUser.email,
        authMethod: AuthMethod.google,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[GoogleAuth] linkAnonymousToGoogle failed: $e');
      return null;
    }
  }

  Future<void> signOut() => _googleSignIn.signOut();
}
