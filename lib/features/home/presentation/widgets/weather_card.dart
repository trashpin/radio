import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/shared/components/app_card.dart';

/// The dashboard weather tile.
///
/// NOTE: This is a styled PLACEHOLDER. The values below are sample/illustrative
/// only — there is no weather service yet. When the weather feature is built,
/// this widget will accept a typed `Weather` model (temperature, condition,
/// location) instead of the hardcoded sample text. Kept visually complete so
/// the dashboard layout is final.
class WeatherCard extends StatelessWidget {
  const WeatherCard({
    super.key,
    this.temperature = '72°F',
    this.condition = 'Partly sunny',
    this.location = 'Ocala, Florida',
  });

  final String temperature;
  final String condition;
  final String location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          const Icon(Icons.wb_sunny_rounded,
              color: AppColors.weatherAmber, size: 40),
          const Gap.h(AppSpacing.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(temperature, style: theme.textTheme.headlineMedium),
              Text(condition, style: theme.textTheme.bodySmall),
            ],
          ),
          const Spacer(),
          Icon(Icons.location_on_outlined,
              size: 18, color: theme.colorScheme.primary),
          const Gap.h(AppSpacing.xs),
          Flexible(
            child: Text(
              location,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
