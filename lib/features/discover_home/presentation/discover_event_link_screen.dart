import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_home/presentation/discover_item_detail_screen.dart';
import 'package:explorer_os_mobile/features/discover_home/providers/discover_event_link_provider.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// Resolves `/discover-event/:id` (the notification/deep-link target) into
/// the real event, then hands off to the normal
/// [DiscoverItemDetailScreen] — spec: "Notification -> Deep Link -> Open
/// Event -> Show Personalized Recommendation," never the generic Discover
/// home page.
class DiscoverEventLinkScreen extends ConsumerWidget {
  const DiscoverEventLinkScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(discoverEventByIdProvider(eventId));
    final matchAsync = ref.watch(discoverEventMatchProvider(eventId));

    return itemAsync.when(
      loading: () => const Scaffold(
        backgroundColor: RD.bg,
        body: Center(child: CircularProgressIndicator(color: RD.green)),
      ),
      error: (_, _) => const _NotFound(),
      data: (item) {
        if (item == null) return const _NotFound();
        final matched = (matchAsync.value?['matched_interest_tags'] as List?)
                ?.map((e) => e.toString())
                .toSet() ??
            const <String>{};
        return DiscoverItemDetailScreen(item: item, matchedInterests: matched);
      },
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(title: 'Event'),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(RD.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_busy_rounded, size: 48, color: RD.textSecondary),
                      const SizedBox(height: RD.md),
                      Text(
                        "We couldn't find that event — it may no longer be active.",
                        textAlign: TextAlign.center,
                        style: RD.body,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
