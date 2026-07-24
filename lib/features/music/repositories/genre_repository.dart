import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/music/models/genre.dart';
import 'package:explorer_os_mobile/features/music/models/mood.dart';

/// Read repository for [Genre]s.
class GenreRepository extends SupabaseReadRepository<Genre> {
  GenreRepository({required super.client, super.connectivity})
      : super(table: SupabaseTables.genres, fromJson: Genre.fromJson);
}

/// Read repository for [Mood]s.
class MoodRepository extends SupabaseReadRepository<Mood> {
  MoodRepository({required super.client, super.connectivity})
      : super(table: SupabaseTables.moods, fromJson: Mood.fromJson);
}

final genreRepositoryProvider = Provider<GenreRepository>((ref) {
  return GenreRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

final moodRepositoryProvider = Provider<MoodRepository>((ref) {
  return MoodRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
