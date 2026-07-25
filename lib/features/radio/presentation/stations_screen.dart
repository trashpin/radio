import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_session_provider.dart';
import 'package:explorer_os_mobile/features/radio/providers/stations_provider.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';

/// The station selector — a grid of station cards (Country, Rock, Top Hits,
/// Kids). Loaded dynamically from Supabase with a curated fallback. Tapping a
/// card selects it and returns to the player tuned to that station.
class StationsScreen extends ConsumerWidget {
  const StationsScreen({super.key});

  static const Color _bg = Color(0xFF0C120F);
  static const Color _accent = Color(0xFFEE7B2E);
  static const Color _textPrimary = Color(0xFFF3F6F2);
  static const Color _textSecondary = Color(0xFF9AA6A0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(radioStationCatalogProvider);
    final selected = ref.watch(selectedStationProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _textPrimary,
        title: const Text('Stations',
            style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _accent)),
        error: (e, _) => Center(
          child: Text('Could not load stations.\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textSecondary)),
        ),
        data: (stations) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: GridView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisSpacing: AppSpacing.lg,
                crossAxisSpacing: AppSpacing.lg,
                childAspectRatio: 0.82,
              ),
              itemCount: stations.length,
              itemBuilder: (context, i) {
                final station = stations[i];
                return _StationCard(
                  station: station,
                  active: selected?.id == station.id,
                  onTap: () {
                    ref
                        .read(selectedStationProvider.notifier)
                        .select(station);
                    // Rebuild the session for the new station, then return.
                    ref.invalidate(radioSessionProvider);
                    Navigator.of(context).maybePop();
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.station,
    required this.active,
    required this.onTap,
  });

  final RadioStation station;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = styleFor(station);
    final hasImage = station.imageUrl != null && station.imageUrl!.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.lgAll,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(
              color: active ? style.accent : Colors.transparent,
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                Image.network(station.imageUrl!, fit: BoxFit.cover)
              else
                ColoredBox(color: style.accent.withValues(alpha: 0.4)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xE60C120F)],
                    stops: [0.35, 1],
                  ),
                ),
              ),
              // Genre chip (top-left)
              Positioned(
                top: AppSpacing.sm,
                left: AppSpacing.sm,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: style.accent,
                    borderRadius: AppRadius.pillAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(style.icon, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text(style.genre,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              if (active)
                const Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: Icon(Icons.graphic_eq_rounded,
                      color: Colors.white, size: 18),
                ),
              // Name + play (bottom)
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(station.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1)),
                          if (station.description != null) ...[
                            const SizedBox(height: 2),
                            Text(station.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.85),
                                    fontSize: 11)),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: style.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(active ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
