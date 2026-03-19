import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_account.dart';
import '../models/user_profile.dart';

/// Syncs user data to Firebase Firestore (Spark free tier).
///
/// Schema:
///   users/{uid}                           — account doc
///   users/{uid}/tax_profiles/{fy}         — annual tax profile
///   users/{uid}/tax_results/{fy}          — computed gap results
///   users/{uid}/done_gaps/{gapId}         — marked-done gaps
///
/// Firebase is India-available and the Spark plan is free with:
///   • 50,000 reads/day  • 20,000 writes/day  • 1GB storage
class CloudSyncService {
  static const String _currentFY = '2025-26';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Anonymous sign-in (for manual accounts) ──────────────────────────────
  /// Signs in anonymously to get a stable Firebase UID. Safe to call multiple
  /// times — returns the existing anonymous user if already signed in.
  Future<String?> ensureAnonymousUid() async {
    try {
      User? user = _auth.currentUser;
      user ??= (await _auth.signInAnonymously()).user;
      return user?.uid;
    } catch (e) {
      debugPrint('[CloudSync] Anonymous sign-in failed: $e');
      return null;
    }
  }

  // ── User account doc ──────────────────────────────────────────────────────
  Future<void> syncAccount(UserAccount account) async {
    final uid = account.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set({
        'name': account.name,
        'pan_masked': account.panCard,
        'email': account.email,
        'auth_method': account.authMethod.name,
        'biometrics_enabled': account.biometricsEnabled,
        'created_at': FieldValue.serverTimestamp(),
        'last_seen': FieldValue.serverTimestamp(),
        'app_version': '1.0.0',
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[CloudSync] syncAccount failed: $e');
    }
  }

  // ── Tax profile (12 onboarding answers) ──────────────────────────────────
  Future<void> syncProfile(String uid, UserProfile p) async {
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('tax_profiles')
          .doc(_currentFY)
          .set({
        'annual_ctc': p.annualCTC,
        'age_group': p.ageGroup.name,
        'employment_type': p.employmentType.name,
        'city': p.city,
        'is_metro_city': p.isMetroCity,
        'pays_rent': p.paysRent,
        'monthly_rent': p.monthlyRent,
        'has_hra': p.hasHRA,
        'invested_80c': p.invested80C,
        'nps_extra': p.npsExtraContribution,
        'has_health_ins_self': p.hasHealthInsuranceSelf,
        'has_health_ins_parents': p.hasHealthInsuranceParents,
        'parents_above_60': p.parentsAbove60,
        'has_home_loan': p.hasHomeLoanSelfOccupied,
        'home_loan_interest': p.homeLoanInterest,
        'has_education_loan': p.hasEducationLoan,
        'education_loan_interest': p.educationLoanInterest,
        'education_loan_year': p.educationLoanRepaymentYear,
        'has_donations': p.hasDonations,
        'donation_amount': p.donationAmount,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[CloudSync] syncProfile failed: $e');
    }
  }

  // ── Mark gap as done ─────────────────────────────────────────────────────
  Future<void> markGapDone(String uid, String gapId) async {
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('done_gaps')
          .doc('${_currentFY}_$gapId')
          .set({
        'gap_id': gapId,
        'fy': _currentFY,
        'done_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[CloudSync] markGapDone failed: $e');
    }
  }

  // ── Load done gaps (for cross-device sync) ────────────────────────────────
  Future<Set<String>> loadDoneGaps(String uid) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('done_gaps')
          .where('fy', isEqualTo: _currentFY)
          .get();
      return snap.docs.map((d) => d['gap_id'] as String).toSet();
    } catch (e) {
      debugPrint('[CloudSync] loadDoneGaps failed: $e');
      return {};
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('[CloudSync] signOut failed: $e');
    }
  }
}
