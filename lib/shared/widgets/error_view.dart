import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/app_exception.dart';

/// A reusable error display with an optional retry button.
///
/// Paired with [AppException], this gives the whole app one consistent way to
/// present failures: an icon, the friendly message, and (optionally) a way to
/// try again. Screens pass the caught [AppException] plus an [onRetry] callback.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.exception, this.onRetry});

  final AppException exception;
  final VoidCallback? onRetry;

  IconData get _icon {
    switch (exception.type) {
      case AppExceptionType.network:
        return Icons.wifi_off_rounded;
      case AppExceptionType.auth:
        return Icons.lock_outline_rounded;
      case AppExceptionType.notFound:
        return Icons.search_off_rounded;
      case AppExceptionType.server:
      case AppExceptionType.unknown:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: AppConstants.spacingMd),
            Text(
              exception.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppConstants.spacingLg),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
