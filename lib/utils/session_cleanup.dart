import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/account_profile_provider.dart';
import '../providers/auth_provider.dart';
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
import '../services/sync_queue_service.dart';

Future<void> clearDeviceSession(WidgetRef ref) async {
  final uid = ref.read(authProvider)?.uid;

  await ref.read(spendMapProvider.notifier).clearLocalData();
  await ref.read(spendMapAdjustmentsProvider.notifier).clearLocalData();
  await ref.read(otherIncomeProvider.notifier).clearLocalData();
  await ref.read(paycheckOverrideProvider.notifier).clearLocalData();
  await ref.read(userProfileProvider.notifier).clearLocalOnly();
  await ref.read(documentChecklistProvider.notifier).clear();
  await ref.read(accountProfileProvider.notifier).clearLocalOnly();
  if (uid != null && uid.isNotEmpty) {
    await const SyncQueueService().clear(uid);
  }
  ref.read(paycheckProvider.notifier).clearUserData();

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
}

Future<void> prepareForAuthentication(WidgetRef ref) async {
  await clearDeviceSession(ref);
}

Future<bool> hydrateAuthenticatedAccount(
  WidgetRef ref,
  UserAccount account,
) async {
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
  final uid = container.read(authProvider)?.uid;

  await container.read(spendMapProvider.notifier).clearLocalData();
  await container.read(spendMapAdjustmentsProvider.notifier).clearLocalData();
  await container.read(otherIncomeProvider.notifier).clearLocalData();
  await container.read(paycheckOverrideProvider.notifier).clearLocalData();
  await container.read(userProfileProvider.notifier).clearLocalOnly();
  await container.read(documentChecklistProvider.notifier).clear();
  await container.read(accountProfileProvider.notifier).clearLocalOnly();
  if (uid != null && uid.isNotEmpty) {
    await const SyncQueueService().clear(uid);
  }
  container.read(paycheckProvider.notifier).clearUserData();

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
}
