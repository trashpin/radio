import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_home/models/discover_intent.dart';
import 'package:explorer_os_mobile/features/discover_home/presentation/discover_item_card.dart';
import 'package:explorer_os_mobile/features/discover_home/providers/discover_interests_provider.dart';
import 'package:explorer_os_mobile/features/discover_home/providers/discover_items_provider.dart';
import 'package:explorer_os_mobile/features/discover_home/services/discover_recommendation_engine.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// What Discover found for one natural-language answer to the opening
/// question — spec's "DISCOVER UNDERSTANDS -> PERSONALIZED RESULTS" step.
/// Reuses the exact same item pool/cards/audio the home feed already uses;
/// this is a different ranking of the same content, not a second system.
class DiscoverAskResultsScreen extends ConsumerWidget {
  const DiscoverAskResultsScreen({super.key, required this.query, required this.intent});

  final String query;
  final DiscoverIntent intent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(discoverAllItemsProvider);
    final interests = ref.watch(discoverInterestsProvider);
    const engine = DiscoverRecommendationEngine();
    final results = engine.respondToIntent(items, intent, interests);

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            RadioSubPageBar(title: 'For "$query"'),
            Expanded(
              child: results.isEmpty
                  ? const _NothingYet()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(RD.lg, RD.md, RD.lg, RD.xl),
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: RD.md),
                      itemBuilder: (_, i) => Align(
                        alignment: Alignment.centerLeft,
                        child: DiscoverItemCard(item: results[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: RD.textSecondary),
            const SizedBox(height: RD.md),
            Text("Nothing matched that yet — check back as more of Marion County is added.",
                textAlign: TextAlign.center, style: RD.body),
          ],
        ),
      ),
    );
  }
}
