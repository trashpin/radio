import 'package:flutter/material.dart';

/// A beautiful category-aware placeholder shown wherever a species has no photo
/// yet — so the app NEVER shows a blank/broken image box (Phase 6).
class WildlifePlaceholder extends StatelessWidget {
  const WildlifePlaceholder({
    super.key,
    this.category,
    this.label,
    this.compact = false,
  });

  final String? category;
  final String? label;
  final bool compact;

  static IconData iconFor(String? category) {
    switch ((category ?? '').toLowerCase()) {
      case 'birds':
        return Icons.flutter_dash_rounded;
      case 'plants':
      case 'wildflowers':
        return Icons.local_florist_rounded;
      case 'trees':
        return Icons.park_rounded;
      case 'fish':
        return Icons.set_meal_rounded;
      case 'reptiles':
      case 'amphibians':
        return Icons.emoji_nature_rounded;
      default:
        return Icons.pets_rounded;
    }
  }

  static List<Color> _gradientFor(String? category) {
    switch ((category ?? '').toLowerCase()) {
      case 'birds':
        return const [Color(0xFF1E3A5F), Color(0xFF2E6E8F)];
      case 'plants':
      case 'wildflowers':
      case 'trees':
        return const [Color(0xFF1B3A24), Color(0xFF2E7D46)];
      case 'fish':
        return const [Color(0xFF12303A), Color(0xFF1E6E7D)];
      case 'reptiles':
      case 'amphibians':
        return const [Color(0xFF2A331B), Color(0xFF5E7D2E)];
      default:
        return const [Color(0xFF2A2016), Color(0xFF6E5230)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradientFor(category);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconFor(category),
                color: Colors.white.withValues(alpha: 0.85),
                size: compact ? 28 : 44),
            if (!compact && (label ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(label!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A network image that falls back to a [WildlifePlaceholder] instead of a
/// broken-image glyph.
class SpeciesImageOrPlaceholder extends StatelessWidget {
  const SpeciesImageOrPlaceholder({
    super.key,
    required this.url,
    this.category,
    this.label,
    this.compact = false,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final String? category;
  final String? label;
  final bool compact;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final u = url?.trim() ?? '';
    if (u.isEmpty) {
      return WildlifePlaceholder(
          category: category, label: label, compact: compact);
    }
    return Image.network(
      u,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) =>
          WildlifePlaceholder(category: category, label: label, compact: compact),
      loadingBuilder: (c, child, p) => p == null
          ? child
          : WildlifePlaceholder(
              category: category, label: label, compact: compact),
    );
  }
}
