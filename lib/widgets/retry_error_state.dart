import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';

class RetryErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const RetryErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: PaycheckColors.gold,
                size: 32,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                style: PaycheckType.body(color: PaycheckColors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: PaycheckColors.gold,
                    side: const BorderSide(color: PaycheckColors.gold),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
