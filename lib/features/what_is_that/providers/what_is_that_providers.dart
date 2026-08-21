import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/what_is_that/models/what_is_that_candidate.dart';
import 'package:explorer_os_mobile/features/what_is_that/services/what_is_that_search.dart';

/// True (magnetometer) compass heading in degrees, or null while
/// unavailable/calibrating/unsupported on this device. Entirely additive —
/// a NEW heading source this feature owns; it never touches
/// [gpsControllerProvider] or how the rest of the app derives heading from
/// GPS movement. `autoDispose` so the compass sensor stops the moment the
/// What Is That screen is closed.
final compassHeadingProvider = StreamProvider.autoDispose<double?>((ref) {
  final events = FlutterCompass.events;
  if (events == null) return Stream<double?>.value(null);
  return events.map((e) => e.heading);
});

/// The live "what am I pointing at" result: real GPS position (from the
/// existing, untouched [gpsControllerProvider]) + the true compass heading
/// when available (falling back to the existing GPS-derived heading/bearing
/// when a compass reading isn't — e.g. web, a device with no magnetometer,
/// or still calibrating) run through [findWhatIsThatCandidates]. Recomputes
/// automatically as the traveler moves or turns.
final whatIsThatCandidatesProvider =
    Provider.autoDispose<List<WhatIsThatCandidate>>((ref) {
  final travel = ref.watch(gpsControllerProvider);
  final userLoc = travel.location;
  if (userLoc == null) return const [];

  final compassHeading = ref.watch(compassHeadingProvider).value;
  final headingDeg =
      compassHeading ?? travel.heading?.degrees ?? travel.bearingDegrees;
  if (headingDeg == null) return const [];

  final locations =
      ref.watch(masterLocationsProvider).value ?? const <MasterLocation>[];
  return findWhatIsThatCandidates(
    locations: locations,
    userLocation: userLoc,
    headingDegrees: headingDeg,
  );
});

/// Whichever heading is actually driving the search right now (compass when
/// available, else the GPS fallback) — surfaced separately so the UI can
/// show the live compass dial and label its source honestly.
final whatIsThatHeadingProvider = Provider.autoDispose<double?>((ref) {
  final travel = ref.watch(gpsControllerProvider);
  final compassHeading = ref.watch(compassHeadingProvider).value;
  return compassHeading ?? travel.heading?.degrees ?? travel.bearingDegrees;
});

/// True while the heading in use is the device's own compass (not the GPS
/// movement fallback) — lets the UI say "compass" vs. "based on your
/// direction of travel."
final whatIsThatUsingCompassProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(compassHeadingProvider).value != null;
});
