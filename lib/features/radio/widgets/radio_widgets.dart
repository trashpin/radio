import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';

/// Reusable building blocks for the ExplorerOS Radio experience. Every screen
/// (Radio, Station Selection, I See Something, Local Gems) composes these — no
/// duplicated UI code.

// ── Glass panel ──────────────────────────────────────────────────────────────

/// A rounded, dark translucent panel with a hairline border — the base surface
/// for cards, chips and bars.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(RD.lg),
    this.radius = RD.rLg,
    this.color,
    this.border = true,
    this.onTap,
    this.glow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final bool border;
  final VoidCallback? onTap;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final panel = AnimatedContainer(
      duration: RD.med,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? RD.panel,
        borderRadius: BorderRadius.circular(radius),
        border: border
            ? Border.all(color: glow ? RD.green : RD.stroke, width: glow ? 1.5 : 1)
            : null,
        boxShadow: glow ? RD.greenGlow(0.25) : null,
      ),
      child: child,
    );
    if (onTap == null) return panel;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: panel,
      ),
    );
  }
}

/// A frosted chip that floats over hero imagery (used for NEARBY / weather).
class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: RD.md, vertical: RD.sm),
      decoration: BoxDecoration(
        color: RD.glassFill(0.62),
        borderRadius: BorderRadius.circular(RD.rMd),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

// ── LIVE badge ───────────────────────────────────────────────────────────────

/// Pulsing red dot + "LIVE" label. When [compact], renders as a small pill for
/// overlaying hero art.
class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key, this.compact = false});
  final bool compact;

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: Tween(begin: 0.4, end: 1.0).animate(_c),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: RD.live, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 6),
        Text('LIVE',
            style: RD.badge.copyWith(
                color: RD.textPrimary, fontSize: widget.compact ? 11 : 12)),
      ],
    );
  }
}

// ── NEARBY badge ─────────────────────────────────────────────────────────────

/// The `NEARBY / place / distance` overlay chip.
class NearbyBadge extends StatelessWidget {
  const NearbyBadge({super.key, required this.place, this.distanceLabel});
  final String place;
  final String? distanceLabel;

  @override
  Widget build(BuildContext context) {
    return GlassChip(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.location_on_rounded, size: 13, color: RD.green),
            const SizedBox(width: 4),
            Text('NEARBY',
                style: RD.badge.copyWith(color: RD.green, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 3),
          Text(place,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RD.cardTitle.copyWith(fontSize: 15)),
          if (distanceLabel != null)
            Text(distanceLabel!, style: RD.caption.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Equalizer ────────────────────────────────────────────────────────────────

/// An animated green equalizer. Animates only while [active]; when idle it
/// shows a low, calm baseline. [bars] and [height] make it reusable at any size.
class Equalizer extends StatefulWidget {
  const Equalizer({
    super.key,
    required this.active,
    this.bars = 12,
    this.height = 34,
    this.barWidth = 3,
    this.color = RD.green,
    this.seed = 7,
  });

  final bool active;
  final int bars;
  final double height;
  final double barWidth;
  final Color color;
  final int seed;

  @override
  State<Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: RD.eq);
  late final List<double> _phase;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(widget.seed);
    _phase = [for (var i = 0; i < widget.bars; i++) rng.nextDouble()];
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant Equalizer old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.bars; i++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.barWidth * 0.4),
                child: _bar(i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bar(int i) {
    final t = (_c.value + _phase[i]) % 1.0;
    final wave = widget.active
        ? 0.25 + 0.75 * (0.5 - (t - 0.5).abs()) * 2
        : 0.18;
    final h = (widget.height * wave).clamp(widget.barWidth, widget.height);
    return Container(
      width: widget.barWidth,
      height: h,
      decoration: BoxDecoration(
        color: widget.active
            ? widget.color
            : widget.color.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(widget.barWidth),
      ),
    );
  }
}

// ── Playback controls ────────────────────────────────────────────────────────

/// Prev / large glowing Play-Pause / Next.
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.isPlaying,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    this.size = 84,
  });

  final bool isPlaying;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _round(Icons.skip_previous_rounded, onPrevious),
        const SizedBox(width: RD.xxl),
        _PlayButton(isPlaying: isPlaying, onTap: onPlayPause, size: size),
        const SizedBox(width: RD.xxl),
        _round(Icons.skip_next_rounded, onNext),
      ],
    );
  }

  Widget _round(IconData icon, VoidCallback onTap) => Material(
        color: RD.panel,
        shape: const CircleBorder(side: BorderSide(color: RD.stroke)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(icon, color: RD.textPrimary, size: 28),
          ),
        ),
      );
}

class _PlayButton extends StatefulWidget {
  const _PlayButton(
      {required this.isPlaying, required this.onTap, required this.size});
  final bool isPlaying;
  final VoidCallback onTap;
  final double size;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: RD.fast,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: RD.bgElevated,
            shape: BoxShape.circle,
            border: Border.all(color: RD.green, width: 3),
            boxShadow: RD.greenGlow(0.4),
          ),
          child: Icon(
            widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: RD.green,
            size: widget.size * 0.5,
          ),
        ),
      ),
    );
  }
}

// ── Primary action card (I See Something / Local Gems) ───────────────────────

class PrimaryActionCard extends StatelessWidget {
  const PrimaryActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tint = RD.green,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(RD.lg),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: tint.withValues(alpha: 0.6)),
            ),
            child: Icon(icon, color: tint, size: 22),
          ),
          const SizedBox(width: RD.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: RD.cardTitle
                        .copyWith(letterSpacing: 0.4, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: RD.body.copyWith(fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: RD.textFaint),
        ],
      ),
    );
  }
}

// ── Story card (Nearby Stories carousel) ─────────────────────────────────────

class StoryCard extends StatelessWidget {
  const StoryCard({
    super.key,
    required this.title,
    required this.category,
    this.imageUrl,
    this.distanceLabel,
    required this.onTap,
    this.width = 220,
  });

  final String title;
  final String category;
  final String? imageUrl;
  final String? distanceLabel;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: RD.panel,
        borderRadius: RD.brLg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(child: _NetworkImage(url: imageUrl)),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x11000000), Color(0xE6000000)],
                      stops: [0.35, 1],
                    ),
                  ),
                ),
              ),
              if (distanceLabel != null)
                Positioned(
                  top: RD.sm,
                  left: RD.sm,
                  child: GlassChip(
                    padding: const EdgeInsets.symmetric(
                        horizontal: RD.sm, vertical: 4),
                    child: Text(distanceLabel!,
                        style: RD.badge.copyWith(color: RD.textPrimary)),
                  ),
                ),
              Positioned(
                left: RD.md,
                right: RD.md,
                bottom: RD.md,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      const Icon(Icons.location_on_rounded,
                          size: 15, color: RD.green),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RD.cardTitle.copyWith(fontSize: 15)),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    Row(children: [
                      Expanded(
                        child: Text(category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RD.caption.copyWith(fontSize: 11)),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: RD.textFaint),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Location card (Local Gems list) ──────────────────────────────────────────

class LocationCard extends StatelessWidget {
  const LocationCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.imageUrl,
    this.leadingIcon = Icons.place_rounded,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? imageUrl;
  final IconData leadingIcon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(RD.md),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(RD.rSm),
            child: SizedBox(
              width: 56,
              height: 56,
              child: (imageUrl != null && imageUrl!.isNotEmpty)
                  ? _NetworkImage(url: imageUrl)
                  : Container(
                      color: RD.panelAlt,
                      child: Icon(leadingIcon, color: RD.green),
                    ),
            ),
          ),
          const SizedBox(width: RD.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RD.cardTitle.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RD.body.copyWith(fontSize: 12)),
              ],
            ),
          ),
          trailing ??
              const Icon(Icons.chevron_right_rounded, color: RD.textFaint),
        ],
      ),
    );
  }
}

// ── Bottom status bar ────────────────────────────────────────────────────────

class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.segments});
  final List<StatusSegment> segments;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: RD.md, vertical: RD.md),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            Expanded(child: _seg(segments[i])),
            if (i != segments.length - 1)
              Container(width: 1, height: 34, color: RD.stroke),
          ],
        ],
      ),
    );
  }

  Widget _seg(StatusSegment s) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(s.icon, color: s.tint, size: 20),
          const SizedBox(width: RD.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RD.cardTitle.copyWith(fontSize: 13)),
                Text(s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RD.caption.copyWith(fontSize: 10.5)),
              ],
            ),
          ),
        ],
      );
}

class StatusSegment {
  const StatusSegment({
    required this.icon,
    required this.value,
    required this.label,
    this.tint = RD.green,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color tint;
}

// ── Station card (Station Selection) ─────────────────────────────────────────

class StationCard extends StatelessWidget {
  const StationCard({
    super.key,
    required this.name,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      onTap: onTap,
      glow: selected,
      padding: const EdgeInsets.all(RD.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: RD.green.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: RD.green),
              ),
              const Spacer(),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: RD.green),
            ],
          ),
          const SizedBox(height: RD.md),
          Text(name, style: RD.title.copyWith(fontSize: 17)),
          const SizedBox(height: RD.xs),
          Text(description, style: RD.body.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

// ── Category tile (I See Something / Local Gems grids) ───────────────────────

class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint = RD.green,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(RD.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: tint.withValues(alpha: 0.5)),
            ),
            child: Icon(icon, color: tint, size: 26),
          ),
          const SizedBox(height: RD.sm),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: RD.cardTitle.copyWith(fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Page dots ────────────────────────────────────────────────────────────────

class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: RD.med,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? RD.green : RD.stroke,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

// ── Sub-page top bar (back + title + optional subtitle) ──────────────────────

class RadioSubPageBar extends StatelessWidget {
  const RadioSubPageBar({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(RD.sm, RD.sm, RD.lg, RD.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: RD.textPrimary),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(child: Text(title, style: RD.title.copyWith(fontSize: 22))),
          ]),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(RD.md, 0, 0, RD.sm),
              child: Text(subtitle!, style: RD.body),
            ),
        ],
      ),
    );
  }
}

/// A pill-style filter chip used by category selectors.
class RadioFilterChip extends StatelessWidget {
  const RadioFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? RD.green : RD.panel,
      borderRadius: BorderRadius.circular(RD.rPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(RD.rPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: RD.lg, vertical: RD.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RD.rPill),
            border: Border.all(color: selected ? RD.green : RD.stroke),
          ),
          child: Text(label,
              style: RD.caption.copyWith(
                  color: selected ? RD.onGreen : RD.textSecondary,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// ── Shared network image (never shows a broken glyph) ────────────────────────

class _NetworkImage extends StatelessWidget {
  const _NetworkImage({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const _ImageFallback();
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _ImageFallback(),
      loadingBuilder: (c, child, p) => p == null
          ? child
          : const ColoredBox(color: RD.panelAlt),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();
  @override
  Widget build(BuildContext context) => Container(
        color: RD.panelAlt,
        child: const Center(
            child: Icon(Icons.landscape_rounded, color: RD.greenDim, size: 34)),
      );
}
