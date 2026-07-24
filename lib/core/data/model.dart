/// Shared data-layer primitives for the ExplorerOS platform.
///
/// [Json] is the canonical shape of a backend record (a decoded Supabase row).
/// [Model] is the contract every domain entity implements: it must expose a
/// stable [id]. That single guarantee is what lets the generic repository and
/// cache (see `read_repository.dart` / `cache_store.dart`) work uniformly for
/// EVERY entity — destinations, parks, stops, stories, wildlife, and so on —
/// without duplicating per-entity plumbing.
library;

/// A decoded backend record.
typedef Json = Map<String, dynamic>;

/// Base contract for all domain entities.
///
/// Models are immutable value objects that only know how to be built *from*
/// backend JSON (read-only content) — plus `toJson` for user-owned entities
/// that sync back (favorites, downloads).
abstract class Model {
  String get id;
}
