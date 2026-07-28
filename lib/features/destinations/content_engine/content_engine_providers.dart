import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/destinations/content_engine/content_data_source.dart';
import 'package:explorer_os_mobile/features/destinations/content_engine/content_relationship_engine.dart';
import 'package:explorer_os_mobile/features/destinations/content_engine/models/destination_content.dart';

/// The active content data source (Supabase in production; overridable in tests
/// with a fake).
final contentDataSourceProvider =
    Provider<ContentDataSource>((ref) => const SupabaseContentDataSource());

/// The Content Relationship Engine — the single entry point for loading all
/// content related to a `destination_code`.
final contentRelationshipEngineProvider =
    Provider<ContentRelationshipEngine>((ref) {
  return ContentRelationshipEngine(ref.watch(contentDataSourceProvider));
});

/// Loads the complete [DestinationExperience] for a `destination_code`.
///
/// Watch this from any screen: `ref.watch(destinationExperienceProvider(code))`.
final destinationExperienceProvider =
    FutureProvider.family<DestinationExperience, String>((ref, code) {
  return ref
      .watch(contentRelationshipEngineProvider)
      .loadDestinationExperience(code);
});
