import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/account_profile_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/tax_readiness_provider.dart';
import '../providers/tax_result_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/sync_queue_service.dart';

Future<void> signOutDeviceAndRouteToAuth(
  BuildContext context,
  WidgetRef ref,
) async {
  final userProfile = ref.read(userProfileProvider.notifier);
  final documentChecklist = ref.read(documentChecklistProvider.notifier);
  final accountProfile = ref.read(accountProfileProvider.notifier);

  // These providers use the current uid for their storage keys, so clear them
  // before auth is removed.
  await userProfile.clearLocalOnly();
  await documentChecklist.clear();
  await accountProfile.clearLocalOnly();
  await const SyncQueueService().clear();

  ref.invalidate(gapStateProvider);
  ref.invalidate(taxResultProvider);
  ref.invalidate(completedTaxProfileProvider);
  ref.invalidate(documentReadinessPercentProvider);

  await ref.read(authProvider.notifier).signOut();

  ref.invalidate(accountProfileProvider);
  ref.invalidate(userProfileProvider);
  ref.invalidate(documentChecklistProvider);
  ref.invalidate(authProvider);

  if (context.mounted) {
    context.go('/auth');
  }
}

void scheduleDeviceSignOut(
  BuildContext context,
  WidgetRef ref,
) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    signOutDeviceAndRouteToAuth(context, ref);
  });
}
