import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/account_profile_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/paycheck_provider.dart';
import '../providers/tax_document_provider.dart';
import '../providers/tax_readiness_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/user_profile_provider.dart';
import '../models/user_account.dart';
import '../services/sync_queue_service.dart';

Future<void> clearDeviceSession(WidgetRef ref) async {
  final userProfile = ref.read(userProfileProvider.notifier);
  final documentChecklist = ref.read(documentChecklistProvider.notifier);
  final accountProfile = ref.read(accountProfileProvider.notifier);

  // Clear user-scoped caches while the outgoing account is still available.
  await userProfile.clearLocalOnly();
  await documentChecklist.clear();
  await accountProfile.clearLocalOnly();
  await const SyncQueueService().clear();
  ref.read(paycheckProvider.notifier).clearUserData();

  await ref.read(authProvider.notifier).signOut();

  ref.invalidate(gapStateProvider);
  ref.invalidate(taxResultProvider);
  ref.invalidate(completedTaxProfileProvider);
  ref.invalidate(documentReadinessPercentProvider);
  ref.invalidate(taxDocumentProvider);
  ref.invalidate(accountProfileProvider);
  ref.invalidate(userProfileProvider);
  ref.invalidate(documentChecklistProvider);
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
