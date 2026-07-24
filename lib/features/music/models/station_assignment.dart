import 'package:explorer_os_mobile/core/data/model.dart';

/// Assigns a song to a radio station (many-to-many: a song can air on multiple
/// stations). [weight] biases selection frequency.
class StationAssignment implements Model {
  const StationAssignment({
    required this.id,
    required this.songId,
    required this.stationId,
    this.weight = 1.0,
  });

  @override
  final String id;
  final String songId;
  final String stationId;
  final double weight;

  factory StationAssignment.fromJson(Json json) => StationAssignment(
        id: json['id']?.toString() ?? '',
        songId: json['song_id']?.toString() ?? '',
        stationId: json['station_id']?.toString() ?? '',
        weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
      );

  Json toJson() => {
        'id': id,
        'song_id': songId,
        'station_id': stationId,
        'weight': weight,
      };
}
