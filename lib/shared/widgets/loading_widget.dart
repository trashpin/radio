import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// A reusable, centered loading indicator.
///
/// Every screen that waits on the backend should show the *same* loading UI, so
/// we define it once here rather than sprinkling `CircularProgressIndicator`s
/// throughout the app. An optional [message] can explain what is loading.
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
            const SizedBox(height: AppConstants.spacingMd),
            Text(message!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
