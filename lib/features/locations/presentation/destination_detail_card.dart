import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/locations/data/location_favorites.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/radio/discovery/nearby_narration_controller.dart';

/// The ONE Destination Detail card used by every location in ExplorerOS —
/// parks, lakes, rivers, cities, museums, trails, springs, restaurants, etc.
/// Tapping any location opens this (it never auto-plays). Buttons enable/disable
/// automatically based on the data present, so adding a location in the admin
/// populates this interface with no extra code.
Future<void> showDestinationDetail(
  BuildContext context,
  MasterLocation location, {
  double? distanceMeters,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DestinationDetailCard(
      location: location,
      distanceMeters: distanceMeters,
    ),
  );
}

class _Palette {
  static const bg = Color(0xFF121915);
  static const card = Color(0xFF1B2620);
  static const green = Color(0xFF2E9E6B);
  static const text = Color(0xFFF3F6F2);
  static const dim = Color(0xFF9CA8A1);
}

String _miles(double meters) {
  final mi = meters / 1609.344;
  return mi < 10 ? '${mi.toStringAsFixed(1)} mi' : '${mi.round()} mi';
}

class DestinationDetailCard extends ConsumerWidget {
  const DestinationDetailCard({
    super.key,
    required this.location,
    this.distanceMeters,
  });

  final MasterLocation location;
  final double? distanceMeters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = location;
    final favorites = ref.watch(locationFavoritesProvider);
    final isFav = favorites.contains(l.id);
    final hasPhotos = l.images.isNotEmpty;
    final hasNarration = l.hasNarration;
    final canNavigate = l.hasCoordinates;
    final hero = l.images.isNotEmpty ? l.images.first : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: _Palette.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.zero,
          children: [
            // Hero image + close.
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  child: SizedBox(
                    height: 210,
                    width: double.infinity,
                    child: hero != null
                        ? Image.network(hero, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _heroFallback())
                        : _heroFallback(),
                  ),
                ),
                Positioned(
                  top: 10, right: 10,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                Positioned(
                  left: 16, bottom: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _Palette.green,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(l.type.label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.name,
                      style: const TextStyle(
                          color: _Palette.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (distanceMeters != null) _miles(distanceMeters!),
                      l.placeLine,
                    ].whereType<String>().join(' · '),
                    style: const TextStyle(color: _Palette.dim, fontSize: 13),
                  ),
                  if ((l.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(l.description!.trim(),
                        style: const TextStyle(
                            color: _Palette.text, fontSize: 14, height: 1.4)),
                  ],
                  const SizedBox(height: 20),
                  // Primary action: Listen.
                  _PrimaryButton(
                    icon: Icons.play_arrow_rounded,
                    label: hasNarration ? 'Listen to Story' : 'Story coming soon',
                    enabled: hasNarration,
                    onTap: () => _listen(context, ref),
                  ),
                  const SizedBox(height: 12),
                  // Secondary actions — auto shown/enabled by available data.
                  Row(children: [
                    Expanded(
                      child: _ActionChip(
                        icon: Icons.navigation_rounded,
                        label: 'Navigate',
                        enabled: canNavigate,
                        onTap: () => _navigate(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionChip(
                        icon: isFav
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: isFav ? 'Saved' : 'Save',
                        highlight: isFav,
                        onTap: () => ref
                            .read(locationFavoritesProvider.notifier)
                            .toggle(l.id),
                      ),
                    ),
                    if (hasPhotos) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionChip(
                          icon: Icons.photo_library_rounded,
                          label: 'Photos',
                          onTap: () => _openGallery(context),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 12),
                  _ActionChip(
                    icon: Icons.info_outline_rounded,
                    label: 'More Information',
                    fullWidth: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _MoreInfoPage(location: l),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroFallback() => Container(
        color: _Palette.card,
        child: const Center(
            child: Icon(Icons.place_rounded, size: 56, color: _Palette.green)),
      );

  void _listen(BuildContext context, WidgetRef ref) {
    ref
        .read(nearbyNarrationControllerProvider.notifier)
        .narrateLocation(location);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playing ${location.name} on Explorer Radio')),
    );
  }

  Future<void> _navigate(BuildContext context) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query='
        '${location.latitude},${location.longitude}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open navigation')));
    }
  }

  void _openGallery(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _PhotoGallery(images: location.images, title: location.name),
    ));
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: enabled ? onTap : null,
        style: FilledButton.styleFrom(
          backgroundColor: _Palette.green,
          disabledBackgroundColor: _Palette.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, size: 22),
        label: Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.highlight = false,
    this.fullWidth = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool highlight;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? _Palette.green : _Palette.text;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen swipeable photo gallery.
class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({required this.images, required this.title});
  final List<String> images;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            child: Image.network(images[i], fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image_rounded,
                    color: Colors.white38, size: 64)),
          ),
        ),
      ),
    );
  }
}

/// Detailed information page — renders the sections that have data (nearby,
/// related, description). More fields appear automatically as they're added.
class _MoreInfoPage extends ConsumerWidget {
  const _MoreInfoPage({required this.location});
  final MasterLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(masterLocationsProvider).value ?? const [];
    final engine = ref.watch(locationEngineProvider);
    final nearby = (location.hasCoordinates)
        ? engine
            .nearby(location.latitude!, location.longitude!, all, maxMiles: 20)
            .where((n) => n.location.id != location.id)
            .take(8)
            .toList()
        : const [];

    return Scaffold(
      backgroundColor: _Palette.bg,
      appBar: AppBar(
        backgroundColor: _Palette.bg,
        foregroundColor: _Palette.text,
        title: Text(location.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(location.type.label,
              style: const TextStyle(
                  color: _Palette.green, fontWeight: FontWeight.w700)),
          if ((location.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _section('About'),
            Text(location.description!.trim(),
                style: const TextStyle(
                    color: _Palette.text, height: 1.45, fontSize: 14)),
          ],
          if (location.placeLine != null) ...[
            const SizedBox(height: 16),
            _section('Where'),
            Text(location.placeLine!,
                style: const TextStyle(color: _Palette.text, fontSize: 14)),
          ],
          if (nearby.isNotEmpty) ...[
            const SizedBox(height: 20),
            _section('Nearby Destinations'),
            for (final n in nearby)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_rounded, color: _Palette.green),
                title: Text(n.location.name,
                    style: const TextStyle(color: _Palette.text)),
                subtitle: Text(
                    '${n.location.type.label} · ${_miles(n.distanceMeters)}',
                    style: const TextStyle(color: _Palette.dim, fontSize: 12)),
                onTap: () {
                  Navigator.of(context).pop();
                  showDestinationDetail(context, n.location,
                      distanceMeters: n.distanceMeters);
                },
              ),
          ],
          const SizedBox(height: 24),
          Text(
            'History, wildlife, plants, activities, accessibility, hours, fees '
            'and tips appear here as they are added for this location.',
            style: const TextStyle(color: _Palette.dim, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: const TextStyle(
                color: _Palette.text,
                fontSize: 16,
                fontWeight: FontWeight.w800)),
      );
}
