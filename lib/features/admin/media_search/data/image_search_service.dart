import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/media_search/data/openverse_client.dart';
import 'package:explorer_os_mobile/features/admin/media_search/data/wikimedia_client.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/search_query.dart';
import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';

/// The outcome of a smart search: the results plus which query in the retry
/// chain actually produced them (so the UI can show the matched query).
class SearchOutcome {
  const SearchOutcome({
    required this.results,
    required this.matchedQuery,
    required this.attempts,
  });
  final List<ImageSearchResult> results;
  final String matchedQuery;
  final List<String> attempts;

  bool get isEmpty => results.isEmpty;
}

/// Orchestrates a single provider with the brief's "Smart Search" retry chain:
/// try the most specific query first, then progressively broader variants,
/// stopping at the first query that yields at least [minResults] raw hits.
class ImageSearchService {
  ImageSearchService({
    required this.openverse,
    required this.wikimedia,
  });

  final OpenverseClient openverse;
  final WikimediaClient wikimedia;

  Future<List<ImageSearchResult>> _searchOnce(
      ImageSource source, String query) async {
    switch (source) {
      case ImageSource.openverse:
        return openverse.search(query);
      case ImageSource.wikimedia:
        return wikimedia.search(query);
      default:
        return const [];
    }
  }

  /// Runs the retry chain for [destination] against [source].
  Future<SearchOutcome> smartSearch(
    ImageSource source,
    SearchDestination destination, {
    int minResults = 4,
  }) async {
    final chain = buildQueryChain(destination);
    final attempts = <String>[];
    List<ImageSearchResult> best = const [];
    var bestQuery = chain.isEmpty ? destination.name : chain.first;

    for (final q in chain) {
      attempts.add(q);
      List<ImageSearchResult> hits;
      try {
        hits = await _searchOnce(source, q);
      } catch (_) {
        continue; // network / provider error → try the next variant
      }
      if (hits.length > best.length) {
        best = hits;
        bestQuery = q;
      }
      if (hits.length >= minResults) {
        return SearchOutcome(results: hits, matchedQuery: q, attempts: attempts);
      }
    }
    return SearchOutcome(
        results: best, matchedQuery: bestQuery, attempts: attempts);
  }

  /// A one-shot search with an explicit query (no retry chain).
  Future<List<ImageSearchResult>> searchQuery(
          ImageSource source, String query) =>
      _searchOnce(source, query);
}

final openverseClientProvider =
    Provider<OpenverseClient>((ref) => OpenverseClient());
final wikimediaClientProvider =
    Provider<WikimediaClient>((ref) => WikimediaClient());

final imageSearchServiceProvider = Provider<ImageSearchService>((ref) {
  return ImageSearchService(
    openverse: ref.watch(openverseClientProvider),
    wikimedia: ref.watch(wikimediaClientProvider),
  );
});
