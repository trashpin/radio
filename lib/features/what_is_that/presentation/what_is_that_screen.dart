import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';
import 'package:explorer_os_mobile/features/what_is_that/models/what_is_that_candidate.dart';
import 'package:explorer_os_mobile/features/what_is_that/providers/what_is_that_providers.dart';

/// "What Is That?" — point your phone in a direction and see what's out
/// there. Deliberately a COMPLETELY SEPARATE, isolated screen (own route,
/// own providers, own pure search function): Explore only ever gets a single
/// entry-point button to it (see `radio_screen.dart`'s `_ExploreBanner`
/// block). Reuses, without modifying: GPS position from the existing
/// `gpsControllerProvider`, the existing directional cone search
/// (`UpcomingDestinationService`, via `findWhatIsThatCandidates`), the
/// existing DJ Sunny narration entry point (`requestInterruption`), and the
/// existing Tell Me More screen/route. The only genuinely new piece is a
/// compass (magnetometer) heading source, scoped entirely to this feature.
class WhatIsThatScreen extends ConsumerStatefulWidget {
  const WhatIsThatScreen({super.key});

  @override
  ConsumerState<WhatIsThatScreen> createState() => _WhatIsThatScreenState();
}

class _WhatIsThatScreenState extends ConsumerState<WhatIsThatScreen> {
  @override
  void initState() {
    super.initState();
    // The compass heading (and therefore the search cone) is only meaningful
    // relative to a fixed physical edge of the phone. Locking to portrait
    // while this screen is open guarantees "the direction the TOP of the
    // phone is pointing" always means the same physical edge, regardless of
    // how the rest of the app allows rotation — restored on dispose.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  TellMeMoreContext _tellMeMoreContextFor(WhatIsThatCandidate c) =>
      TellMeMoreContext(
        subject: c.name,
        locationId: c.locationId,
        contextKind: 'attraction',
        location: GeoPoint(latitude: c.latitude, longitude: c.longitude),
        distanceLabel: c.distanceLabel,
      );

  void _tellDjSunny(WidgetRef ref, WhatIsThatCandidate c) {
    final text = (c.description ?? '').trim();
    final radio = ref.read(radioEngineControllerProvider.notifier);
    radio.requestInterruption(
      AudioSegment(
        id: 'whatisthat:${c.locationId}:'
            '${DateTime.now().microsecondsSinceEpoch}',
        title: c.name,
        artist: 'DJ Sunny',
        type: AudioSegmentType.gpsNarration,
        priority: PlaybackPriority.scheduledAnnouncement,
        imageUrl: c.imageUrl,
        audioUrl: c.hasAudio ? c.audioUrl : null,
        spokenText:
            c.hasAudio ? null : (text.isNotEmpty ? text : "That's ${c.name}."),
        location: GeoPoint(latitude: c.latitude, longitude: c.longitude),
        tags: const ['what_is_that'],
        interruptible: true,
        resumeAfter: true,
        tellMeMoreContext: _tellMeMoreContextFor(c),
      ),
    );
    // requestInterruption only PLAYS immediately if something is already
    // playing (it interrupts the current segment); when the radio is idle it
    // just queues the segment silently. Same fix NearbyNarrationController
    // already applies for "What's Near Me" — kick playback explicitly so
    // tapping the button is never a silent no-op.
    if (ref.read(radioEngineControllerProvider).status !=
        PlaybackStatus.playing) {
      radio.play();
    }
  }

  Future<void> _navigate(WhatIsThatCandidate c) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${c.latitude},${c.longitude}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final travel = ref.watch(gpsControllerProvider);
    final hasFix = travel.location != null;
    final heading = ref.watch(whatIsThatHeadingProvider);
    final usingCompass = ref.watch(whatIsThatUsingCompassProvider);
    final candidates = ref.watch(whatIsThatCandidatesProvider);

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(onBack: () => context.pop()),
            Expanded(
              child: !hasFix
                  ? const _StatusMessage(
                      text: "Waiting for a GPS fix so we know where you "
                          "are…")
                  : heading == null
                      ? const _StatusMessage(
                          text: "Waiting for a heading — walk a few steps, "
                              "or give the compass a moment to calibrate.")
                      : _Body(
                          heading: heading,
                          usingCompass: usingCompass,
                          candidates: candidates,
                          onTellDjSunny: (c) => _tellDjSunny(ref, c),
                          onTellMeMore: (c) => context.push(
                              AppRoute.tellMeMore.path,
                              extra: _tellMeMoreContextFor(c)),
                          onNavigate: _navigate,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(RD.sm, RD.sm, RD.md, RD.sm),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, color: RD.greenBright),
            label: Text(
              'BACK TO EXPLORE',
              style: RD.badge.copyWith(
                color: RD.greenBright,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Spacer(),
          Text(
            "WHAT IS THAT?",
            style:
                RD.badge.copyWith(color: RD.textSecondary, letterSpacing: 1.4),
          ),
        ],
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_outlined,
                size: 56, color: RD.textSecondary),
            const SizedBox(height: RD.md),
            Text(
              text,
              textAlign: TextAlign.center,
              style: RD.body.copyWith(color: RD.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({
    required this.heading,
    required this.usingCompass,
    required this.candidates,
    required this.onTellDjSunny,
    required this.onTellMeMore,
    required this.onNavigate,
  });

  final double heading;
  final bool usingCompass;
  final List<WhatIsThatCandidate> candidates;
  final void Function(WhatIsThatCandidate) onTellDjSunny;
  final void Function(WhatIsThatCandidate) onTellMeMore;
  final void Function(WhatIsThatCandidate) onNavigate;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final candidates = widget.candidates;
    final selected = candidates.isEmpty
        ? null
        : candidates.firstWhere(
            (c) => c.id == _selectedId,
            orElse: () => candidates.first,
          );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: RD.lg, vertical: RD.md),
      children: [
        _CompassDial(
          heading: widget.heading,
          usingCompass: widget.usingCompass,
        ),
        const SizedBox(height: RD.lg),
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: RD.xl),
            child: Text(
              "Nothing known is in that direction within about 5 miles. "
              "Try turning a little.",
              textAlign: TextAlign.center,
              style: RD.body.copyWith(color: RD.textSecondary),
            ),
          )
        else ...[
          Text(
            candidates.length == 1
                ? "1 place that way"
                : "${candidates.length} places that way",
            style: RD.badge
                .copyWith(color: RD.textSecondary, letterSpacing: 1.1),
          ),
          const SizedBox(height: RD.sm),
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: candidates.length,
              separatorBuilder: (_, _) => const SizedBox(width: RD.sm),
              itemBuilder: (context, i) {
                final c = candidates[i];
                return _CandidateChip(
                  candidate: c,
                  selected: c.id == selected?.id,
                  onTap: () => setState(() => _selectedId = c.id),
                );
              },
            ),
          ),
          const SizedBox(height: RD.lg),
          if (selected != null)
            _CandidateDetail(
              candidate: selected,
              onTellDjSunny: () => widget.onTellDjSunny(selected),
              onTellMeMore: () => widget.onTellMeMore(selected),
              onNavigate: () => widget.onNavigate(selected),
            ),
        ],
      ],
    );
  }
}

class _CompassDial extends StatelessWidget {
  const _CompassDial({required this.heading, required this.usingCompass});
  final double heading;
  final bool usingCompass;

  static const _shortLabel = {
    CardinalDirection.north: 'N',
    CardinalDirection.northEast: 'NE',
    CardinalDirection.east: 'E',
    CardinalDirection.southEast: 'SE',
    CardinalDirection.south: 'S',
    CardinalDirection.southWest: 'SW',
    CardinalDirection.west: 'W',
    CardinalDirection.northWest: 'NW',
  };

  @override
  Widget build(BuildContext context) {
    final cardinal = _shortLabel[CardinalDirection.fromBearing(heading)] ?? '';
    return Column(
      children: [
        // Deliberately FIXED, always pointing straight up — this represents
        // the top of the phone itself (the direction "What Is That?" always
        // searches), never rotated. Rotating it to point at magnetic/true
        // north (a compass-needle metaphor) was confusing: it made the arrow
        // look like it was pointing somewhere OTHER than where the phone's
        // top edge — and therefore the search — was actually aimed.
        const SizedBox(
          width: 96,
          height: 96,
          child: Icon(Icons.arrow_upward_rounded,
              size: 72, color: RD.greenBright),
        ),
        const SizedBox(height: RD.xs),
        Text(
          '${heading.round()}° $cardinal',
          style: RD.title.copyWith(color: Colors.white),
        ),
        Text(
          usingCompass
              ? 'top of phone — compass heading'
              : 'top of phone — based on your direction of travel',
          style: RD.caption.copyWith(color: RD.textSecondary),
        ),
      ],
    );
  }
}

class _CandidateChip extends StatelessWidget {
  const _CandidateChip({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });
  final WhatIsThatCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(RD.xs),
        decoration: BoxDecoration(
          color: RD.panel,
          borderRadius: BorderRadius.circular(RD.rMd),
          border: Border.all(
            color: selected ? RD.greenBright : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(RD.rSm),
                child: (candidate.imageUrl ?? '').isNotEmpty
                    ? Image.network(candidate.imageUrl!,
                        fit: BoxFit.cover, width: double.infinity)
                    : Container(
                        color: RD.bgElevated,
                        alignment: Alignment.center,
                        child: const Icon(Icons.place_rounded,
                            color: RD.textSecondary),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(candidate.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RD.caption.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            Text(candidate.distanceLabel,
                style: RD.caption.copyWith(color: RD.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _CandidateDetail extends StatelessWidget {
  const _CandidateDetail({
    required this.candidate,
    required this.onTellDjSunny,
    required this.onTellMeMore,
    required this.onNavigate,
  });
  final WhatIsThatCandidate candidate;
  final VoidCallback onTellDjSunny;
  final VoidCallback onTellMeMore;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: RD.panel,
        borderRadius: BorderRadius.circular(RD.rLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((candidate.imageUrl ?? '').isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(candidate.imageUrl!, fit: BoxFit.cover),
            ),
          Padding(
            padding: const EdgeInsets.all(RD.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidate.name,
                    style: RD.title.copyWith(color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  [
                    if ((candidate.typeLabel ?? '').isNotEmpty)
                      candidate.typeLabel,
                    candidate.distanceLabel,
                  ].whereType<String>().join('  ·  '),
                  style: RD.caption.copyWith(color: RD.textSecondary),
                ),
                if ((candidate.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: RD.sm),
                  Text(candidate.description!,
                      style: RD.body.copyWith(color: RD.textPrimary)),
                ],
                const SizedBox(height: RD.md),
                Wrap(
                  spacing: RD.sm,
                  runSpacing: RD.sm,
                  children: [
                    FilledButton.icon(
                      onPressed: onTellDjSunny,
                      icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                      label: const Text('DJ Sunny, tell me'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onTellMeMore,
                      icon: const Icon(Icons.info_outline_rounded, size: 18),
                      label: const Text('Tell Me More'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onNavigate,
                      icon: const Icon(Icons.directions_rounded, size: 18),
                      label: const Text('Navigate'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
