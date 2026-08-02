import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_area/data/area_content_repository.dart';
import 'package:explorer_os_mobile/features/discover_area/models/audio_experience_sequence.dart';
import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/discover_area/models/narratable_item.dart';
import 'package:explorer_os_mobile/features/discover_area/providers/area_attractions_provider.dart';
import 'package:explorer_os_mobile/features/discover_area/providers/area_species_provider.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';

/// The full, ready-to-play Audio Experience sequence for [area] — gathers
/// History/Nature content, Wildlife species, and nearby Attractions, then
/// hands them to [buildAudioExperienceSequence] for ordering.
final audioExperienceSequenceProvider =
    FutureProvider.family<List<NarratableItem>, DiscoveryArea>((ref, area) async {
  final locationId = area.location.id;
  final history = await ref.watch(
    areaContentForCategoryProvider((locationId: locationId, categoryToken: 'history')).future,
  );
  final nature = await ref.watch(
    areaContentForCategoryProvider((locationId: locationId, categoryToken: 'nature')).future,
  );
  final wildlife = await ref.watch(areaSpeciesProvider('wildlife').future);
  final attractions = ref.watch(areaAttractionsProvider(area));
  final contentItems = ref.watch(locationContentItemsProvider);

  return buildAudioExperienceSequence(
    area: area,
    historyBlocks: history,
    wildlifeSpecies: wildlife,
    natureBlocks: nature,
    attractions: attractions,
    locationContentItems: contentItems,
  );
});
