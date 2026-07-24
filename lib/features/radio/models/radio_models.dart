/// Barrel for every model the Radio Engine works with.
///
/// The three content entities (RadioStation, Song, Narration) are REUSED from
/// the shared platform data layer (`shared/models`) — not duplicated — while
/// the engine-specific models live in this feature. Importing this one file
/// gives services/controllers the whole radio model vocabulary.
library;

// Reused shared content models.
export 'package:explorer_os_mobile/shared/models/narration.dart';
export 'package:explorer_os_mobile/shared/models/radio_station.dart';
export 'package:explorer_os_mobile/shared/models/song.dart';

// Engine-specific models.
export 'announcement.dart';
export 'audio_segment.dart';
export 'geo_point.dart';
export 'gps_audio_trigger.dart';
export 'playback_priority.dart';
export 'playback_queue_item.dart';
export 'playback_state.dart';
export 'station_rule.dart';
