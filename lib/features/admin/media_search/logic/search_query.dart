/// Pure query-building for the Media Search Center.
///
/// Given a destination (name + county + state + type), it produces the primary
/// search string AND an ordered "smart retry" fallback chain, so a search keeps
/// trying broader/narrower variants until quality results appear (the brief's
/// "Smart Search" behavior).
library;

/// The minimal destination shape the query builder needs (kept independent of
/// the app's `MasterLocation` so it's trivially unit-testable).
class SearchDestination {
  const SearchDestination({
    required this.name,
    this.county,
    this.state = 'Florida',
    this.typeLabel,
  });

  final String name;
  final String? county;
  final String state;
  final String? typeLabel;
}

String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The primary query: `Name County State` (skipping blanks/dupes).
String buildPrimaryQuery(SearchDestination d) {
  final parts = <String>[d.name];
  final county = d.county?.trim();
  if (county != null && county.isNotEmpty) {
    final c = county.toLowerCase().endsWith('county')
        ? county
        : '$county County';
    if (!d.name.toLowerCase().contains(county.toLowerCase())) parts.add(c);
  }
  if (d.state.trim().isNotEmpty &&
      !d.name.toLowerCase().contains(d.state.toLowerCase())) {
    parts.add(d.state);
  }
  return _clean(parts.join(' '));
}

/// The ordered smart-retry chain. Each entry is tried in turn until enough
/// quality results are found:
///   1. Name + County + State   (most specific)
///   2. Name + State
///   3. Name + County
///   4. Name + type keyword (e.g. "State Park", "Historic Site")
///   5. Name alone             (broadest)
///
/// Duplicates and blanks are removed while preserving order.
List<String> buildQueryChain(SearchDestination d) {
  final name = _clean(d.name);
  final county = d.county?.trim();
  final countyLabel = (county == null || county.isEmpty)
      ? null
      : (county.toLowerCase().endsWith('county') ? county : '$county County');
  final state = d.state.trim().isEmpty ? null : d.state.trim();
  final type = d.typeLabel?.trim().isEmpty ?? true ? null : d.typeLabel!.trim();

  final candidates = <String>[
    [name, countyLabel, state].whereType<String>().join(' '),
    [name, state].whereType<String>().join(' '),
    [name, countyLabel].whereType<String>().join(' '),
    if (type != null && !name.toLowerCase().contains(type.toLowerCase()))
      [name, type].whereType<String>().join(' '),
    name,
  ];

  final seen = <String>{};
  final out = <String>[];
  for (final c in candidates) {
    final q = _clean(c);
    if (q.isEmpty) continue;
    final key = q.toLowerCase();
    if (seen.add(key)) out.add(q);
  }
  return out;
}

/// The significant tokens of a destination name, used by ranking to measure how
/// well a result title matches (lowercased, stop-words + generic place words
/// removed).
Set<String> significantTokens(String name) {
  const stop = {
    'the', 'of', 'and', 'a', 'an', 'at', 'in', 'on', 'state', 'national',
    'county', 'park', 'florida', 'fl', 'historic', 'site', 'area',
  };
  return name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.length > 2 && !stop.contains(t))
      .toSet();
}
