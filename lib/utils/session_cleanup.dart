import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/account_profile_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/money_goal_provider.dart';
import '../providers/other_income_provider.dart';
import '../providers/paycheck_override_provider.dart';
import '../providers/paycheck_provider.dart';
import '../providers/spend_map_adjustments_provider.dart';
import '../providers/spend_map_provider.dart';
import '../providers/tax_document_provider.dart';
import '../providers/tax_readiness_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/user_profile_provider.dart';
import '../models/user_account.dart';
import '../features/monthly_close/providers/monthly_close_provider.dart';
import '../features/recovery/providers/recovery_provider.dart';
import '../features/spend_completeness/providers/spend_completeness_provider.dart';
import '../services/durable_user_state_service.dart';

Future<void> clearDeviceSession(WidgetRef ref) async {
  // Account-scoped caches stay encrypted on-device. Deleting them during
  // sign-in or sign-out made an expired session look like permanent data loss.
  await ref.read(authProvider.notifier).signOut();
  _invalidateUserScopedProviders(ref);
}

void _invalidateUserScopedProviders(WidgetRef ref) {
  ref.invalidate(gapStateProvider);
  ref.invalidate(taxResultProvider);
  ref.invalidate(completedTaxProfileProvider);
  ref.invalidate(documentReadinessPercentProvider);
  ref.invalidate(taxDocumentProvider);
  ref.invalidate(accountProfileProvider);
  ref.invalidate(userProfileProvider);
  ref.invalidate(documentChecklistProvider);
  ref.invalidate(spendMapProvider);
  ref.invalidate(spendMapAdjustmentsProvider);
  ref.invalidate(otherIncomeProvider);
  ref.invalidate(paycheckOverrideProvider);
  ref.invalidate(paycheckProvider);
  ref.invalidate(moneyGoalProvider);
  ref.invalidate(spendCompletenessProvider);
  ref.invalidate(recoveryProvider);
  ref.invalidate(monthlyCloseProvider);
}

Future<void> prepareForAuthentication(WidgetRef ref) async {
  await clearDeviceSession(ref);
}

Future<bool> hydrateAuthenticatedAccount(
  WidgetRef ref,
  UserAccount account,
) async {
  final uid = account.uid;
  if (uid != null && uid.isNotEmpty) {
    await durableUserStateService.restore(uid);
  }
  ref.read(userProfileProvider.notifier).resetForAccount(account);
  ref.invalidate(accountProfileProvider);
  ref.invalidate(taxDocumentProvider);
  ref.invalidate(documentChecklistProvider);
  ref.invalidate(gapStateProvider);
  ref.invalidate(taxResultProvider);
  ref.invalidate(completedTaxProfileProvider);
  ref.invalidate(spendMapProvider);
  ref.invalidate(spendMapAdjustmentsProvider);
  ref.invalidate(otherIncomeProvider);
  ref.invalidate(paycheckOverrideProvider);
  ref.invalidate(paycheckProvider);
  ref.invalidate(moneyGoalProvider);
  ref.invalidate(spendCompletenessProvider);
  ref.invalidate(recoveryProvider);
  ref.invalidate(monthlyCloseProvider);
  return ref.read(userProfileProvider.notifier).load();
}

Future<void> signOutDeviceAndRouteToAuth(
  BuildContext context,
  WidgetRef ref,
) async {
  await clearDeviceSession(ref);
  ref.invalidate(authProvider);

  if (context.mounted) {
    context.go('/auth');
  }
}

/// Test-only entry point that accepts a [ProviderContainer] instead of a
/// [WidgetRef].
Future<void> clearDeviceSessionForContainer(ProviderContainer container) async {
  await container.read(authProvider.notifier).signOut();

  container.invalidate(gapStateProvider);
  container.invalidate(taxResultProvider);
  container.invalidate(completedTaxProfileProvider);
  container.invalidate(documentReadinessPercentProvider);
  container.invalidate(taxDocumentProvider);
  container.invalidate(accountProfileProvider);
  container.invalidate(userProfileProvider);
  container.invalidate(documentChecklistProvider);
  container.invalidate(spendMapProvider);
  container.invalidate(spendMapAdjustmentsProvider);
  container.invalidate(otherIncomeProvider);
  container.invalidate(paycheckOverrideProvider);
  container.invalidate(paycheckProvider);
  container.invalidate(moneyGoalProvider);
  container.invalidate(spendCompletenessProvider);
  container.invalidate(recoveryProvider);
  container.invalidate(monthlyCloseProvider);
}
