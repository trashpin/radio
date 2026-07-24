import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/radio/repositories/announcement_repository.dart';
import 'package:explorer_os_mobile/features/radio/repositories/radio_station_repository.dart';
import 'package:explorer_os_mobile/features/radio/repositories/song_repository.dart';
import 'package:explorer_os_mobile/features/radio/repositories/station_profile_repository.dart';
import 'package:explorer_os_mobile/features/stories/data/narration_repository.dart';
import 'package:explorer_os_mobile/features/radio/models/announcement.dart';
import 'package:explorer_os_mobile/features/radio/models/station_profile.dart';
import 'package:explorer_os_mobile/shared/models/narration.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

/// Aggregate facade over the radio content repositories.
///
/// WHY THIS EXISTS: the engine/UI often need several related reads (a station,
/// its profile, its songs, its announcements/narrations). Rather than inject
/// five repositories everywhere, this facade composes the existing ones — it
/// REUSES `RadioStationRepository`, `SongRepository`, `AnnouncementRepository`,
/// `StationProfileRepository`, and the stories `NarrationRepository` (no
/// duplicated data-access logic).
class RadioRepository {
  const RadioRepository({
    required this.stations,
    required this.profiles,
    required this.songs,
    required this.announcements,
    required this.narrations,
  });

  final RadioStationRepository stations;
  final StationProfileRepository profiles;
  final SongRepository songs;
  final AnnouncementRepository announcements;
  final NarrationRepository narrations;

  Future<List<RadioStation>> allStations() => stations.getAll();
  Future<List<StationProfile>> allProfiles() => profiles.getAll();
  Future<List<Song>> songsForStation(String stationId) =>
      songs.byStation(stationId);
  Future<List<Announcement>> announcementsForStation(String stationId) =>
      announcements.byStation(stationId);
  Future<List<Narration>> narrationsForStory(String storyId) =>
      narrations.byStory(storyId);
}

final radioRepositoryProvider = Provider<RadioRepository>((ref) {
  return RadioRepository(
    stations: ref.watch(radioStationRepositoryProvider),
    profiles: ref.watch(stationProfileRepositoryProvider),
    songs: ref.watch(songRepositoryProvider),
    announcements: ref.watch(announcementRepositoryProvider),
    narrations: ref.watch(narrationRepositoryProvider),
  );
});
