import 'package:explorer_os_mobile/features/discover_area/models/area_content_block.dart';
import 'package:explorer_os_mobile/features/discover_area/models/nearby_attractions.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/location_intelligence/models/content_item.dart'
    show ContentItem;
import 'package:explorer_os_mobile/features/locations/data/location_narration.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/narration/services/narration_script_composer.dart';

/// One narratable "beat" in the Audio Experience — the common shape an area's
/// intro, a History/Nature content block, a species, and an attraction all
/// convert to, so one sequencer ([AudioExperienceController]) can play a
/// heterogeneous sequence without needing to know which kind each item was.
class NarratableItem {
  const NarratableItem({required this.title, this.audioUrl, this.script});
  final String title;
  final String? audioUrl;
  final String? script;

  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;
  bool get hasNarration => hasAudio || (script ?? '').trim().isNotEmpty;

  factory NarratableItem.fromContentBlock(AreaContentBlock b) => NarratableItem(
        title: b.title,
        audioUrl: b.audioUrl,
        script: b.narrationScript,
      );

  static const _composer = NarrationScriptComposer();
  factory NarratableItem.fromSpecies(Species s) => NarratableItem(
        title: s.commonName,
        script: _composer.composeForSpecies(s),
      );

  factory NarratableItem.fromLocation(
    MasterLocation location,
    List<ContentItem> contentItems,
  ) {
    final narration = resolveLocationNarration(location, contentItems);
    return NarratableItem(
      title: location.name,
      audioUrl: narration.hasAudio ? narration.audioUrl : null,
      script: narration.text,
    );
  }

  factory NarratableItem.fromAttraction(
    AttractionMatch m,
    List<ContentItem> contentItems,
  ) =>
      NarratableItem.fromLocation(m.location, contentItems);
}
