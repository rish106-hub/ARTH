import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/paycheck.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/paycheck_provider.dart';
import '../engine/recovery_engine.dart';
import '../models/recovery_models.dart';
import '../services/recovery_storage_service.dart';

final recoveryStorageProvider = Provider<RecoveryStorageService>(
  (_) => const RecoveryStorageService(),
);

final employerDatasetProvider = FutureProvider<EmployerDataset>((_) async {
  final raw = await rootBundle.loadString('assets/employer_playbooks.json');
  return EmployerDataset.fromJson(
    jsonDecode(raw) as Map<String, dynamic>,
  );
});

class RecoveryNotifier extends AsyncNotifier<RecoveryState> {
  late String _uid;
  late RecoveryStorageService _storage;

  @override
  Future<RecoveryState> build() async {
    _uid = ref.watch(authProvider)?.uid ?? 'guest';
    _storage = ref.read(recoveryStorageProvider);
    final paycheck = ref.watch(paycheckProvider);
    final dataset = await ref.watch(employerDatasetProvider.future);
    final saved = await _storage.load(_uid);
    final derived = RecoveryEngine.derive(
      saved: saved,
      paycheck: paycheck,
      dataset: dataset,
      now: DateTime.now(),
    );
    if (_changed(saved, derived)) {
      await _storage.save(_uid, derived);
    }
    return derived;
  }

  Future<void> updateClaim(
    String claimId, {
    ClaimCaseStatus? status,
    String? note,
    List<String>? selectedEvidenceIds,
  }) async {
    final current = state.value;
    if (current == null) return;
    final now = DateTime.now();
    final claims = [
      for (final claim in current.claimCases)
        if (claim.id == claimId)
          claim.copyWith(
            status: status,
            note: note,
            selectedEvidenceIds: selectedEvidenceIds,
            updatedAt: now,
          )
        else
          claim,
    ];
    final dataset = await ref.read(employerDatasetProvider.future);
    final next = RecoveryEngine.derive(
      saved: current.copyWith(claimCases: claims),
      paycheck: ref.read(paycheckProvider),
      dataset: dataset,
      now: now,
    );
    await _save(next);
  }

  Future<void> setChecklistItem(
    String monthKey, {
    bool? payslipChecked,
    bool? claimItemsReviewed,
  }) async {
    final current = state.value;
    if (current == null) return;
    final now = DateTime.now();
    final checklists = [
      for (final checklist in current.checklists)
        if (checklist.monthKey == monthKey)
          _completeChecklist(
            checklist.copyWith(
              payslipChecked: payslipChecked,
              claimItemsReviewed: claimItemsReviewed,
            ),
            now,
          )
        else
          checklist,
    ];
    await _save(current.copyWith(checklists: checklists));
  }

  Future<void> updateBenefit(
    String benefitId, {
    required int annualCap,
    required int resetMonth,
    required DateTime deadline,
  }) async {
    final current = state.value;
    if (current == null) return;
    final benefits = [
      for (final benefit in current.benefits)
        if (benefit.id == benefitId)
          benefit.copyWith(
            annualCap: annualCap,
            resetMonth: resetMonth,
            deadline: deadline,
            source: 'Added by you from your employer policy',
          )
        else
          benefit,
    ];
    await _save(current.copyWith(benefits: benefits));
  }

  Future<void> _save(RecoveryState next) async {
    state = AsyncData(next);
    await _storage.save(_uid, next);
  }

  PaydayChecklist _completeChecklist(
    PaydayChecklist checklist,
    DateTime now,
  ) {
    if (checklist.complete && checklist.completedAt == null) {
      return checklist.copyWith(completedAt: now);
    }
    return checklist;
  }

  bool _changed(RecoveryState left, RecoveryState right) =>
      jsonEncode(left.toJson()) != jsonEncode(right.toJson());
}

final recoveryProvider = AsyncNotifierProvider<RecoveryNotifier, RecoveryState>(
  RecoveryNotifier.new,
);

final recoveryClaimProvider = Provider.family<ClaimCase?, String>((ref, id) {
  final state = ref.watch(recoveryProvider).value;
  if (state == null) return null;
  for (final claim in state.claimCases) {
    if (claim.id == id || claim.paycheckItemId == id) return claim;
  }
  return null;
});

PaycheckItem? paycheckItemForClaim(PaycheckState paycheck, ClaimCase claim) {
  for (final item in paycheck.items) {
    if (item.id == claim.paycheckItemId) return item;
  }
  return null;
}
