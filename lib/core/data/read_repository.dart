import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explorer_os_mobile/core/data/cache_store.dart';
import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/core/error/error_handler.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';

/// Generic, read-only repository for a Supabase-backed entity of type [T].
///
/// WHY THIS EXISTS: every content entity (destinations, parks, stops, stories,
/// wildlife, plants, radio stations, songs, narrations) needs the exact same
/// read behavior — fetch all, fetch by id, fetch by a foreign key, with error
/// normalization and cache fallback. Implementing that once here means the
/// per-entity repositories are tiny (just a table name + a `fromJson`), so we
/// never duplicate query/caching/error logic.
///
/// Caching strategy (offline-ready): reads are served from the [CacheStore]
/// when the device is offline or when a network call fails, and successful
/// network results refresh the cache. Swapping [InMemoryCacheStore] for a
/// persistent store later gives true offline support with zero repo changes.
class SupabaseReadRepository<T extends Model> {
  SupabaseReadRepository({
    required this.client,
    required this.table,
    required this.fromJson,
    CacheStore<T>? cache,
    this.connectivity = const AlwaysOnlineConnectivityService(),
  }) : cache = cache ?? InMemoryCacheStore<T>();

  final SupabaseClient client;
  final String table;
  final T Function(Json json) fromJson;
  final CacheStore<T> cache;
  final ConnectivityService connectivity;

  /// Fetches every row. Serves cache when offline or on failure; refreshes the
  /// cache on success. Pass [forceRefresh] to bypass a warm cache.
  Future<List<T>> getAll({bool forceRefresh = false}) async {
    final cached = cache.readAll();

    if (!forceRefresh) {
      if (!await connectivity.isOnline) return cached ?? const [];
      if (cached != null) return cached;
    }

    try {
      final rows = await client.from(table).select();
      final items = rows.map((row) => fromJson(row)).toList(growable: false);
      cache.writeAll(items);
      return items;
    } catch (error, stackTrace) {
      if (cached != null) return cached; // graceful offline/failure fallback
      throw ErrorHandler.from(error, stackTrace);
    }
  }

  /// Fetches a single row by primary key, using the cache when possible.
  Future<T?> getById(String id) async {
    final cachedItem = cache.readById(id);
    if (cachedItem != null) return cachedItem;

    try {
      final row = await client.from(table).select().eq('id', id).maybeSingle();
      if (row == null) return null;
      final item = fromJson(row);
      cache.upsert(item);
      return item;
    } catch (error, stackTrace) {
      throw ErrorHandler.from(error, stackTrace);
    }
  }

  /// Fetches rows where [column] equals [value] — the building block for
  /// relationship queries (e.g. stops where `park_id = …`).
  Future<List<T>> getWhere(String column, Object value) async {
    try {
      final rows = await client.from(table).select().eq(column, value);
      return rows.map((row) => fromJson(row)).toList(growable: false);
    } catch (error, stackTrace) {
      throw ErrorHandler.from(error, stackTrace);
    }
  }
}

/// Generic repository for USER-OWNED entities that also write back to Supabase
/// (favorites, downloads).
///
/// WHY THIS EXISTS: user data is read the same way as content (so it extends
/// [SupabaseReadRepository]) but additionally needs create/update/delete to
/// synchronize local changes to the backend. Keeping the write logic generic
/// here avoids duplicating it in every user-data repository. Content
/// repositories deliberately do NOT get these methods — enforcing the app's
/// read-only stance on destination content.
class SupabaseSyncRepository<T extends Model> extends SupabaseReadRepository<T> {
  SupabaseSyncRepository({
    required super.client,
    required super.table,
    required super.fromJson,
    required this.toJson,
    super.cache,
    super.connectivity,
  });

  final Json Function(T item) toJson;

  /// Inserts or updates [item] remotely and refreshes the local cache.
  Future<void> upsert(T item) async {
    try {
      await client.from(table).upsert(toJson(item));
      cache.upsert(item);
    } catch (error, stackTrace) {
      throw ErrorHandler.from(error, stackTrace);
    }
  }

  /// Deletes the row with [id] remotely and evicts it from the cache.
  Future<void> deleteById(String id) async {
    try {
      await client.from(table).delete().eq('id', id);
      cache.remove(id);
    } catch (error, stackTrace) {
      throw ErrorHandler.from(error, stackTrace);
    }
  }
}
