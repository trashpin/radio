import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';

/// A reusable error display with an optional retry button.
///
/// Paired with [AppException], this gives the whole app one consistent way to
/// present failures: an icon, the friendly message, and (optionally) a retry.
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
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 52, color: theme.colorScheme.error),
            const Gap.v(AppSpacing.lg),
            Text(
              exception.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const Gap.v(AppSpacing.xl),
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
