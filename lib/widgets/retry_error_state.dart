import 'package:flutter/material.dart';

import 'premium_ui.dart';

/// The failed-to-load state, for any screen whose data came back an error.
///
/// Delegates to [ArthStatePanel] rather than drawing its own panel. Errors were
/// the one state that looked like a different app — a bare centred line with an
/// outlined button, while every empty and locked state used the panel. Same
/// surface, same spacing, same button weight now.
class RetryErrorState extends StatelessWidget {
  /// What failed, phrased as a heading: "Could not load your Tax Dossier".
  final String message;
  final VoidCallback onRetry;

  const RetryErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ArthStatePanel(
      icon: Icons.cloud_off_rounded,
      title: message,
      message: 'Nothing was lost. Try again in a moment.',
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }
}
