import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';

/// The "HISTORICAL EVIDENCE" visual language for Marion County Adventures —
/// deliberately distinct from the modern Guide's own clean presentation
/// (spec: "MODERN GUIDE" vs "HISTORICAL EVIDENCE" must feel like two
/// different things). Two variants:
///
/// - [ArchivedFilmOverlay] wraps a video player: desaturated, low-contrast
///   grade, a soft vignette, and a sparse, intermittent grain/scratch/
///   flicker pass — tuned to read as "an old recording," not "a modern
///   video with a filter slapped on." The character must stay clearly
///   legible at all times; nothing here obscures the performance.
/// - [ArchivedPaperFrame] wraps a static image (photograph/document/map/
///   object): a light sepia grade plus an aged, bordered card.
///
/// No projector/film-audio texture is layered in — there's no royalty-free
/// asset in this repo to use, and faking one with a system beep would read
/// as cheap. Documented here as a known, deliberate gap rather than a
/// silent omission; a real texture can be dropped in later as a config URL.
class ArchivedFilmOverlay extends StatefulWidget {
  const ArchivedFilmOverlay({super.key, required this.child, this.label});
  final Widget child;
  final String? label;

  @override
  State<ArchivedFilmOverlay> createState() => _ArchivedFilmOverlayState();
}

class _ArchivedFilmOverlayState extends State<ArchivedFilmOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: RD.brLg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColorFiltered(colorFilter: const ColorFilter.matrix(_filmGradeMatrix), child: widget.child),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.05,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => CustomPaint(painter: _FilmGrainPainter(_controller.value)),
            ),
          ),
          if (widget.label != null)
            Positioned(
              top: 10,
              left: 10,
              child: _ArchivedTag(label: widget.label!),
            ),
        ],
      ),
    );
  }
}

// Desaturating, slightly contrast-boosted, darkened-highlight matrix — "old
// film stock," not a flat grayscale conversion.
const List<double> _filmGradeMatrix = <double>[
  0.30, 0.59, 0.11, 0, -12,
  0.30, 0.59, 0.11, 0, -12,
  0.30, 0.59, 0.11, 0, -18,
  0, 0, 0, 1, 0,
];

class _FilmGrainPainter extends CustomPainter {
  _FilmGrainPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random((t * 1000).floor());

    // Flicker: a very small, fast brightness wobble — kept subtle so the
    // character's face never dims into illegibility.
    final flicker = 0.03 + 0.04 * (0.5 + 0.5 * math.sin(t * math.pi * 26));
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: flicker),
    );

    // Sparse grain speckles.
    final grainPaint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (var i = 0; i < 50; i++) {
      final dx = rand.nextDouble() * size.width;
      final dy = rand.nextDouble() * size.height;
      canvas.drawCircle(Offset(dx, dy), 0.6, grainPaint);
    }

    // Intermittent vertical scratch — appears for a slice of the cycle,
    // then moves, rather than sitting in one place the whole time.
    final scratchPhase = (t * 5) % 1.0;
    if (scratchPhase < 0.18) {
      final x = (0.15 + 0.7 * math.sin(t * math.pi * 3.7).abs()) * size.width;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 1.2, size.height),
        Paint()..color = Colors.white.withValues(alpha: 0.16),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FilmGrainPainter oldDelegate) => oldDelegate.t != t;
}

/// Static-image evidence (photograph/document/map/object): a lighter sepia
/// grade plus an aged, bordered card — legible at a glance as "old," without
/// the motion effects a still image doesn't need.
class ArchivedPaperFrame extends StatelessWidget {
  const ArchivedPaperFrame({super.key, required this.child, this.label});
  final Widget child;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: RD.brLg,
        border: Border.all(color: const Color(0xFF8A7358), width: 3),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RD.brLg.topLeft.x - 3),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColorFiltered(colorFilter: const ColorFilter.matrix(_sepiaMatrix), child: child),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.1,
                    colors: [Colors.transparent, const Color(0xFF3A2E1F).withValues(alpha: 0.35)],
                    stops: const [0.6, 1.0],
                  ),
                ),
              ),
            ),
            if (label != null) Positioned(top: 10, left: 10, child: _ArchivedTag(label: label!)),
          ],
        ),
      ),
    );
  }
}

const List<double> _sepiaMatrix = <double>[
  0.39, 0.77, 0.19, 0, 0,
  0.35, 0.69, 0.17, 0, 0,
  0.27, 0.53, 0.13, 0, 0,
  0, 0, 0, 1, 0,
];

class _ArchivedTag extends StatelessWidget {
  const _ArchivedTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.movie_filter_outlined, size: 12, color: Colors.white70),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
      ]),
    );
  }
}
