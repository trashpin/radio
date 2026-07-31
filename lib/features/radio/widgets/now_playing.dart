import 'dart:async';

import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// A single image with a slow Ken Burns zoom + pan that loops gently.
class KenBurnsImage extends StatefulWidget {
  const KenBurnsImage({super.key, required this.url});
  final String url;

  @override
  State<KenBurnsImage> createState() => _KenBurnsImageState();
}

class _KenBurnsImageState extends State<KenBurnsImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 18))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        final scale = 1.0 + 0.12 * t;
        final dx = (t - 0.5) * 0.06;
        final dy = (0.5 - t) * 0.04;
        return Transform.scale(
          scale: scale,
          alignment: Alignment(dx, dy),
          child: child,
        );
      },
      child: Image.network(
        widget.url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => Container(
          color: RD.panel,
          child: const Center(
              child: Icon(Icons.image_rounded, color: RD.greenDim, size: 40)),
        ),
      ),
    );
  }
}

/// A hero slideshow: if [images] has one, it Ken-Burns-animates it; if several,
/// it crossfades between them every [interval] (each with its own Ken Burns),
/// preloading the next image for a smooth transition.
class HeroSlideshow extends StatefulWidget {
  const HeroSlideshow({
    super.key,
    required this.images,
    this.interval = const Duration(seconds: 12),
  });
  final List<String> images;
  final Duration interval;

  @override
  State<HeroSlideshow> createState() => _HeroSlideshowState();
}

class _HeroSlideshowState extends State<HeroSlideshow> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant HeroSlideshow old) {
    super.didUpdateWidget(old);
    if (old.images != widget.images) {
      _index = 0;
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.images.length < 2) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted) return;
      final next = (_index + 1) % widget.images.length;
      // Preload the upcoming image before showing it.
      precacheImage(NetworkImage(widget.images[next]), context);
      setState(() => _index = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Container(
        color: RD.panel,
        child: const Center(
            child: Icon(Icons.landscape_rounded, color: RD.greenDim, size: 44)),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 900),
      child: KenBurnsImage(
        key: ValueKey(widget.images[_index]),
        url: widget.images[_index],
      ),
    );
  }
}

/// The expanded "Now Playing" hero: an edge-to-edge slideshow with a dark
/// gradient, a LIVE badge, category chip, title, distance, and a favorite heart.
/// Rounded bottom corners. Purely presentational — the screen supplies data.
class NowPlayingHero extends StatelessWidget {
  const NowPlayingHero({
    super.key,
    required this.images,
    required this.title,
    required this.category,
    this.distanceLabel,
    this.favorite,
    this.onFavorite,
    this.height = 320,
  });

  final List<String> images;
  final String title;
  final String category;
  final String? distanceLabel;

  /// null = favorite not applicable (e.g. a species, not a saved location).
  final bool? favorite;
  final VoidCallback? onFavorite;
  final double height;

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.of(context).size.height * 0.38).clamp(240.0, height);
    return ClipRRect(
      borderRadius: BorderRadius.circular(RD.rXl),
      child: SizedBox(
        height: h,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            HeroSlideshow(images: images),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Color(0x11000000), Color(0xE6000000)],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
            Positioned(
              top: RD.md,
              left: RD.md,
              child: GlassChip(child: const LiveBadge(compact: true)),
            ),
            if (favorite != null)
              Positioned(
                top: RD.sm,
                right: RD.sm,
                child: IconButton(
                  onPressed: onFavorite,
                  icon: Icon(
                    favorite!
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: favorite! ? RD.green : Colors.white,
                    size: 28,
                  ),
                ),
              ),
            Positioned(
              left: RD.lg,
              right: RD.lg,
              bottom: RD.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: RD.md, vertical: 5),
                    decoration: BoxDecoration(
                      color: RD.green,
                      borderRadius: BorderRadius.circular(RD.rPill),
                    ),
                    child: Text(category.toUpperCase(),
                        style: RD.badge.copyWith(color: RD.onGreen)),
                  ),
                  const SizedBox(height: RD.sm),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: RD.title.copyWith(
                          fontSize: 26, height: 1.1, shadows: const [
                        Shadow(color: Colors.black, blurRadius: 12),
                      ])),
                  if ((distanceLabel ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.near_me_rounded,
                          color: RD.green, size: 15),
                      const SizedBox(width: 4),
                      Text(distanceLabel!,
                          style: RD.caption.copyWith(color: Colors.white)),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Now Playing controls: Play/Pause (large), Skip, and Save / Navigate /
/// More Photos chips. No progress bar, timer, or volume — by design.
class NowPlayingControls extends StatelessWidget {
  const NowPlayingControls({
    super.key,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSkip,
    this.saved,
    this.onSave,
    this.onNavigate,
    this.onMorePhotos,
  });

  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onSkip;

  /// null = not applicable; disables the Save chip.
  final bool? saved;
  final VoidCallback? onSave;
  final VoidCallback? onNavigate;
  final VoidCallback? onMorePhotos;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PlayPause(isPlaying: isPlaying, onTap: onPlayPause),
            const SizedBox(width: RD.xxl),
            Material(
              color: RD.panel,
              shape: const CircleBorder(side: BorderSide(color: RD.stroke)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onSkip,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Icon(Icons.skip_next_rounded,
                      color: RD.textPrimary, size: 30),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: RD.lg),
        Row(
          children: [
            Expanded(
              child: _Chip(
                icon: (saved ?? false)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: (saved ?? false) ? 'Saved' : 'Save',
                highlight: saved ?? false,
                onTap: onSave,
              ),
            ),
            const SizedBox(width: RD.sm),
            Expanded(
              child: _Chip(
                icon: Icons.navigation_rounded,
                label: 'Navigate',
                onTap: onNavigate,
              ),
            ),
            if (onMorePhotos != null) ...[
              const SizedBox(width: RD.sm),
              Expanded(
                child: _Chip(
                  icon: Icons.photo_library_rounded,
                  label: 'Photos',
                  onTap: onMorePhotos,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PlayPause extends StatefulWidget {
  const _PlayPause({required this.isPlaying, required this.onTap});
  final bool isPlaying;
  final VoidCallback onTap;
  @override
  State<_PlayPause> createState() => _PlayPauseState();
}

class _PlayPauseState extends State<_PlayPause> {
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
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: RD.bgElevated,
            shape: BoxShape.circle,
            border: Border.all(color: RD.green, width: 3),
            boxShadow: RD.greenGlow(0.4),
          ),
          child: Icon(
            widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: RD.green,
            size: 38,
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    this.onTap,
    this.highlight = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? RD.green : RD.textPrimary;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: RD.panel,
        borderRadius: RD.brMd,
        child: InkWell(
          borderRadius: RD.brMd,
          onTap: onTap,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: RD.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RD.caption.copyWith(color: color)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen swipeable gallery for the "More Photos" action.
void showRadioPhotoGallery(
    BuildContext context, List<String> images, String title) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: PageView.builder(
        itemCount: images.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: Image.network(images[i],
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(Icons.photo_outlined,
                    color: Colors.white38, size: 64)),
          ),
        ),
      ),
    ),
  ));
}
