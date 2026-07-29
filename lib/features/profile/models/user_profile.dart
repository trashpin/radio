/// A user's ExplorerOS profile (the `public.profiles` row).
class UserProfile {
  const UserProfile({
    required this.id,
    this.firstName,
    this.lastName,
    this.displayName,
    this.email,
    this.avatarUrl,
    this.role = 'user',
    this.subscriptionLevel = 'free',
    this.joinDate,
    this.favoriteParks = const [],
    this.favoriteCounties = const [],
    this.tripHistory = const [],
    this.achievements = const [],
    this.preferredNarrator,
    this.preferredMusicStyle,
    this.downloadedAudio = const [],
    this.settings = const {},
  });

  final String id;
  final String? firstName;
  final String? lastName;
  final String? displayName;
  final String? email;
  final String? avatarUrl;
  final String role;
  final String subscriptionLevel;
  final DateTime? joinDate;
  final List<String> favoriteParks;
  final List<String> favoriteCounties;
  final List<dynamic> tripHistory;
  final List<String> achievements;
  final String? preferredNarrator;
  final String? preferredMusicStyle;
  final List<String> downloadedAudio;
  final Map<String, dynamic> settings;

  bool get isAdmin => role.toLowerCase() == 'admin';

  String get name {
    final full = [firstName, lastName]
        .where((s) => (s ?? '').trim().isNotEmpty)
        .join(' ')
        .trim();
    if (full.isNotEmpty) return full;
    return (displayName ?? '').trim().isNotEmpty
        ? displayName!.trim()
        : (email ?? 'Explorer');
  }

  static List<String> _strs(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: (j['id'] ?? '').toString(),
        firstName: j['first_name'] as String?,
        lastName: j['last_name'] as String?,
        displayName: j['display_name'] as String?,
        email: j['email'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        role: (j['role'] ?? 'user') as String,
        subscriptionLevel: (j['subscription_level'] ?? 'free') as String,
        joinDate: DateTime.tryParse('${j['created_at']}'),
        favoriteParks: _strs(j['favorite_parks']),
        favoriteCounties: _strs(j['favorite_counties']),
        tripHistory: j['trip_history'] is List ? j['trip_history'] as List : const [],
        achievements: _strs(j['achievements']),
        preferredNarrator: j['preferred_narrator'] as String?,
        preferredMusicStyle: j['preferred_music_style'] as String?,
        downloadedAudio: _strs(j['downloaded_audio']),
        settings: j['settings'] is Map
            ? Map<String, dynamic>.from(j['settings'] as Map)
            : const {},
      );
}
