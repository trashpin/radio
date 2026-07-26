import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';

/// How chatty a DJ is between songs.
enum BanterLength {
  short('Short'),
  medium('Medium'),
  long('Long');

  const BanterLength(this.label);
  final String label;
}

/// An on-air DJ persona. Voice is an ElevenLabs voice id/name assigned in the
/// DJ Studio; personality/energy/humor/length shape the banter style.
class DjPersonality {
  const DjPersonality({
    required this.id,
    required this.name,
    required this.station,
    required this.tagline,
    required this.personality,
    required this.energy, // 1..5
    required this.humor, // 1..5
    required this.length,
    this.voiceId,
    this.voiceName,
  });

  final String id;
  final String name;
  final DjStation station;
  final String tagline;
  final String personality;
  final int energy;
  final int humor;
  final BanterLength length;
  final String? voiceId;
  final String? voiceName;

  DjPersonality copyWith({String? voiceId, String? voiceName}) => DjPersonality(
        id: id,
        name: name,
        station: station,
        tagline: tagline,
        personality: personality,
        energy: energy,
        humor: humor,
        length: length,
        voiceId: voiceId ?? this.voiceId,
        voiceName: voiceName ?? this.voiceName,
      );
}

/// The six seed DJs from the brief. These are the roster shown in the DJ Studio.
const List<DjPersonality> kSeedDjs = [
  DjPersonality(
    id: 'ranger_mike',
    name: 'Forest Ranger Mike',
    station: DjStation.all,
    tagline: 'Your trusted guide to the forest',
    personality: 'Warm, knowledgeable park ranger — calm and reassuring.',
    energy: 3,
    humor: 2,
    length: BanterLength.medium,
  ),
  DjPersonality(
    id: 'country_casey',
    name: 'Country Casey',
    station: DjStation.country,
    tagline: 'Back roads and boot-stompin\' country',
    personality: 'Down-home, friendly, storytelling drawl.',
    energy: 3,
    humor: 3,
    length: BanterLength.medium,
  ),
  DjPersonality(
    id: 'rock_rob',
    name: 'Rock Rob',
    station: DjStation.rock,
    tagline: 'Turn it up on the open road',
    personality: 'High-energy, punchy, a little wild.',
    energy: 5,
    humor: 3,
    length: BanterLength.short,
  ),
  DjPersonality(
    id: 'sunny_sarah',
    name: 'Sunny Sarah',
    station: DjStation.topHits,
    tagline: 'Today\'s biggest hits',
    personality: 'Bright, upbeat, polished top-40 host.',
    energy: 4,
    humor: 3,
    length: BanterLength.short,
  ),
  DjPersonality(
    id: 'campfire_charlie',
    name: 'Campfire Charlie',
    station: DjStation.all,
    tagline: 'Stories around the fire',
    personality: 'Mellow, cozy storyteller for evenings and campgrounds.',
    energy: 2,
    humor: 2,
    length: BanterLength.long,
  ),
  DjPersonality(
    id: 'kids_kelly',
    name: 'Kids Kelly',
    station: DjStation.kids,
    tagline: 'Fun for little explorers',
    personality: 'Playful, encouraging, sing-along energy.',
    energy: 5,
    humor: 4,
    length: BanterLength.short,
  ),
];

/// Admin-assigned voices per DJ (dj id -> {voiceId, voiceName}), session-scoped
/// today (a `dj_personalities` table can persist this later without UI change).
class DjVoiceAssignments extends Notifier<Map<String, ({String id, String name})>> {
  @override
  Map<String, ({String id, String name})> build() => {};

  void assign(String djId, String voiceId, String voiceName) =>
      state = {...state, djId: (id: voiceId, name: voiceName)};
}

final djVoiceAssignmentsProvider = NotifierProvider<DjVoiceAssignments,
    Map<String, ({String id, String name})>>(DjVoiceAssignments.new);

/// The DJ roster with any assigned voices applied.
final djRosterProvider = Provider<List<DjPersonality>>((ref) {
  final assign = ref.watch(djVoiceAssignmentsProvider);
  return [
    for (final dj in kSeedDjs)
      if (assign[dj.id] case final v?)
        dj.copyWith(voiceId: v.id, voiceName: v.name)
      else
        dj,
  ];
});

/// The DJ that hosts a given station (falls back to Forest Ranger Mike).
DjPersonality djForStation(List<DjPersonality> roster, DjStation station) {
  return roster.firstWhere(
    (d) => d.station == station,
    orElse: () => roster.firstWhere((d) => d.id == 'ranger_mike',
        orElse: () => roster.first),
  );
}
