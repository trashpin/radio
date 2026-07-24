import 'package:explorer_os_mobile/core/data/model.dart';

/// The kind of entity a favorite/download can reference.
///
/// A single enum lets favorites and downloads point at ANY content type
/// (destinations, parks, stops, stories…) without a table per relationship.
enum FavoriteEntityType {
  destination,
  park,
  stop,
  story,
  wildlife,
  plant,
  radioStation,
  song;

  /// Backend token (snake_case) persisted in the `entity_type` column.
  String get token {
    switch (this) {
      case FavoriteEntityType.radioStation:
        return 'radio_station';
      default:
        return name;
    }
  }

  static FavoriteEntityType fromToken(String? token) {
    return FavoriteEntityType.values.firstWhere(
      (t) => t.token == token,
      orElse: () => FavoriteEntityType.destination,
    );
  }
}

/// A user's favorite: a pointer from a user to any content entity.
///
/// USER-OWNED and writable, so it provides [toJson] for Supabase sync (unlike
/// read-only content models). The polymorphic `entityType`/`entityId` pair lets
/// one table capture favorites across every content type.
class UserFavorite implements Model {
  const UserFavorite({
    required this.id,
    required this.userId,
    required this.entityType,
    required this.entityId,
    this.createdAt,
  });

  @override
  final String id;
  final String userId;
  final FavoriteEntityType entityType;
  final String entityId;
  final DateTime? createdAt;

  factory UserFavorite.fromJson(Json json) => UserFavorite(
        id: json['id']?.toString() ?? '',
        userId: json['user_id']?.toString() ?? '',
        entityType: FavoriteEntityType.fromToken(json['entity_type'] as String?),
        entityId: json['entity_id']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      );

  Json toJson() => {
        'id': id,
        'user_id': userId,
        'entity_type': entityType.token,
        'entity_id': entityId,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}
