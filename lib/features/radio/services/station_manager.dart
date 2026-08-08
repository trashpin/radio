import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/services/smart_music_rotation.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';
import 'package:explorer_os_mobile/features/radio/models/station_rule.dart';

/// Owns the CURRENT station: its identity, its [StationRule], and its music
/// playlist, and produces the next music segment on demand.
///
/// WHY THIS EXISTS: the engine shouldn't care where music comes from or how the
/// playlist advances — it just asks "give me the next music segment". This
/// manager encapsulates music selection and exposes the active rules the
/// schedulers need. Content is loaded by the engine via repositories and handed
/// here, keeping this class pure and testable.
///
/// Selection is delegated to the [SmartMusicRotationEngine]: instead of a
/// sequential round-robin cursor, each track is chosen from the top-scoring
/// candidates so the station never plays the same order twice and never repeats
/// a song during a trip. A fresh engine (new random seed) is created on each
/// [load], making every drive feel unique.
class StationManager {
  StationManager({SmartMusicRotationEngine Function()? engineFactory})
      : _engineFactory =
            engineFactory ?? (() => SmartMusicRotationEngine());

  final SmartMusicRotationEngine Function() _engineFactory;

  RadioStation? _station;
  StationRule? _rule;
  List<Song> _playlist = const [];
  Map<String, Song> _byId = const {};
  SmartMusicRotationEngine? _rotation;

  /// Current county's preferred music categories (CountyConfig.musicCategories),
  /// fed into the rotation scorer. Empty until a county is known.
  List<String> _countyCategories = const [];

  /// Updates the county music categories used to bias song selection.
  void setCountyMusicCategories(List<String> categories) =>
      _countyCategories = [
        for (final c in categories)
          if (c.trim().isNotEmpty) c.trim(),
      ];

  RadioStation? get station => _station;
  StationRule? get rule => _rule;
  bool get hasMusic => _playlist.isNotEmpty;

  /// The rotation engine driving music selection (exposed for debugging/tests).
  SmartMusicRotationEngine? get rotation => _rotation;

  /// Loads the active station, its rule, and its playlist, and starts a fresh
  /// rotation trip.
  void load({
    required RadioStation station,
    StationRule? rule,
    List<Song> playlist = const [],
  }) {
    _station = station;
    _rule = rule;
    _playlist = playlist;
    _byId = {for (final s in playlist) s.id: s};
    _rotation = _engineFactory();
  }

  /// Returns the next music [AudioSegment], selected by the Smart Music Rotation
  /// Engine, or null if the station has no music.
  AudioSegment? nextMusicSegment() {
    if (_playlist.isEmpty) return null;
    final engine = _rotation ??= _engineFactory();
    final ctx = RotationContext.now(
      park: _station?.destinationId,
      countyCategories: _countyCategories,
    );
    final picked = engine.pickNext(_rotationSongs(), ctx);
    final song = picked == null ? null : _byId[picked.id];
    if (song == null) return null;
    return AudioSegment.fromSong(song, parkId: _station?.destinationId);
  }

  List<RotationSong> _rotationSongs() => [
        for (final s in _playlist)
          RotationSong(
            id: s.id,
            audioUrl: s.audioUrl ?? '',
            title: s.title,
            park: _station?.destinationId,
            durationSeconds: s.durationSeconds,
          ),
      ];
}
