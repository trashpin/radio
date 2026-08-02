import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_area/controllers/audio_experience_controller.dart';
import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/discover_area/providers/audio_experience_provider.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// "Audio Experience" — sit back and listen. Plays the area's introduction,
/// history, a few wildlife highlights, nature, interesting facts, and nearby
/// attractions back to back, then returns to the normal radio. Designed to
/// be safe to use while driving: large text, minimal interaction, no images
/// competing for attention.
class AudioExperienceScreen extends ConsumerStatefulWidget {
  const AudioExperienceScreen({super.key, required this.area});
  final DiscoveryArea area;

  @override
  ConsumerState<AudioExperienceScreen> createState() => _AudioExperienceScreenState();
}

class _AudioExperienceScreenState extends ConsumerState<AudioExperienceScreen> {
  bool _started = false;

  // Captured in initState so dispose() never touches `ref` (unsafe after
  // unmount) — a lazy `late` field would initialize during dispose.
  late final AudioExperienceController _audio;

  @override
  void initState() {
    super.initState();
    _audio = ref.read(audioExperienceControllerProvider.notifier);
  }

  @override
  void dispose() {
    _audio.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(audioExperienceSequenceProvider(widget.area));
    final playback = ref.watch(audioExperienceControllerProvider);

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            RadioSubPageBar(title: 'Audio Experience', subtitle: widget.area.name),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _empty(),
                data: (items) {
                  if (items.isEmpty) return _empty();
                  if (!_started) {
                    _started = true;
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => ref.read(audioExperienceControllerProvider.notifier).play(items),
                    );
                  }
                  final current = playback.current ?? items.first;
                  final index = playback.items.isEmpty
                      ? 0
                      : playback.items.indexOf(current).clamp(0, items.length - 1);
                  return _player(current.title, index + 1, items.length, playback.hasNext);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headphones_rounded, size: 56, color: RD.textSecondary),
            const SizedBox(height: RD.lg),
            Text('Nothing to play yet for ${widget.area.name}',
                textAlign: TextAlign.center, style: RD.title.copyWith(fontSize: 20)),
            const SizedBox(height: RD.sm),
            Text(
              'Add History, Nature, or Attractions content for this area to '
              'enable the full audio experience.',
              textAlign: TextAlign.center,
              style: RD.body,
            ),
          ],
        ),
      ),
    );
  }

  Widget _player(String title, int position, int total, bool hasNext) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq_rounded, size: 64, color: RD.green),
            const SizedBox(height: RD.lg),
            Text('$position of $total', style: RD.badge.copyWith(color: RD.textSecondary)),
            const SizedBox(height: RD.sm),
            Text(title, textAlign: TextAlign.center, style: RD.title.copyWith(fontSize: 24)),
            const SizedBox(height: RD.xxl),
            FilledButton.icon(
              onPressed: hasNext
                  ? () => ref.read(audioExperienceControllerProvider.notifier).skipToNext()
                  : () => Navigator.of(context).maybePop(),
              icon: Icon(hasNext ? Icons.skip_next_rounded : Icons.check_rounded),
              label: Text(hasNext ? 'Skip Ahead' : 'Done'),
            ),
          ],
        ),
      ),
    );
  }
}
