import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';

/// Events published by the Radio Engine so the UI (and other systems) can react
/// instead of polling `PlaybackState`.
///
/// `sealed` enables exhaustive handling. Emitted on `RadioEngineService.events`.
sealed class RadioEvent {
  const RadioEvent(this.at);
  final DateTime at;
}

class SegmentStarted extends RadioEvent {
  const SegmentStarted(super.at, this.segment);
  final AudioSegment segment;
}

class SegmentCompleted extends RadioEvent {
  const SegmentCompleted(super.at, this.segment);
  final AudioSegment segment;
}

class SegmentInterrupted extends RadioEvent {
  const SegmentInterrupted(super.at, this.segment);
  final AudioSegment segment;
}

class MusicResumed extends RadioEvent {
  const MusicResumed(super.at);
}

class StationChanged extends RadioEvent {
  const StationChanged(super.at, this.stationId);
  final String stationId;
}

class QueueCleared extends RadioEvent {
  const QueueCleared(super.at);
}

class PlaybackPaused extends RadioEvent {
  const PlaybackPaused(super.at);
}

class PlaybackResumed extends RadioEvent {
  const PlaybackResumed(super.at);
}

class PlaybackStopped extends RadioEvent {
  const PlaybackStopped(super.at);
}

class VolumeChanged extends RadioEvent {
  const VolumeChanged(super.at, this.volume);
  final double volume;
}

class MuteChanged extends RadioEvent {
  const MuteChanged(super.at, this.muted);
  final bool muted;
}
