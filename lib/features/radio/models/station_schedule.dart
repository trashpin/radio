import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';

/// A single daypart in a station's schedule (e.g. "Morning Drive", 6–10, music).
class Daypart {
  const Daypart({
    required this.label,
    required this.startHour,
    required this.endHour,
    this.emphasis = AudioCategory.music,
  });

  final String label;
  final int startHour;
  final int endHour;

  /// What this daypart leans toward (e.g. more spoken word in the morning).
  final AudioCategory emphasis;

  bool contains(int hour) => hour >= startHour && hour < endHour;
}

/// A station's daypart schedule (read-only backend content).
///
/// Lets a station shift emphasis by time of day (morning talk vs. evening
/// music). The schedulers can consult [daypartFor] to bias selection. Distinct
/// from [StationRule] (which sets cadence counts).
class StationSchedule implements Model {
  const StationSchedule({
    required this.id,
    required this.stationId,
    this.dayparts = const [],
  });

  @override
  final String id;
  final String stationId;
  final List<Daypart> dayparts;

  Daypart? daypartFor(int hour) {
    for (final d in dayparts) {
      if (d.contains(hour)) return d;
    }
    return null;
  }

  factory StationSchedule.fromJson(Json json) => StationSchedule(
        id: json['id']?.toString() ?? '',
        stationId: json['station_id']?.toString() ?? '',
        dayparts: ((json['dayparts'] as List?) ?? const [])
            .map((e) => Daypart(
                  label: (e['label'] ?? '') as String,
                  startHour: (e['start_hour'] as num?)?.toInt() ?? 0,
                  endHour: (e['end_hour'] as num?)?.toInt() ?? 24,
                ))
            .toList(growable: false),
      );
}
