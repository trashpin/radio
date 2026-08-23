import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_home/models/discover_interest.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';
import 'package:explorer_os_mobile/features/discover_home/presentation/discover_audio_actions.dart';
import 'package:explorer_os_mobile/features/discover_home/presentation/discover_item_detail_screen.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// A "why recommended" caption from what actually matched — never fabricated,
/// only ever names interests the item genuinely carries (spec example:
/// "Recommended because you like History and Outdoor Activities.").
String? reasonCaption(Set<String> matchedInterests) {
  if (matchedInterests.isEmpty) return null;
  final labels = matchedInterests.map(discoverInterestLabel).toList();
  final joined = labels.length == 1
      ? labels.first
      : '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
  return 'Recommended because you like $joined.';
}

/// One Discover card — used across PICKED FOR YOU / TODAY / THIS WEEKEND /
/// NEAR YOU / YOU MIGHT LIKE. [recommendation] is optional: sections that
/// aren't interest-scored (TODAY/THIS WEEKEND/NEAR YOU) just pass the item.
class DiscoverItemCard extends ConsumerWidget {
  const DiscoverItemCard({super.key, required this.item, this.matchedInterests = const {}});

  final DiscoverableItem item;
  final Set<String> matchedInterests;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reason = reasonCaption(matchedInterests);
    final subtitleParts = [
      ?item.category,
      ?item.context.distanceLabel,
    ];
    return SizedBox(
      width: 240,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DiscoverItemDetailScreen(item: item)),
        ),
        child: GlassPanel(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(RD.rLg)),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: (item.imageUrl ?? '').isNotEmpty
                      ? Image.network(item.imageUrl!,
                          fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder())
                      : _placeholder(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(RD.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RD.cardTitle.copyWith(color: RD.textPrimary)),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitleParts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RD.caption.copyWith(color: RD.textSecondary)),
                    ],
                    if (reason != null) ...[
                      const SizedBox(height: RD.xs),
                      Text(reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: RD.caption.copyWith(
                              color: RD.green, fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: RD.sm),
                    _HearAboutItButton(item: item, matchedInterests: matchedInterests),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: RD.panelAlt,
        alignment: Alignment.center,
        child: const Icon(Icons.image_rounded, color: RD.textFaint, size: 32),
      );
}

class _HearAboutItButton extends ConsumerWidget {
  const _HearAboutItButton({required this.item, required this.matchedInterests});
  final DiscoverableItem item;
  final Set<String> matchedInterests;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      height: 34,
      child: OutlinedButton.icon(
        onPressed: () => hearAboutIt(context, ref, item, matchedInterests: matchedInterests),
        icon: const Icon(Icons.headphones_rounded, size: 16, color: RD.green),
        label: const Text('Hear About It', style: TextStyle(fontSize: 12, color: RD.green)),
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: const BorderSide(color: RD.green),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RD.rPill)),
        ),
      ),
    );
  }
}
