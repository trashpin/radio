import 'package:explorer_os_mobile/core/data/model.dart';

/// Abstraction over a local cache of entities of type [T].
///
/// WHY THIS EXISTS: it is the seam that makes offline support a drop-in future
/// change. Repositories talk to a [CacheStore] instead of a concrete storage
/// engine, so today's in-memory implementation can be swapped for a persistent
/// one (Hive, Isar, sqflite, Drift…) without touching a single repository or
/// widget. Keyed by [Model.id] for O(1) lookups.
abstract class CacheStore<T extends Model> {
  /// All cached items, or null if a full list has never been cached (distinct
  /// from an empty list, which means "we cached zero results").
  List<T>? readAll();

  /// Replaces the cached collection with [items] and marks it complete.
  void writeAll(List<T> items);

  /// A single cached item by id, or null if absent.
  T? readById(String id);

  /// Inserts or updates a single item.
  void upsert(T item);

  /// Removes a single item by id.
  void remove(String id);

  /// Clears everything.
  void clear();
}

/// Default, process-lifetime cache. Fast and dependency-free; loses data on
/// app restart. Persistent stores can implement [CacheStore] later.
class InMemoryCacheStore<T extends Model> implements CacheStore<T> {
  final Map<String, T> _byId = {};
  bool _hasFullList = false;

  @override
  List<T>? readAll() =>
      _hasFullList ? _byId.values.toList(growable: false) : null;

  @override
  void writeAll(List<T> items) {
    _byId
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.id, item)));
    _hasFullList = true;
  }

  @override
  T? readById(String id) => _byId[id];

  @override
  void upsert(T item) => _byId[item.id] = item;

  @override
  void remove(String id) => _byId.remove(id);

  @override
  void clear() {
    _byId.clear();
    _hasFullList = false;
  }
}
