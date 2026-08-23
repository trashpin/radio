import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/discover_home/controllers/discover_audio_controller.dart';
import 'package:explorer_os_mobile/features/discover_home/data/discover_interactions_repository.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';
import 'package:explorer_os_mobile/features/discover_home/presentation/discover_audio_actions.dart';
import 'package:explorer_os_mobile/features/locations/data/location_favorites.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/services/tell_me_more_mapping.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';
import 'package:explorer_os_mobile/shared/design/category_visuals.dart';

/// The Discover favorites key for [item] — plain location ids for `location`
/// kind items (so a park favorited here matches the SAME
/// [locationFavoritesProvider] entry the rest of the app already reads),
/// prefixed for gems/events (a new use of that provider, no collision risk).
String discoverFavoriteKey(DiscoverableItem item) => switch (item.kind) {
      DiscoverItemKind.location => item.id,
      DiscoverItemKind.gem => 'gem:${item.id}',
      DiscoverItemKind.event => 'event:${item.id}',
    };

/// Full item detail — the spec's "show whatever information is available,
/// never show empty fields" page. Reuses [tellMeMoreResultProvider] for the
/// structured facts (same pipeline the Radio "Tell Me More" flow already
/// uses) rather than a second lookup system.
class DiscoverItemDetailScreen extends ConsumerWidget {
  const DiscoverItemDetailScreen({super.key, required this.item});
  final DiscoverableItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = item.context.tellMeMoreContext;
    final resultAsync = ctx.hasContext
        ? ref.watch(tellMeMoreResultProvider(ctx))
        : const AsyncValue<TellMeMoreResult?>.data(null);
    final favorites = ref.watch(locationFavoritesProvider);
    final favKey = discoverFavoriteKey(item);
    final isFav = favorites.contains(favKey);

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            RadioSubPageBar(title: item.title),
            Expanded(
              child: resultAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: RD.green)),
                error: (_, _) => _Body(item: item, result: null, isFav: isFav, favKey: favKey),
                data: (result) =>
                    _Body(item: item, result: result, isFav: isFav, favKey: favKey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.item, required this.result, required this.isFav, required this.favKey});
  final DiscoverableItem item;
  final TellMeMoreResult? result;
  final bool isFav;
  final String favKey;

  Future<void> _navigate() async {
    final loc = item.context.tellMeMoreContext.location;
    final lat = loc?.latitude ?? result?.latitude;
    final lng = loc?.longitude ?? result?.longitude;
    if (lat == null || lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openUrl(String? url) async {
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _addToCalendar() async {
    final date = item.eventDate;
    if (date == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    final start = '${date.year}${two(date.month)}${two(date.day)}';
    final end = date.add(const Duration(days: 1));
    final endStr = '${end.year}${two(end.month)}${two(end.day)}';
    final details = [
      ?item.teaser,
      ?result?.eventTimeLabel,
    ].join(' — ');
    final uri = Uri.https('www.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': item.title,
      'dates': '$start/$endStr',
      if (details.trim().isNotEmpty) 'details': details,
      if (result?.locationLabel != null) 'location': result!.locationLabel!,
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleParts = [
      ?item.category,
      ?item.context.distanceLabel,
      ?result?.eventDateLabel,
      ?result?.eventTimeLabel,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(RD.lg, 0, RD.lg, RD.xl),
      children: [
        if ((item.imageUrl ?? '').isNotEmpty)
          ClipRRect(
            borderRadius: RD.brXl,
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Image.network(item.imageUrl!, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(color: RD.panel)),
            ),
          ),
        const SizedBox(height: RD.lg),
        Text(item.title, style: RD.title.copyWith(fontSize: 22)),
        if (subtitleParts.isNotEmpty) ...[
          const SizedBox(height: RD.xs),
          Row(children: [
            Icon(
              categoryIconFor(
                  item.category ?? (item.kind == DiscoverItemKind.gem ? 'gem' : null)),
              size: 15,
              color: RD.green,
            ),
            const SizedBox(width: RD.xs),
            Expanded(
              child: Text(subtitleParts.join(' · '), style: RD.caption.copyWith(color: RD.green)),
            ),
          ]),
        ],
        const SizedBox(height: RD.lg),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => hearAboutIt(context, ref, item),
              icon: const Icon(Icons.headphones_rounded, color: RD.green),
              label: const Text('Hear About It', style: TextStyle(color: RD.green)),
            ),
          ),
          const SizedBox(width: RD.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final history = result?.history?.trim() ?? '';
                if (history.isNotEmpty) {
                  ref.read(discoverInteractionsRepositoryProvider).log(item, 'heard');
                  await ref.read(discoverAudioControllerProvider.notifier).play(
                        title: item.title,
                        audioUrl: (result?.hasAudio ?? false) ? result!.audioUrl : null,
                        spokenText: history,
                      );
                } else {
                  await tellMeMoreAudio(context, ref, item);
                }
              },
              icon: const Icon(Icons.menu_book_rounded, color: RD.green),
              label: const Text('Tell Me More', style: TextStyle(color: RD.green)),
            ),
          ),
        ]),
        if ((result?.history ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: RD.lg),
          GlassPanel(child: Text(result!.history!, style: RD.body.copyWith(height: 1.5))),
        ],
        if (result?.hours != null || result?.admission != null || result?.costInfo != null) ...[
          const SizedBox(height: RD.md),
          _Fact(icon: Icons.schedule_rounded, label: 'Hours', value: result?.hours),
          _Fact(icon: Icons.local_activity_rounded, label: 'Admission', value: result?.admission),
          _Fact(icon: Icons.attach_money_rounded, label: 'Cost', value: result?.costInfo),
        ],
        _Fact(icon: Icons.phone_rounded, label: 'Phone', value: result?.phone),
        _Fact(icon: Icons.accessible_rounded, label: 'Accessibility', value: result?.accessibilityInfo),
        if (result?.familyFriendly == true)
          const _Fact(icon: Icons.family_restroom_rounded, label: 'Good for', value: 'Families'),
        if (result?.activities.isNotEmpty ?? false) ...[
          const SizedBox(height: RD.lg),
          Text('Highlights', style: RD.sectionLabel),
          const SizedBox(height: RD.sm),
          Wrap(spacing: RD.sm, runSpacing: RD.sm, children: [
            for (final a in result!.activities)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: RD.md, vertical: 6),
                decoration: BoxDecoration(
                    color: RD.panel,
                    borderRadius: BorderRadius.circular(RD.rPill),
                    border: Border.all(color: RD.stroke)),
                child: Text(a, style: RD.caption.copyWith(color: RD.textPrimary)),
              ),
          ]),
        ],
        if (result?.goodToKnow.isNotEmpty ?? false) ...[
          const SizedBox(height: RD.lg),
          Text('Good to know', style: RD.sectionLabel),
          const SizedBox(height: RD.sm),
          for (final g in result!.goodToKnow)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  ', style: TextStyle(color: RD.green)),
                Expanded(child: Text(g, style: RD.body)),
              ]),
            ),
        ],
        const SizedBox(height: RD.lg),
        Wrap(spacing: RD.sm, runSpacing: RD.sm, children: [
          if (result?.canNavigate ?? item.context.tellMeMoreContext.location != null)
            _ActionChip(icon: Icons.directions_rounded, label: 'Navigate', onTap: () {
              ref.read(discoverInteractionsRepositoryProvider).log(item, 'navigated');
              _navigate();
            }),
          if (result?.hasWebsite ?? false)
            _ActionChip(icon: Icons.open_in_new_rounded, label: 'Website', onTap: () {
              ref.read(discoverInteractionsRepositoryProvider).log(item, 'website');
              _openUrl(result?.website);
            }),
          if (result?.hasTicket ?? false)
            _ActionChip(icon: Icons.confirmation_num_rounded, label: 'Tickets', onTap: () {
              ref.read(discoverInteractionsRepositoryProvider).log(item, 'tickets');
              _openUrl(result?.ticketUrl);
            }),
          if (result?.hasRegistration ?? false)
            _ActionChip(icon: Icons.how_to_reg_rounded, label: 'Register', onTap: () {
              ref.read(discoverInteractionsRepositoryProvider).log(item, 'registration');
              _openUrl(result?.registrationUrl);
            }),
          if (item.eventDate != null)
            _ActionChip(icon: Icons.event_available_rounded, label: 'Add to Calendar', onTap: _addToCalendar),
          _ActionChip(
            icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            label: isFav ? 'Saved' : 'Save',
            active: isFav,
            onTap: () {
              ref.read(locationFavoritesProvider.notifier).toggle(favKey);
              ref.read(discoverInteractionsRepositoryProvider).log(item, 'saved');
            },
          ),
        ]),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, this.value});
  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if ((value ?? '').trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, color: RD.green, size: 18),
        const SizedBox(width: RD.sm),
        Text('$label: ', style: RD.caption.copyWith(color: RD.textSecondary)),
        Expanded(child: Text(value!, style: RD.body)),
      ]),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? RD.live : RD.green;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      style: OutlinedButton.styleFrom(side: BorderSide(color: color)),
    );
  }
}
