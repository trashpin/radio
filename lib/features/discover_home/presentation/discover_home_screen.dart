import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_home/controllers/discover_audio_controller.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';
import 'package:explorer_os_mobile/features/discover_home/presentation/discover_ask_input.dart';
import 'package:explorer_os_mobile/features/discover_home/presentation/discover_interests_screen.dart';
import 'package:explorer_os_mobile/features/discover_home/presentation/discover_item_card.dart';
import 'package:explorer_os_mobile/features/discover_home/presentation/discover_mini_player.dart';
import 'package:explorer_os_mobile/features/discover_home/providers/discover_greeting_provider.dart';
import 'package:explorer_os_mobile/features/discover_home/providers/discover_interests_provider.dart';
import 'package:explorer_os_mobile/features/discover_home/providers/discover_items_provider.dart';
import 'package:explorer_os_mobile/features/discover_home/services/discover_recommendation_engine.dart';
import 'package:explorer_os_mobile/features/gps/presentation/location_prompt.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// "What can I do in Marion County?" — the Discover tab replacing Radio's
/// former primary-nav slot. A personalized feed built entirely from existing
/// content (`nearby_gems`/`events`/`locations` via [discoverAllItemsProvider])
/// — no new content system, no duplicate database.
class DiscoverHomeScreen extends ConsumerStatefulWidget {
  const DiscoverHomeScreen({super.key});

  @override
  ConsumerState<DiscoverHomeScreen> createState() => _DiscoverHomeScreenState();
}

class _DiscoverHomeScreenState extends ConsumerState<DiscoverHomeScreen> {
  @override
  void initState() {
    super.initState();
    // Best-effort GPS start — NEAR YOU still works (county-wide fallback)
    // without it, per spec.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(gpsStatusProvider.notifier)
          .requestAndStart()
          .catchError((_) => ref.read(gpsStatusProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(discoverAllItemsProvider);
    final interests = ref.watch(discoverInterestsProvider);
    final hasRealLocation = ref.watch(discoverHasRealLocationProvider);
    const engine = DiscoverRecommendationEngine();

    final picked = engine.pickedForYou(items, interests);
    final today = engine.today(items);
    final weekend = engine.thisWeekend(items);
    final near = engine.nearYou(items);
    final shownIds = <String>{
      for (final r in picked) r.item.id,
      for (final i in today) i.id,
      for (final i in weekend) i.id,
      for (final i in near) i.id,
    };
    final youMightLike = engine.youMightLike(items, interests, shownIds);

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Stack(children: [
          items.isEmpty
              ? const _EmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(RD.lg, RD.sm, RD.lg, 96),
                  children: [
                    const _GreetingHeader(),
                    const SizedBox(height: RD.sm),
                    const DiscoverAskInput(),
                    const SizedBox(height: RD.md),
                    const LocationPrompt(margin: EdgeInsets.only(bottom: RD.md)),
                    if (interests.isEmpty) const _InterestsPrompt(),
                    if (picked.isNotEmpty)
                      _RecommendationSection(title: 'PICKED FOR YOU', items: picked),
                    if (today.isNotEmpty)
                      _ItemSection(title: 'TODAY', items: today),
                    if (weekend.isNotEmpty)
                      _ItemSection(title: 'THIS WEEKEND', items: weekend),
                    _ItemSection(
                      title: hasRealLocation ? 'NEAR YOU' : 'AROUND MARION COUNTY',
                      items: near,
                    ),
                    if (youMightLike.isNotEmpty)
                      _ItemSection(title: 'YOU MIGHT LIKE', items: youMightLike),
                  ],
                ),
          Positioned(
            left: RD.lg,
            right: RD.lg,
            bottom: RD.sm,
            child: const DiscoverMiniPlayer(),
          ),
        ]),
      ),
    );
  }
}

/// "Hey Steve, what are you in the mood to do today?" — a fresh, varied,
/// context-aware opening line each session (see `discover_greeting_provider`
/// / `discover_greeting_selector`), spoken aloud once via the same narration
/// player every other Discover audio uses (so the radio ducks/resumes around
/// it exactly like a "Hear About It" tap would).
class _GreetingHeader extends ConsumerStatefulWidget {
  const _GreetingHeader();

  @override
  ConsumerState<_GreetingHeader> createState() => _GreetingHeaderState();
}

class _GreetingHeaderState extends ConsumerState<_GreetingHeader> {
  bool _spoken = false;

  void _maybeAutoSpeak(String text) {
    if (_spoken) return;
    _spoken = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(discoverAudioControllerProvider.notifier)
          .play(title: 'Discover', spokenText: text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final greeting = ref.watch(discoverGreetingProvider);

    final text = greeting.when(
      data: (s) {
        _maybeAutoSpeak(s.text);
        return s.text;
      },
      loading: () => "Here's what you might enjoy around Marion County.",
      error: (_, _) => "Here's what you might enjoy around Marion County.",
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(text, style: RD.title.copyWith(fontSize: 22)),
        ),
        IconButton(
          icon: const Icon(Icons.volume_up_rounded, color: RD.textSecondary),
          tooltip: 'Hear it',
          onPressed: () => ref
              .read(discoverAudioControllerProvider.notifier)
              .play(title: 'Discover', spokenText: text),
        ),
        IconButton(
          icon: const Icon(Icons.tune_rounded, color: RD.textSecondary),
          tooltip: 'Edit interests',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DiscoverInterestsScreen()),
          ),
        ),
      ],
    );
  }
}

class _InterestsPrompt extends StatelessWidget {
  const _InterestsPrompt();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RD.lg),
      child: GlassPanel(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DiscoverInterestsScreen()),
        ),
        child: Row(children: [
          const Icon(Icons.tune_rounded, color: RD.green),
          const SizedBox(width: RD.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tell us what you like', style: RD.cardTitle.copyWith(color: RD.textPrimary)),
                const SizedBox(height: 2),
                Text('Pick your interests for picks made just for you.',
                    style: RD.caption.copyWith(color: RD.textSecondary)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: RD.textFaint),
        ]),
      ),
    );
  }
}

class _RecommendationSection extends StatelessWidget {
  const _RecommendationSection({required this.title, required this.items});
  final String title;
  final List<DiscoverRecommendation> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RD.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: RD.sectionLabel),
          const SizedBox(height: RD.sm),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: RD.md),
              itemBuilder: (_, i) => DiscoverItemCard(
                item: items[i].item,
                matchedInterests: items[i].matchedInterests,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemSection extends StatelessWidget {
  const _ItemSection({required this.title, required this.items});
  final String title;
  final List<DiscoverableItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: RD.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: RD.sectionLabel),
          const SizedBox(height: RD.sm),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: RD.md),
              itemBuilder: (_, i) => DiscoverItemCard(item: items[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_rounded, size: 56, color: RD.textSecondary),
            const SizedBox(height: RD.lg),
            Text('Nothing to discover yet',
                textAlign: TextAlign.center, style: RD.title.copyWith(fontSize: 20)),
            const SizedBox(height: RD.sm),
            Text(
              "We're still loading what's around Marion County — check back in a moment.",
              textAlign: TextAlign.center,
              style: RD.body,
            ),
          ],
        ),
      ),
    );
  }
}
