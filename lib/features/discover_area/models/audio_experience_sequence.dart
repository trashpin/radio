import 'package:explorer_os_mobile/features/discover_area/models/area_content_block.dart';
import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/discover_area/models/narratable_item.dart';
import 'package:explorer_os_mobile/features/discover_area/models/nearby_attractions.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/location_intelligence/models/content_item.dart'
    show ContentItem;

/// Assembles the Audio Experience's full sequence, in the spec's order:
/// Area Introduction → History → Wildlife → Nature → Interesting Facts →
/// Nearby Attractions → (return to radio, handled by the player itself once
/// the sequence ends).
///
/// Wildlife and Attractions are capped ([wildlifeLimit]/[attractionsLimit]) —
/// this is a "listen while driving" overview, not an exhaustive tour through
/// every species and every nearby location. Any section with nothing to say
/// is simply omitted, not included as a silent/empty item.
///
/// Pure — every input is pre-fetched data, no I/O here — easy to unit test.
List<NarratableItem> buildAudioExperienceSequence({
  required DiscoveryArea area,
  required List<AreaContentBlock> historyBlocks,
  required List<Species> wildlifeSpecies,
  required List<AreaContentBlock> natureBlocks,
  required List<AttractionMatch> attractions,
  required List<ContentItem> locationContentItems,
  int wildlifeLimit = 3,
  int attractionsLimit = 3,
}) {
  final sequence = <NarratableItem>[];

  // 1. Area Introduction.
  final intro = area.shortIntroduction?.trim();
  if (intro != null && intro.isNotEmpty) {
    sequence.add(NarratableItem(title: 'Welcome to ${area.name}', script: intro));
  }

  // 2. Area History.
  sequence.addAll(historyBlocks.map(NarratableItem.fromContentBlock));

  // 3. Wildlife.
  sequence.addAll(
    wildlifeSpecies.take(wildlifeLimit).map(NarratableItem.fromSpecies),
  );

  // 4. Nature.
  sequence.addAll(natureBlocks.map(NarratableItem.fromContentBlock));

  // 5. Interesting Facts — the area's own narration script, when it's a
  // distinct piece of writing from the intro already used above.
  final facts = area.location.narrationScript?.trim();
  if (facts != null && facts.isNotEmpty && facts != intro) {
    sequence.add(NarratableItem(title: 'Interesting Facts', script: facts));
  }

  // 6. Nearby Attractions.
  sequence.addAll(
    attractions
        .take(attractionsLimit)
        .map((m) => NarratableItem.fromAttraction(m, locationContentItems)),
  );

  // Drop anything that ended up with nothing to actually say (e.g. a
  // location with no narration content at all) rather than playing dead air.
  return sequence.where((i) => i.hasNarration).toList(growable: false);
}
