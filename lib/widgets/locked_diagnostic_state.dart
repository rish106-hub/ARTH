import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'premium_ui.dart';

class LockedDiagnosticState extends StatelessWidget {
  final String title;
  final String message;

  const LockedDiagnosticState({
    super.key,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return ArthStatePanel(
      icon: Icons.lock_clock_outlined,
      title: title,
      message: message,
      actionLabel: 'Start diagnostic',
      onAction: () => context.go('/questions'),
    );
  }
}

bool isIncompleteTaxProfileError(Object error) {
  return error.toString().contains('tax profile incomplete');
}
