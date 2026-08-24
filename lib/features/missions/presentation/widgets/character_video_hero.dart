import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';

/// A character avatar video (HeyGen) as the visual/audio centerpiece of a
/// story beat — the Adventure Introduction, a QR/Old World "new character
/// appears" reveal, or the Final Reveal. Shared by [MissionIntroScreen],
/// [OldWorldScreen], and [MissionCompleteScreen] rather than duplicated —
/// same autoplay-with-sound, tap-to-pause behavior everywhere a character
/// speaks on video. Portrait (matches the 720x1280/9:16 the
/// `heygen-avatar` edge function renders at).
class CharacterVideoHero extends StatefulWidget {
  const CharacterVideoHero({super.key, required this.videoUrl});
  final String videoUrl;

  @override
  State<CharacterVideoHero> createState() => _CharacterVideoHeroState();
}

class _CharacterVideoHeroState extends State<CharacterVideoHero> {
  late final VideoPlayerController _controller =
      VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play());
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: RD.brLg,
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: _ready
            ? GestureDetector(
                onTap: _toggle,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoPlayer(_controller),
                    if (!_controller.value.isPlaying)
                      Container(
                        color: Colors.black26,
                        child: const Center(
                          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 56),
                        ),
                      ),
                  ],
                ),
              )
            : Container(
                color: RD.panelAlt,
                child: const Center(child: CircularProgressIndicator(color: RD.green)),
              ),
      ),
    );
  }
}
