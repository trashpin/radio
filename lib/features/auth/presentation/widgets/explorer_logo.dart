import 'package:flutter/material.dart';

/// The ExplorerOS wordmark + emblem, used across the auth screens.
class ExplorerLogo extends StatelessWidget {
  const ExplorerLogo({super.key, this.size = 72, this.showWordmark = true});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final green = theme.colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [green, green.withValues(alpha: 0.65)],
            ),
            borderRadius: BorderRadius.circular(size * 0.28),
            boxShadow: [
              BoxShadow(
                color: green.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(Icons.explore_rounded,
              color: Colors.white, size: size * 0.56),
        ),
        if (showWordmark) ...[
          SizedBox(height: size * 0.28),
          RichText(
            text: TextSpan(
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
              children: [
                TextSpan(
                    text: 'Explorer',
                    style: TextStyle(color: theme.colorScheme.onSurface)),
                TextSpan(text: 'OS', style: TextStyle(color: green)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
