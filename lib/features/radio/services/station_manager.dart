import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';
import 'package:explorer_os_mobile/features/radio/models/station_rule.dart';

/// Owns the CURRENT station: its identity, its [StationRule], and its music
/// playlist, and produces the next music segment on demand.
///
/// WHY THIS EXISTS: the engine shouldn't care where music comes from or how the
/// playlist advances — it just asks "give me the next music segment". This
/// manager encapsulates the current station's playlist cursor (round-robin) and
/// exposes the active rules the schedulers need. Content is loaded by the engine
/// via repositories and handed here, keeping this class pure and testable.
class StationManager {
  RadioStation? _station;
  StationRule? _rule;
  List<Song> _playlist = const [];
  int _cursor = 0;

  RadioStation? get station => _station;
  StationRule? get rule => _rule;
  bool get hasMusic => _playlist.isNotEmpty;

  /// Loads the active station, its rule, and its playlist.
  void load({
    required RadioStation station,
    StationRule? rule,
    List<Song> playlist = const [],
  }) {
    _station = station;
    _rule = rule;
    _playlist = playlist;
    _cursor = 0;
  }

  /// Returns the next music [AudioSegment] (looping the playlist), or null if
  /// the station has no music.
  AudioSegment? nextMusicSegment() {
    if (_playlist.isEmpty) return null;
    final song = _playlist[_cursor % _playlist.length];
    _cursor++;
    return AudioSegment.fromSong(song);
  }
}
