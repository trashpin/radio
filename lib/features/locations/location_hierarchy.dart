import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// Pure helpers for the location hierarchy (Country → State → County → City →
/// Park → POI …, unlimited depth via [MasterLocation.parentLocationId]).
///
/// All functions are cycle-safe and side-effect free so they're trivially unit
/// tested; the engine/admin layer supplies the full location set.
class LocationHierarchy {
  const LocationHierarchy._();

  /// Index a location list by id for O(1) parent lookups.
  static Map<String, MasterLocation> indexById(List<MasterLocation> all) => {
        for (final l in all) l.id: l,
      };

  /// Ancestors of [l], nearest parent first up to the root. Cycle-safe.
  static List<MasterLocation> ancestorsOf(
    MasterLocation l,
    Map<String, MasterLocation> byId,
  ) {
    final out = <MasterLocation>[];
    final seen = <String>{l.id};
    var pid = l.parentLocationId;
    while (pid != null && pid.isNotEmpty && !seen.contains(pid)) {
      final parent = byId[pid];
      if (parent == null) break;
      out.add(parent);
      seen.add(parent.id);
      pid = parent.parentLocationId;
    }
    return out;
  }

  /// The full chain root → … → [l] (breadcrumb order).
  static List<MasterLocation> chainTo(
    MasterLocation l,
    Map<String, MasterLocation> byId,
  ) =>
      [...ancestorsOf(l, byId).reversed, l];

  /// Direct children of [parentId].
  static List<MasterLocation> childrenOf(
    String parentId,
    List<MasterLocation> all,
  ) =>
      [for (final l in all) if (l.parentLocationId == parentId) l];

  /// All descendants of [parentId] (any depth). Cycle-safe.
  static List<MasterLocation> descendantsOf(
    String parentId,
    List<MasterLocation> all,
  ) {
    final byParent = <String, List<MasterLocation>>{};
    for (final l in all) {
      final p = l.parentLocationId;
      if (p != null && p.isNotEmpty) (byParent[p] ??= []).add(l);
    }
    final out = <MasterLocation>[];
    final seen = <String>{};
    final stack = <String>[parentId];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      for (final child in byParent[id] ?? const <MasterLocation>[]) {
        if (seen.add(child.id)) {
          out.add(child);
          stack.add(child.id);
        }
      }
    }
    return out;
  }

  /// The nearest ancestor (or [l] itself) of a given [type] — e.g. the current
  /// County/City/Park for a POI. Returns null if none in the chain.
  static MasterLocation? nearestOfType(
    MasterLocation l,
    LocationType type,
    Map<String, MasterLocation> byId,
  ) {
    if (l.type == type) return l;
    for (final a in ancestorsOf(l, byId)) {
      if (a.type == type) return a;
    }
    return null;
  }

  /// A human-readable breadcrumb ("Florida › Marion County › Ocala › …").
  static String breadcrumb(
    MasterLocation l,
    Map<String, MasterLocation> byId, {
    String separator = ' › ',
  }) =>
      chainTo(l, byId).map((e) => e.name).join(separator);
}
