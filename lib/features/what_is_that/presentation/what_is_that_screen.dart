import 'dart:async';

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
import 'package:explorer_os_mobile/features/what_is_that/data/what_is_that_narration_repository.dart';
import 'package:explorer_os_mobile/features/what_is_that/models/what_is_that_candidate.dart';
import 'package:explorer_os_mobile/features/what_is_that/models/what_is_that_topic.dart';
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

/// The three phases of the "look around, then commit" flow — spec:
/// "Do NOT play narration while the user is simply looking around" and
/// only identify/narrate once the ↑ button is pressed. `scanning` is a pure,
/// continuously-updating live view of whatever `whatIsThatCandidatesProvider`
/// currently returns for the phone's current heading (never queries a
/// photo, never plays audio); pressing ↑ freezes that provider's CURRENT
/// result into `_lockedCandidates` and moves to `chooser` (when there's a
/// real choice to make) or straight to `detail` (when there's only one).
enum _Phase { scanning, chooser, detail }

class _Body extends ConsumerStatefulWidget {
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
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  _Phase _phase = _Phase.scanning;
  List<WhatIsThatCandidate> _lockedCandidates = const [];
  String? _selectedId;

  /// Cached Google Places photos, keyed by `locationId` — populated by a
  /// cheap read of our own cache table (never a live Places call from this
  /// screen), and only once the user has actually pressed ↑ — spec: "Only
  /// request a photo if reasonable non-photo identification methods cannot
  /// determine the target," so nothing photo-related is looked up while
  /// merely scanning around.
  Map<String, String?> _cachedPhotos = const {};
  final Set<String> _photoRequestsSent = {};

  Future<void> _loadPhotos(List<WhatIsThatCandidate> candidates) async {
    final repo = ref.read(whatIsThatNarrationRepositoryProvider);
    final needLookup = candidates
        .where((c) => (c.imageUrl ?? '').trim().isEmpty)
        .map((c) => c.locationId)
        .toList();
    if (needLookup.isEmpty) return;

    final photos = await repo.cachedPhotosFor(needLookup);
    if (mounted) setState(() => _cachedPhotos = {..._cachedPhotos, ...photos});

    // Opportunistically ask the worker to cache a photo for anything STILL
    // missing one — fire-and-forget, never awaited/polled, never blocks this
    // screen. Purely improves things the NEXT time this place comes up.
    for (final c in candidates) {
      if ((c.imageUrl ?? '').trim().isNotEmpty) continue;
      if ((photos[c.locationId] ?? '').trim().isNotEmpty) continue;
      if (!_photoRequestsSent.add(c.locationId)) continue;
      unawaited(repo.enqueuePhotoOnly(c.locationId));
    }
  }

  /// Our own database image first; a cached Google Places photo only when we
  /// have nothing of our own. Never blocks on a fresh Places call.
  String? _imageFor(WhatIsThatCandidate c) {
    final own = c.imageUrl;
    if (own != null && own.trim().isNotEmpty) return own;
    final cached = _cachedPhotos[c.locationId];
    return (cached != null && cached.trim().isNotEmpty) ? cached : null;
  }

  /// The ↑ button — spec: "Lock the current compass direction. Determine
  /// the best matching place/feature. ... If multiple strong candidates
  /// exist ... show the user the relevant choices."
  void _onConfirm() {
    final candidates = widget.candidates;
    setState(() {
      _lockedCandidates = candidates;
      _selectedId = candidates.isNotEmpty ? candidates.first.id : null;
      _phase = candidates.length > 1 ? _Phase.chooser : _Phase.detail;
    });
    if (candidates.isNotEmpty) unawaited(_loadPhotos(candidates));
  }

  void _onPick(String id) => setState(() {
        _selectedId = id;
        _phase = _Phase.detail;
      });

  void _onScanAgain() => setState(() {
        _phase = _Phase.scanning;
        _lockedCandidates = const [];
        _selectedId = null;
      });

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.scanning:
        return _ScanningView(
          heading: widget.heading,
          usingCompass: widget.usingCompass,
          candidates: widget.candidates,
          onConfirm: _onConfirm,
        );
      case _Phase.chooser:
        return _ChooserView(
          candidates: _lockedCandidates,
          imageFor: _imageFor,
          onPick: _onPick,
          onScanAgain: _onScanAgain,
        );
      case _Phase.detail:
        final selected = _lockedCandidates.isEmpty
            ? null
            : _lockedCandidates.firstWhere(
                (c) => c.id == _selectedId,
                orElse: () => _lockedCandidates.first,
              );
        if (selected == null) {
          return _ChooserView(
            candidates: const [],
            imageFor: _imageFor,
            onPick: _onPick,
            onScanAgain: _onScanAgain,
          );
        }
        return SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: RD.lg, vertical: RD.md),
          child: _CandidateDetail(
            key: ValueKey(selected.id),
            candidate: selected,
            imageUrl: _imageFor(selected),
            onTellDjSunny: () => widget.onTellDjSunny(selected),
            onTellMeMore: () => widget.onTellMeMore(selected),
            onNavigate: () => widget.onNavigate(selected),
            onScanAgain: _onScanAgain,
            onChooseDifferent: _lockedCandidates.length > 1
                ? () => setState(() => _phase = _Phase.chooser)
                : null,
          ),
        );
    }
  }
}

/// Live "look around" view — spec: a discovery/search screen that feels
/// active while the user rotates the phone, showing up to 3 results in the
/// direction the top of the phone currently points, with NO narration and
/// no photo lookups. Just the same `whatIsThatCandidatesProvider` result
/// already computed for the compass dial, read straight through with zero
/// extra state.
class _ScanningView extends StatelessWidget {
  const _ScanningView({
    required this.heading,
    required this.usingCompass,
    required this.candidates,
    required this.onConfirm,
  });
  final double heading;
  final bool usingCompass;
  final List<WhatIsThatCandidate> candidates;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: RD.sm),
        _CompassDial(heading: heading, usingCompass: usingCompass),
        const SizedBox(height: RD.sm),
        const _LiveSearchingBadge(),
        Expanded(
          child: candidates.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(RD.xl),
                    child: Text(
                      "Nothing known yet in that direction — keep rotating.",
                      textAlign: TextAlign.center,
                      style: RD.body.copyWith(color: RD.textSecondary),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: RD.lg, vertical: RD.md),
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final c in candidates) _ScanResultRow(candidate: c),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: RD.xl),
          child: Column(
            children: [
              _ConfirmArrowButton(onTap: onConfirm),
              const SizedBox(height: RD.sm),
              Text("WHAT'S THERE?",
                  style: RD.badge
                      .copyWith(color: RD.textSecondary, letterSpacing: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

/// A small pulsing dot + label — spec: "The status should remain visible
/// while the system is updating the directional results... The screen
/// should feel active and responsive rather than looking like a static
/// information page." Reuses the app's existing "equalizer" pulse timing
/// ([RD.eq]) rather than inventing a new animation rhythm.
class _LiveSearchingBadge extends StatefulWidget {
  const _LiveSearchingBadge();

  @override
  State<_LiveSearchingBadge> createState() => _LiveSearchingBadgeState();
}

class _LiveSearchingBadgeState extends State<_LiveSearchingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: RD.eq)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: Tween<double>(begin: 0.25, end: 1.0).animate(_controller),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: RD.greenBright,
            ),
          ),
        ),
        const SizedBox(width: RD.sm),
        Text('SEARCHING AROUND YOU...',
            style:
                RD.badge.copyWith(color: RD.textSecondary, letterSpacing: 1.1)),
      ],
    );
  }
}

/// One live-scan result row — spec: "Category icon, Place/location name,
/// Distance, Optional short description when useful." Purely informational
/// (not tappable) while scanning — the user commits with the ↑ button, per
/// the identification flow, not by tapping a row here.
class _ScanResultRow extends StatelessWidget {
  const _ScanResultRow({required this.candidate});
  final WhatIsThatCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final description = (candidate.description ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RD.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CategoryBadge(icon: _categoryIconFor(candidate), size: 36),
          const SizedBox(width: RD.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidate.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RD.cardTitle.copyWith(color: Colors.white)),
                Text(
                  [
                    candidate.distanceLabel,
                    if (description.isNotEmpty) description,
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RD.caption.copyWith(color: RD.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small circular icon badge — spec: "The icon should be visually
/// secondary to the location name" (small + muted) and "Do not make the
/// screen overly colorful." Every category icon renders in the SAME single
/// accent color; only the glyph itself varies by category, so recognition
/// comes from shape, not from a rainbow of colors.
class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.icon, this.size = 36});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: RD.bgElevated,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: RD.greenBright),
    );
  }
}

/// A consistent, professional category icon for [c] — spec section 3: one
/// recognizable icon per category family (water, park/nature, building,
/// history, museum, town/community, attraction, event, wildlife), used the
/// same everywhere in this feature (the live scan rows, the chooser cards'
/// no-photo fallback, and the selected-place detail). Purely cosmetic —
/// never affects identification or ranking, which stay driven entirely by
/// [WhatIsThatCandidate.typeLabel] from the existing database, unchanged.
IconData _categoryIconFor(WhatIsThatCandidate c) {
  final t = (c.typeLabel ?? '').toLowerCase();
  const rules = <MapEntry<String, IconData>>[
    // Most specific first.
    MapEntry('museum', Icons.museum_rounded),
    MapEntry('historic', Icons.account_balance_rounded),
    MapEntry('monument', Icons.account_balance_rounded),
    MapEntry('memorial', Icons.account_balance_rounded),
    MapEntry('event', Icons.event_rounded),
    MapEntry('festival', Icons.event_rounded),
    MapEntry('wildlife', Icons.pets_rounded),
    MapEntry('attraction', Icons.attractions_rounded),
    MapEntry('hidden gem', Icons.attractions_rounded),
    MapEntry('lake', Icons.water_rounded),
    MapEntry('river', Icons.water_rounded),
    MapEntry('spring', Icons.water_rounded),
    MapEntry('waterfall', Icons.water_rounded),
    MapEntry('boat ramp', Icons.water_rounded),
    MapEntry('beach', Icons.beach_access_rounded),
    MapEntry('forest', Icons.park_rounded),
    MapEntry('park', Icons.park_rounded),
    MapEntry('trail', Icons.park_rounded),
    MapEntry('scenic', Icons.landscape_rounded),
    MapEntry('cave', Icons.landscape_rounded),
    MapEntry('campground', Icons.park_rounded),
    MapEntry('town', Icons.location_city_rounded),
    MapEntry('village', Icons.location_city_rounded),
    MapEntry('community', Icons.location_city_rounded),
    MapEntry('lighthouse', Icons.apartment_rounded),
    MapEntry('bridge', Icons.apartment_rounded),
    MapEntry('visitor center', Icons.apartment_rounded),
    MapEntry('coffee', Icons.apartment_rounded),
    MapEntry('restaurant', Icons.apartment_rounded),
    MapEntry('business', Icons.apartment_rounded),
  ];
  for (final rule in rules) {
    if (t.contains(rule.key)) return rule.value;
  }
  return Icons.place_rounded;
}

/// Large, thumb-reachable confirm button — spec: "Place a large, simple
/// button at the LOWER portion of the screen for easy one-handed access."
class _ConfirmArrowButton extends StatelessWidget {
  const _ConfirmArrowButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 88,
        height: 88,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: RD.greenBright,
        ),
        child: const Icon(Icons.arrow_upward_rounded,
            size: 44, color: RD.onGreen),
      ),
    );
  }
}

/// Shown only once the user has pressed ↑ and there was more than one
/// strong candidate in the locked direction — spec: "show the user the
/// relevant choices, preferably with available photos, and let the user
/// select the correct one." Reuses [_CandidateCard] unchanged.
class _ChooserView extends StatelessWidget {
  const _ChooserView({
    required this.candidates,
    required this.imageFor,
    required this.onPick,
    required this.onScanAgain,
  });
  final List<WhatIsThatCandidate> candidates;
  final String? Function(WhatIsThatCandidate) imageFor;
  final void Function(String id) onPick;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(RD.sm, RD.sm, RD.lg, 0),
          child: TextButton.icon(
            onPressed: onScanAgain,
            icon: const Icon(Icons.refresh_rounded, color: RD.greenBright),
            label: Text('SCAN AGAIN',
                style:
                    RD.badge.copyWith(color: RD.greenBright, letterSpacing: 1.1)),
          ),
        ),
        Expanded(
          child: candidates.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(RD.xl),
                    child: Text(
                      "Nothing known was in that direction. Point "
                      "somewhere else and press ↑ again.",
                      textAlign: TextAlign.center,
                      style: RD.body.copyWith(color: RD.textSecondary),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: RD.lg, vertical: RD.sm),
                  children: [
                    Text(
                      "${candidates.length} places that way — which one?",
                      style: RD.badge
                          .copyWith(color: RD.textSecondary, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: RD.sm),
                    for (final c in candidates) ...[
                      _CandidateCard(
                        candidate: c,
                        imageUrl: imageFor(c),
                        selected: false,
                        onTap: () => onPick(c.id),
                      ),
                      const SizedBox(height: RD.sm),
                    ],
                  ],
                ),
        ),
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

/// A candidate selection card — spec: "Show: Photo, Building/place name,
/// Type/category, Distance, Address when useful... The user should be able
/// to tap the photo/card to select that building." A photo is only ever a
/// visual aid: a candidate with no photo at all (neither our own database
/// nor a cached Google Places one) still shows fully identified by name,
/// type, and distance — never blocked on having a picture.
class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.imageUrl,
    required this.selected,
    required this.onTap,
  });
  final WhatIsThatCandidate candidate;
  final String? imageUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(RD.sm),
        decoration: BoxDecoration(
          color: RD.panel,
          borderRadius: BorderRadius.circular(RD.rMd),
          border: Border.all(
            color: selected ? RD.greenBright : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(RD.rSm),
              child: SizedBox(
                width: 64,
                height: 64,
                child: (imageUrl ?? '').trim().isNotEmpty
                    ? Image.network(imageUrl!, fit: BoxFit.cover)
                    : Container(
                        color: RD.bgElevated,
                        alignment: Alignment.center,
                        child: Icon(_categoryIconFor(candidate),
                            color: RD.greenBright),
                      ),
              ),
            ),
            const SizedBox(width: RD.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(candidate.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RD.cardTitle.copyWith(color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if ((candidate.typeLabel ?? '').isNotEmpty)
                        candidate.typeLabel,
                      candidate.distanceLabel,
                    ].whereType<String>().join('  ·  '),
                    style: RD.caption.copyWith(color: RD.textSecondary),
                  ),
                  if ((candidate.address ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(candidate.address!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RD.caption.copyWith(color: RD.textSecondary)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateDetail extends StatelessWidget {
  const _CandidateDetail({
    super.key,
    required this.candidate,
    required this.imageUrl,
    required this.onTellDjSunny,
    required this.onTellMeMore,
    required this.onNavigate,
    required this.onScanAgain,
    this.onChooseDifferent,
  });
  final WhatIsThatCandidate candidate;
  final String? imageUrl;
  final VoidCallback onTellDjSunny;
  final VoidCallback onTellMeMore;
  final VoidCallback onNavigate;
  final VoidCallback onScanAgain;
  final VoidCallback? onChooseDifferent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: onScanAgain,
              icon: const Icon(Icons.refresh_rounded,
                  size: 18, color: RD.greenBright),
              label: Text('SCAN AGAIN',
                  style: RD.badge
                      .copyWith(color: RD.greenBright, letterSpacing: 1.0)),
            ),
            if (onChooseDifferent != null)
              TextButton.icon(
                onPressed: onChooseDifferent,
                icon: const Icon(Icons.swap_horiz_rounded,
                    size: 18, color: RD.textSecondary),
                label: Text('DIFFERENT PLACE',
                    style: RD.badge
                        .copyWith(color: RD.textSecondary, letterSpacing: 1.0)),
              ),
          ],
        ),
        const SizedBox(height: RD.sm),
        Container(
          decoration: BoxDecoration(
            color: RD.panel,
            borderRadius: BorderRadius.circular(RD.rLg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((imageUrl ?? '').trim().isNotEmpty)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(imageUrl!, fit: BoxFit.cover),
                ),
              Padding(
                padding: const EdgeInsets.all(RD.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _CategoryBadge(
                            icon: _categoryIconFor(candidate), size: 32),
                        const SizedBox(width: RD.sm),
                        Expanded(
                          child: Text(candidate.name,
                              style: RD.title.copyWith(color: Colors.white)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if ((candidate.typeLabel ?? '').isNotEmpty)
                          candidate.typeLabel,
                        candidate.distanceLabel,
                      ].whereType<String>().join('  ·  '),
                      style: RD.caption.copyWith(color: RD.textSecondary),
                    ),
                    if ((candidate.address ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(candidate.address!,
                          style: RD.caption.copyWith(color: RD.textSecondary)),
                    ],
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
                        OutlinedButton.icon(
                          onPressed: onTellDjSunny,
                          icon: const Icon(Icons.replay_rounded, size: 18),
                          label: const Text('Replay'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onTellMeMore,
                          icon:
                              const Icon(Icons.info_outline_rounded, size: 18),
                          label: const Text('Tell Me More'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onNavigate,
                          icon: const Icon(Icons.directions_rounded, size: 18),
                          label: const Text('Navigate'),
                        ),
                      ],
                    ),
                    const SizedBox(height: RD.lg),
                    _TopicPicker(candidate: candidate, imageUrl: imageUrl),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Which topics are worth even offering for [c] — spec: "Only display
/// topics for which meaningful information exists." A simple, free
/// presence-based check against fields already on the candidate (our own
/// database — Google Places only ever supplements the actual generated
/// answer later, per the identification priority order: existing database
/// before Google Places). "What's Here Now" and "Tell Me More" are always
/// offered — asking "what's here" or for a general overview is meaningful
/// for literally any physical place, even when the honest answer ends up
/// being "not verified" (the worker says so rather than inventing one).
List<WhatIsThatTopic> _relevantTopicsFor(WhatIsThatCandidate c) {
  final hasDescription = (c.description ?? '').trim().isNotEmpty;
  const peopleStoryTypes = {
    'Historic Site',
    'Historic District',
    'Museum',
    'Monument',
    'Memorial',
  };
  final out = <WhatIsThatTopic>[];
  if (hasDescription) out.add(WhatIsThatTopic.history);
  out.add(WhatIsThatTopic.whatsHereNow);
  if (hasDescription) out.add(WhatIsThatTopic.uniqueFeatures);
  if (hasDescription || peopleStoryTypes.contains(c.typeLabel)) {
    out.add(WhatIsThatTopic.peopleStories);
  }
  if (c.wheelchairAccessible != null) out.add(WhatIsThatTopic.accessibility);
  if ((c.hours ?? '').trim().isNotEmpty ||
      (c.admission ?? '').trim().isNotEmpty) {
    out.add(WhatIsThatTopic.visitorInformation);
  }
  out.add(WhatIsThatTopic.tellMeMore);
  return out;
}

/// Auto-plays a short basic DJ Sunny narration the moment a candidate is
/// selected (spec: "Immediately play the short basic DJ Sunny narration"),
/// then reveals the relevant topic chips once it's had time to finish (spec:
/// "After the basic narration, display the short list of available
/// information topics"). Each topic is additional, richer, on-demand
/// narration — reuses the exact enqueue -> trigger -> poll pattern already
/// proven by Radio Automation's "Generate & poll" flow, and the exact same
/// requestInterruption + play-if-idle playback fix already applied to
/// [WhatIsThatScreen._tellDjSunny] — no new audio player, no new voice.
class _TopicPicker extends ConsumerStatefulWidget {
  const _TopicPicker({required this.candidate, required this.imageUrl});
  final WhatIsThatCandidate candidate;
  final String? imageUrl;

  @override
  ConsumerState<_TopicPicker> createState() => _TopicPickerState();
}

class _TopicPickerState extends ConsumerState<_TopicPicker> {
  WhatIsThatTopic? _busyTopic;
  String? _error;
  bool _narrationDone = false;

  @override
  void initState() {
    super.initState();
    _playBasicNarration();
  }

  void _playBasicNarration() {
    final c = widget.candidate;
    final text = (c.description ?? '').trim();
    final spoken = text.isNotEmpty ? text : "That's ${c.name}.";
    final radio = ref.read(radioEngineControllerProvider.notifier);
    radio.requestInterruption(
      AudioSegment(
        id: 'whatisthat:${c.locationId}:'
            '${DateTime.now().microsecondsSinceEpoch}',
        title: c.name,
        artist: 'DJ Sunny',
        type: AudioSegmentType.gpsNarration,
        priority: PlaybackPriority.scheduledAnnouncement,
        imageUrl: widget.imageUrl,
        audioUrl: c.hasAudio ? c.audioUrl : null,
        spokenText: c.hasAudio ? null : spoken,
        location: GeoPoint(latitude: c.latitude, longitude: c.longitude),
        tags: const ['what_is_that'],
        interruptible: true,
        resumeAfter: true,
      ),
    );
    if (ref.read(radioEngineControllerProvider).status !=
        PlaybackStatus.playing) {
      radio.play();
    }
    // Reveal the topic list once the basic narration has had time to finish.
    // Estimated from word count (same formula RadioAudioService already uses
    // for its own TTS-completion fallback) since a pre-recorded clip's exact
    // duration isn't known client-side.
    final words = c.hasAudio ? 30 : spoken.split(RegExp(r'\s+')).length;
    final secs = (words / 2.0).clamp(4, 60).toInt() + 2;
    Future.delayed(Duration(seconds: secs), () {
      if (mounted) setState(() => _narrationDone = true);
    });
  }

  Future<void> _play(WhatIsThatNarration narration) async {
    final c = widget.candidate;
    final radio = ref.read(radioEngineControllerProvider.notifier);
    radio.requestInterruption(
      AudioSegment(
        id: 'whatisthat:topic:${c.locationId}:'
            '${DateTime.now().microsecondsSinceEpoch}',
        title: c.name,
        artist: 'DJ Sunny',
        type: AudioSegmentType.gpsNarration,
        priority: PlaybackPriority.scheduledAnnouncement,
        imageUrl: widget.imageUrl,
        audioUrl: narration.hasAudio ? narration.audioUrl : null,
        spokenText: narration.hasAudio ? null : narration.script,
        location: GeoPoint(latitude: c.latitude, longitude: c.longitude),
        tags: const ['what_is_that'],
        interruptible: true,
        resumeAfter: true,
      ),
    );
    if (ref.read(radioEngineControllerProvider).status !=
        PlaybackStatus.playing) {
      radio.play();
    }
  }

  Future<void> _onTopicTap(WhatIsThatTopic topic) async {
    if (_busyTopic != null) return;
    setState(() {
      _busyTopic = topic;
      _error = null;
    });
    final repo = ref.read(whatIsThatNarrationRepositoryProvider);
    final locationId = widget.candidate.locationId;
    try {
      var narration = await repo.narrationFor(locationId, topic);
      if (narration == null) {
        final queued = await repo.enqueueTopic(locationId, topic);
        if (queued) await repo.triggerNarrationWorker();
        // Poll briefly for the result (mirrors Radio Automation's Create
        // tab) — OpenAI + Google Places + ElevenLabs together usually take
        // a few seconds; the job stays queued for the scheduled worker
        // either way if this tab closes before it's ready.
        for (var i = 0; i < 10 && narration == null && mounted; i++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          narration = await repo.narrationFor(locationId, topic);
        }
      }
      if (!mounted) return;
      if (narration == null) {
        setState(() => _error =
            "DJ Sunny is still putting that together — try again in a "
            "moment.");
        return;
      }
      await _play(narration);
    } finally {
      if (mounted) setState(() => _busyTopic = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_narrationDone) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: RD.sm),
          Text('DJ Sunny is talking…',
              style: RD.caption.copyWith(color: RD.textSecondary)),
        ],
      );
    }

    final topics = _relevantTopicsFor(widget.candidate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ASK DJ SUNNY ABOUT...',
          style: RD.badge.copyWith(color: RD.textSecondary, letterSpacing: 1.1),
        ),
        const SizedBox(height: RD.sm),
        Wrap(
          spacing: RD.sm,
          runSpacing: RD.sm,
          children: [
            for (final topic in topics)
              _TopicChip(
                label: '🎧 ${topic.label}',
                busy: _busyTopic == topic,
                enabled: _busyTopic == null,
                onTap: () => _onTopicTap(topic),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: RD.sm),
          Text(_error!, style: RD.caption.copyWith(color: RD.amber)),
        ],
      ],
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({
    required this.label,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: enabled ? onTap : null,
      child: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}
