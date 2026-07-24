import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';

/// A reusable, centered loading indicator with an optional [message].
///
/// Every screen that waits on the backend shows this same loading UI, so we
/// define it once instead of scattering `CircularProgressIndicator`s around.
class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const Gap.v(AppSpacing.lg),
            Text(message!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
