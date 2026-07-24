import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/companion/services/travel_companion_service.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_providers.dart';
import 'package:explorer_os_mobile/features/radio/producer/producer_engine.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';

/// Wires the GPS ↔ AI Producer ↔ Radio coordinator.
///
/// The [TravelCompanionService] depends on all three engines (this is the
/// designated integration layer). It auto-attaches to the GPS engine so that as
/// soon as GPS tracking produces travel contexts, the coordinator maps them
/// through the Producer and drives the Radio engine. Subscribing is harmless
/// before tracking starts (no contexts flow until then).
final travelCompanionServiceProvider =
    Provider<TravelCompanionService>((ref) {
  final service = TravelCompanionService(
    producer: ref.watch(producerEngineProvider),
    radioEngine: ref.watch(radioEngineServiceProvider),
  );
  service.attachTo(ref.watch(gpsServiceProvider));
  ref.onDispose(service.dispose);
  return service;
});
