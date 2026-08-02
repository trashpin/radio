/// One narrated content block within a Discover This Area category (e.g. the
/// "Early Settlement" segment of an area's History). Several blocks can share
/// a (locationId, categoryToken) pair and play in [sortOrder] — see
/// migration 0042 for why this is a generic, admin-manageable table rather
/// than per-category columns.
class AreaContentBlock {
  const AreaContentBlock({
    required this.id,
    required this.locationId,
    required this.categoryToken,
    required this.title,
    this.narrationScript,
    this.audioUrl,
    this.images = const [],
    this.sortOrder = 0,
    this.active = true,
  });

  final String id;
  final String locationId;
  final String categoryToken;
  final String title;
  final String? narrationScript;
  final String? audioUrl;
  final List<String> images;
  final int sortOrder;
  final bool active;

  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;
  bool get hasNarration => hasAudio || (narrationScript ?? '').trim().isNotEmpty;
  String? get heroImage => images.isNotEmpty ? images.first : null;

  static List<String> _strs(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  factory AreaContentBlock.fromJson(Map<String, dynamic> j) => AreaContentBlock(
        id: (j['id'] ?? '').toString(),
        locationId: (j['location_id'] ?? '').toString(),
        categoryToken: (j['category_token'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        narrationScript: j['narration_script'] as String?,
        audioUrl: j['audio_url'] as String?,
        images: _strs(j['images']),
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        active: (j['active'] ?? true) as bool,
      );

  Map<String, dynamic> toWrite() => {
        'location_id': locationId,
        'category_token': categoryToken,
        'title': title,
        'narration_script': narrationScript,
        'audio_url': audioUrl,
        'images': images,
        'sort_order': sortOrder,
        'active': active,
      };
}
