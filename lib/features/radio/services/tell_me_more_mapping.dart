import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/destinations/data/destination_repository.dart';
import 'package:explorer_os_mobile/features/narration/data/destination_narration_repository.dart';
import 'package:explorer_os_mobile/features/narration/models/destination_narration.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';

/// Maps a DJ Banter category (the `category` token on [TellMeMoreContext])
/// to the ordered list of narration `script_type`s that best answer "tell me
/// more" about that moment. The first type with a published narration wins;
/// later entries are fallbacks so the button still surfaces something useful
/// even when the ideal type hasn't been generated/approved yet.
///
/// Returns an empty list for categories with no narration counterpart
/// (station IDs, song intros/outros, promos) — [TellMeMoreScreen] treats that
/// as "nothing more to add" rather than an empty-content state.
List<String> narrationTypesForBanterCategory(String? categoryId) {
  switch (categoryId) {
    case 'arrival':
      return const ['arrival', 'quick_intro'];
    case 'history_tease':
      return const ['main_history', 'extended_history'];
    case 'wildlife_tease':
      return const ['wildlife', 'birds'];
    case 'bird_tease':
      return const ['birds', 'wildlife'];
    case 'plant_tease':
      return const ['plants', 'trees'];
    case 'geology_tease':
      return const ['geology'];
    case 'interesting_fact':
      return const ['fun_facts'];
    case 'scenic_observation':
      return const ['scenic_highlights'];
    case 'photo_opportunity':
      return const ['photography_tips', 'scenic_highlights'];
    case 'trail_suggestion':
      return const ['nearby_attractions', 'scenic_highlights'];
    case 'hidden_gem':
      return const ['hidden_gems', 'nearby_attractions'];
    case 'family_activity':
      return const ['family_version', 'kids_version'];
    case 'safety_reminder':
      return const ['emergency_info'];
    case 'departure':
      return const ['departure'];
    case 'welcome':
      return const ['quick_intro', 'arrival'];
    default:
      // song_intro, song_outro, station_id, promotion, unknown categories.
      return const [];
  }
}

/// Resolves a `destination_code` (all a DJ Banter Studio clip carries) to the
/// `destination_id` uuid `destination_narrations` is actually keyed by.
/// Cached per code for the app session — codes don't change at runtime.
final _destinationIdByCodeProvider =
    FutureProvider.family<String?, String>((ref, code) async {
  final matches = await ref
      .watch(destinationRepositoryProvider)
      .getWhere('destination_code', code);
  return matches.isEmpty ? null : matches.first.id;
});

/// The best published narration to show for a "Tell Me More" tap, or null
/// when the destination/category has nothing published yet.
final tellMeMoreNarrationProvider = FutureProvider.autoDispose
    .family<DestinationNarration?, TellMeMoreContext>((ref, ctx) async {
  var destinationId = ctx.destinationId;
  if ((destinationId == null || destinationId.isEmpty) &&
      (ctx.destinationCode ?? '').isNotEmpty) {
    // DJ banter clips only carry destination_code today, not destination_id.
    destinationId = await ref.watch(
      _destinationIdByCodeProvider(ctx.destinationCode!).future,
    );
  }
  if (destinationId == null || destinationId.isEmpty) return null;

  final types = narrationTypesForBanterCategory(ctx.category);
  if (types.isEmpty) return null;

  return ref.watch(destinationNarrationRepositoryProvider).bestPublishedFor(
        destinationId: destinationId,
        scriptTypes: types,
      );
});
