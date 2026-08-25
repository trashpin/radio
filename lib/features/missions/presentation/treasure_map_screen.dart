import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/controllers/mission_audio_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/game_guide_repository.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_character.dart';
import 'package:explorer_os_mobile/features/missions/models/treasure_discovery.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_narration_service.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// STAGE 2 of arrival — GPS already got the player to
/// [MissionStop.arrivalRadiusMeters] (STAGE 1: the existing JourneyMap/
/// route system, completely unchanged). This screen is what happens next,
/// reached only when the current stop has a [TreasureDiscovery]
/// configured: a stylized map + written clue + a progressive hint ladder
/// that makes the player physically look around instead of walking to a
/// GPS pin, before they reach the EXISTING QR scanner
/// ([AppRoute.qrScan]) — unchanged, including its own "Simulate Discovery"
/// dev-mode action and its own wrong-QR handling. No new QR/GPS/geofence
/// system exists here; this is purely a presentational stage in between.
class TreasureMapScreen extends ConsumerStatefulWidget {
  const TreasureMapScreen({super.key});

  @override
  ConsumerState<TreasureMapScreen> createState() => _TreasureMapScreenState();
}

class _TreasureMapScreenState extends ConsumerState<TreasureMapScreen> {
  int _hintsShown = 0;

  Future<void> _requestHint(TreasureDiscovery discovery) async {
    final available = [
      if (discovery.hasHint1) discovery.hint1Text!,
      if (discovery.hasHint2) discovery.hint2Text!,
      if (discovery.hasFinalHint) discovery.finalHintText!,
    ];
    if (_hintsShown >= available.length) return;
    final level = _hintsShown;
    setState(() => _hintsShown++);
    ref.read(activeMissionControllerProvider.notifier).useHint();

    // Guide presentation only (spec: "The Guide should also support
    // physical treasure-hunt hints") — the hint ladder/XP logic above is
    // completely unchanged, this just speaks the new hint through the
    // Guide's own voice, same as every other Guide-delivered hint.
    final guide = await ref.read(activeGuideCharacterProvider.future);
    final text = available[level];
    final result = await ref.read(missionNarrationServiceProvider).requestFor(
          subjectId: 'hint:treasure:${discovery.id}:$level',
          kind: 'guide',
          subjectType: 'guide',
          text: text,
          voiceId: guide?.voiceId,
        );
    await ref.read(missionAudioControllerProvider.notifier).play(
          title: guide?.name ?? 'The Guide',
          audioUrl: result?.audioUrl,
          spokenText: text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final stop = ref.watch(activeMissionControllerProvider).currentStop;
    final discoveryId = stop?.treasureDiscoveryId;
    final discoveryAsync = discoveryId == null
        ? null
        : ref.watch(treasureDiscoveryByIdProvider(discoveryId));
    final guide = ref.watch(activeGuideCharacterProvider).value;

    return Scaffold(
      backgroundColor: const Color(0xFF241B0F), // aged-paper-adjacent dark tone
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Your Next Discovery'),
      ),
      body: SafeArea(
        child: discoveryAsync == null
            ? const _NoDiscoveryFallback()
            : discoveryAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: RD.amber)),
                error: (e, _) => const _NoDiscoveryFallback(),
                data: (discovery) => discovery == null
                    ? const _NoDiscoveryFallback()
                    : _TreasureMapContent(
                        discovery: discovery,
                        hintsShown: _hintsShown,
                        onRequestHint: () => _requestHint(discovery),
                        guide: guide,
                      ),
              ),
      ),
    );
  }
}

/// Reached only if this route is somehow opened with no treasure discovery
/// configured for the current stop — falls back straight to the existing
/// QR scanner, exactly the pre-treasure-hunt behavior, rather than
/// stranding the player on an empty screen.
class _NoDiscoveryFallback extends StatelessWidget {
  const _NoDiscoveryFallback();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.pushReplacement(AppRoute.qrScan.path);
    });
    return const Center(child: CircularProgressIndicator(color: RD.amber));
  }
}

class _TreasureMapContent extends StatelessWidget {
  const _TreasureMapContent({
    required this.discovery,
    required this.hintsShown,
    required this.onRequestHint,
    this.guide,
  });
  final TreasureDiscovery discovery;
  final int hintsShown;
  final VoidCallback onRequestHint;
  final MissionCharacter? guide;

  @override
  Widget build(BuildContext context) {
    final hints = [
      if (discovery.hasHint1) discovery.hint1Text!,
      if (discovery.hasHint2) discovery.hint2Text!,
      if (discovery.hasFinalHint) discovery.finalHintText!,
    ];

    return ListView(
      padding: const EdgeInsets.all(RD.lg),
      children: [
        if ((discovery.difficulty ?? '').isNotEmpty) ...[
          _difficultyPill(discovery.difficulty!),
          const SizedBox(height: RD.sm),
        ],
        Text('Now the real search begins.',
            style: RD.body.copyWith(color: Colors.white70, fontSize: 14, fontStyle: FontStyle.italic)),
        const SizedBox(height: RD.lg),

        // The map — mystery artwork of the real area, never a GPS pin on
        // the exact QR spot.
        ClipRRect(
          borderRadius: RD.brLg,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: discovery.hasMapImage
                ? Image.network(discovery.treasureMapImageUrl!, fit: BoxFit.cover)
                : const _TreasureMapPlaceholder(),
          ),
        ),

        if ((discovery.clueText ?? '').isNotEmpty) ...[
          const SizedBox(height: RD.lg),
          GlassPanel(
            color: Colors.black.withValues(alpha: 0.35),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.map_outlined, color: RD.amber, size: 18),
                  const SizedBox(width: RD.xs),
                  Text('YOUR CLUE', style: RD.sectionLabel.copyWith(color: RD.amber)),
                ]),
                const SizedBox(height: RD.xs),
                Text(discovery.clueText!,
                    style: RD.body.copyWith(color: Colors.white, fontSize: 15, height: 1.5)),
              ],
            ),
          ),
        ],

        if (discovery.searchAreaMeters != null) ...[
          const SizedBox(height: RD.sm),
          Text(
            'Somewhere within about ${_friendlyDistance(discovery.searchAreaMeters!)} of here.',
            style: RD.caption.copyWith(color: Colors.white54),
          ),
        ],

        if (hintsShown > 0) ...[
          const SizedBox(height: RD.md),
          Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: RD.panelAlt,
              backgroundImage:
                  (guide?.imageUrl ?? '').isNotEmpty ? NetworkImage(guide!.imageUrl!) : null,
              child: (guide?.imageUrl ?? '').isEmpty
                  ? const Icon(Icons.person_rounded, color: RD.textSecondary, size: 16)
                  : null,
            ),
            const SizedBox(width: RD.sm),
            Text(guide?.name ?? 'The Guide',
                style: RD.cardTitle.copyWith(color: Colors.white, fontSize: 14)),
          ]),
        ],
        for (var i = 0; i < hintsShown; i++) ...[
          const SizedBox(height: RD.sm),
          GlassPanel(
            color: Colors.black.withValues(alpha: 0.25),
            child: Row(children: [
              const Icon(Icons.lightbulb_outline_rounded, color: RD.amber, size: 18),
              const SizedBox(width: RD.xs),
              Expanded(
                child: Text(hints[i], style: RD.body.copyWith(color: Colors.white70, fontSize: 14)),
              ),
            ]),
          ),
        ],

        if (hintsShown < hints.length) ...[
          const SizedBox(height: RD.md),
          OutlinedButton.icon(
            onPressed: onRequestHint,
            style: OutlinedButton.styleFrom(
              foregroundColor: RD.amber,
              side: const BorderSide(color: RD.amber),
              minimumSize: const Size(double.infinity, 44),
            ),
            icon: const Text('🧭'),
            label: Text(hintsShown == 0 ? 'Ask the Guide' : 'Stronger Hint'),
          ),
        ],

        const SizedBox(height: RD.xl),
        Text(
          'Stay on marked trails. Do not enter restricted areas or cross unsafe terrain.',
          textAlign: TextAlign.center,
          style: RD.caption.copyWith(color: Colors.white38),
        ),
        const SizedBox(height: RD.md),

        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RD.amber, foregroundColor: Colors.black),
            onPressed: () => context.push(AppRoute.qrScan.path),
            child: const Text("I Found It — Scan QR", style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _difficultyPill(String difficulty) => Container(
        padding: const EdgeInsets.symmetric(horizontal: RD.sm, vertical: 4),
        decoration: BoxDecoration(
          color: RD.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(RD.rPill),
          border: Border.all(color: RD.amber.withValues(alpha: 0.5)),
        ),
        child: Text(difficulty.toUpperCase(), style: RD.badge.copyWith(color: RD.amber)),
      );

  String _friendlyDistance(double meters) {
    final feet = meters * 3.28084;
    if (feet < 1000) return '${feet.round()} feet';
    return '${(meters / 1609.344).toStringAsFixed(1)} miles';
  }
}

/// Shown when no [TreasureDiscovery.treasureMapImageUrl] has been set yet
/// — a styled aged-paper/compass motif rather than a blank box, so the
/// stage still feels like part of the game before real art exists.
class _TreasureMapPlaceholder extends StatelessWidget {
  const _TreasureMapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.brown.shade700, Colors.brown.shade900],
        ),
        border: Border.all(color: RD.amber.withValues(alpha: 0.4), width: 2),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 48, color: RD.amber),
            SizedBox(height: RD.sm),
            Text('X MARKS THE SPOT',
                style: TextStyle(
                    color: RD.amber, fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
