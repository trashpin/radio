import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// An Explorer Radio station, optionally scoped to a [Destination].
///
/// Read-only backend content. A station groups [Song]s (and, conceptually,
/// narrations) into a continuous audio experience. `streamUrl` is the live
/// stream when applicable.
class RadioStation implements Model {
  const RadioStation({
    required this.id,
    required this.name,
    this.destinationId,
    this.description,
    this.imageUrl,
    this.streamUrl,
  });

  @override
  final String id;
  final String name;
  final String? destinationId;
  final String? description;
  final String? imageUrl;
  final String? streamUrl;

  factory RadioStation.fromJson(Json json) => RadioStation(
        id: json['id']?.toString() ?? '',
        name: (json['name'] ?? '') as String,
        destinationId: json['destination_id']?.toString(),
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        streamUrl: json['stream_url'] as String?,
      );

  /// Synthesizes a station from a [Destination]. Base44 has no `radio_stations`
  /// table — each destination *is* a station, powered by its audio `media`.
  factory RadioStation.fromDestination(Destination destination) => RadioStation(
        id: destination.id,
        name: '${destination.name} Radio',
        destinationId: destination.id,
        description: destination.description,
        imageUrl: destination.imageUrl,
      );
}
