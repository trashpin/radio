import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/widgets/forest_audio_bar.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/ocala_forest_providers.dart';
import 'package:explorer_os_mobile/features/ocala_forest/services/forest_playback.dart';
import 'package:explorer_os_mobile/features/ocala_forest/services/forest_story_selector.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// FOREST STORIES — `experienceType == 'story'` forest locations. Mirrors
/// `GpsStorySelector` (`lib/features/story_studio/services/gps_story_selector.dart`)
/// via `ForestStorySelector` for the "play something nearby" action.
///
/// No real story content is seeded yet (nothing was fabricated to fill this
/// category) — the mechanism is fully built and tested; this screen will
/// start surfacing real stories the moment `forest_locations` rows with
/// `experience_type = 'story'` exist.
class ForestStoriesScreen extends ConsumerStatefulWidget {
  const ForestStoriesScreen({super.key});

  @override
  ConsumerState<ForestStoriesScreen> createState() => _ForestStoriesScreenState();
}

class _ForestStoriesScreenState extends ConsumerState<ForestStoriesScreen> {
  final _selector = ForestStorySelector();
  final Set<String> _played = {};
  String? _status;

  void _playNearby(List<ForestLocation> stories) {
    final loc = ref.read(gpsControllerProvider).location;
    if (loc == null) {
      setState(() => _status = 'Waiting for a GPS fix…');
      return;
    }
    final story = _selector.select(stories, loc.latitude, loc.longitude,
        alreadyPlayed: _played);
    if (story == null) {
      setState(() => _status = 'No forest story is close enough to play right now.');
      return;
    }
    _played.add(story.id);
    playForestLocation(ref, story);
    setState(() => _status = 'Playing: ${story.name}');
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(forestLocationsProvider);
    final stories = (locationsAsync.value ?? const <ForestLocation>[])
        .where((l) => l.isStory && l.active)
        .toList();

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(
                title: 'Forest Stories', subtitle: 'Ocala National Forest'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: RD.lg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _playNearby(stories),
                  icon: const Icon(Icons.auto_stories_rounded),
                  label: const Text('Play a Nearby Story'),
                ),
              ),
            ),
            if (_status != null) ...[
              const SizedBox(height: RD.sm),
              Text(_status!,
                  style: RD.caption.copyWith(color: RD.textSecondary)),
            ],
            const Padding(
              padding: EdgeInsets.fromLTRB(RD.lg, RD.sm, RD.lg, 0),
              child: ForestAudioBar(),
            ),
            const SizedBox(height: RD.md),
            Expanded(
              child: stories.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(RD.xl),
                        child: Text(
                          'No forest stories have been added yet — check '
                          'back soon.',
                          textAlign: TextAlign.center,
                          style: RD.body.copyWith(color: RD.textSecondary),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(RD.lg),
                      itemCount: stories.length,
                      separatorBuilder: (_, _) => const SizedBox(height: RD.sm),
                      itemBuilder: (context, i) {
                        final story = stories[i];
                        return GlassPanel(
                          onTap: () {
                            _played.add(story.id);
                            playForestLocation(ref, story);
                          },
                          child: Row(
                            children: [
                              const Icon(Icons.auto_stories_rounded,
                                  color: RD.greenBright),
                              const SizedBox(width: RD.sm),
                              Expanded(
                                child: Text(story.name,
                                    style:
                                        RD.cardTitle.copyWith(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
