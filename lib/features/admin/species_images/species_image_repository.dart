import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';

/// One image in a species' master image library (a row of the `media` table
/// linked by `species_id`). This is the single source of truth for a species'
/// photos — every park reads the same species record, not its own copy.
class SpeciesImage {
  const SpeciesImage({
    required this.id,
    required this.url,
    this.thumbnailUrl,
    this.isFeatured = false,
    this.approved = true,
    this.photographer,
    this.license,
    this.source,
    this.sortOrder = 0,
  });

  final String id;
  final String url;
  final String? thumbnailUrl;
  final bool isFeatured;
  final bool approved;
  final String? photographer;
  final String? license;
  final String? source;
  final int sortOrder;

  factory SpeciesImage.fromMedia(Map<String, dynamic> j) => SpeciesImage(
        id: (j['media_id'] ?? '').toString(),
        url: (j['file_url'] ?? '').toString(),
        thumbnailUrl: j['thumbnail_url'] as String?,
        isFeatured: (j['is_featured'] ?? false) as bool,
        approved: (j['published'] ?? true) as bool,
        photographer: j['photographer'] as String?,
        license: j['license'] as String?,
        source: j['copyright_holder'] as String?,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );
}

/// Reads/writes the master species image library (the `media` table +
/// `species.hero_image` for the featured pick). No other tables are touched.
class SpeciesImageRepository {
  const SpeciesImageRepository();

  static const String bucket = 'media';

  Future<List<SpeciesImage>> imagesFor(String speciesId) async {
    if (!SupabaseService.isConfigured) return const [];
    final rows = await SupabaseService.client
        .from('media')
        .select()
        .eq('species_id', speciesId)
        .eq('media_type', 'image')
        .order('sort_order', ascending: true) as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(SpeciesImage.fromMedia)
        .where((i) => i.url.trim().isNotEmpty)
        .toList();
  }

  /// All species-linked image rows (one query) for the audit report.
  Future<Map<String, int>> galleryCounts() async {
    if (!SupabaseService.isConfigured) return const {};
    final rows = await SupabaseService.client
        .from('media')
        .select('species_id')
        .eq('media_type', 'image')
        .not('species_id', 'is', null) as List;
    final counts = <String, int>{};
    for (final r in rows) {
      final id = (r as Map)['species_id']?.toString();
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  String _slug(String s) {
    final b = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return b.isEmpty ? 'image' : b;
  }

  /// Uploads an image for a species and records it in the master library.
  /// The first image (or [featured]) also becomes the species' featured photo.
  Future<void> upload({
    required Species species,
    required Uint8List bytes,
    required String filename,
    String contentType = 'image/jpeg',
    bool featured = false,
    String? photographer,
    String? license,
  }) async {
    final client = SupabaseService.client;
    final path = 'species/${species.id}/'
        '${DateTime.now().millisecondsSinceEpoch}_${_slug(filename)}';
    await client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    final url = client.storage.from(bucket).getPublicUrl(path);

    final existing = await imagesFor(species.id);
    final makeFeatured = featured || existing.isEmpty;

    await client.from('media').insert({
      'species_id': species.id,
      'media_type': 'image',
      'file_url': url,
      'thumbnail_url': url,
      'title': species.commonName,
      'alt_text': species.commonName,
      'photographer': photographer,
      'license': license,
      'is_featured': makeFeatured,
      'sort_order': existing.length,
      'published': true,
    });
    if (makeFeatured) await _setHero(species.id, url);
  }

  Future<void> setFeatured(String speciesId, SpeciesImage image) async {
    final client = SupabaseService.client;
    // Clear other featured flags, set this one.
    await client
        .from('media')
        .update({'is_featured': false})
        .eq('species_id', speciesId)
        .eq('media_type', 'image');
    await client.from('media').update({'is_featured': true}).eq(
        'media_id', image.id);
    await _setHero(speciesId, image.url);
  }

  Future<void> setApproved(SpeciesImage image, bool approved) =>
      SupabaseService.client
          .from('media')
          .update({'published': approved}).eq('media_id', image.id);

  Future<void> setMeta(SpeciesImage image,
          {String? photographer, String? license}) =>
      SupabaseService.client.from('media').update({
        'photographer': ?photographer,
        'license': ?license,
      }).eq('media_id', image.id);

  /// Persists a new gallery order (index = sort_order).
  Future<void> reorder(List<SpeciesImage> ordered) async {
    final client = SupabaseService.client;
    for (var i = 0; i < ordered.length; i++) {
      await client
          .from('media')
          .update({'sort_order': i}).eq('media_id', ordered[i].id);
    }
  }

  /// Removes an image; if it was the featured pick, promotes the next one.
  Future<void> delete(String speciesId, SpeciesImage image) async {
    final client = SupabaseService.client;
    await client.from('media').delete().eq('media_id', image.id);
    if (image.isFeatured) {
      final rest = await imagesFor(speciesId);
      if (rest.isNotEmpty) {
        await setFeatured(speciesId, rest.first);
      } else {
        await _setHero(speciesId, null);
      }
    }
  }

  Future<void> _setHero(String speciesId, String? url) => SupabaseService.client
      .from('species')
      .update({'hero_image': url}).eq('species_id', speciesId);
}

final speciesImageRepositoryProvider =
    Provider<SpeciesImageRepository>((ref) => const SpeciesImageRepository());

/// Bumps to force a refresh after a write.
class SpeciesImageRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final speciesImageRefreshProvider =
    NotifierProvider<SpeciesImageRefresh, int>(SpeciesImageRefresh.new);

/// Images for a single species (master library).
final speciesImagesProvider =
    FutureProvider.family<List<SpeciesImage>, String>((ref, speciesId) {
  ref.watch(speciesImageRefreshProvider);
  return ref.watch(speciesImageRepositoryProvider).imagesFor(speciesId);
});

/// One audit row per species (Phase 3).
class SpeciesImageAudit {
  const SpeciesImageAudit({
    required this.species,
    required this.hasFeatured,
    required this.galleryCount,
  });
  final Species species;
  final bool hasFeatured;
  final int galleryCount;
  bool get needsImage => !hasFeatured && galleryCount == 0;
}

/// The image-audit report across every species.
final speciesImageAuditProvider =
    FutureProvider<List<SpeciesImageAudit>>((ref) async {
  ref.watch(speciesImageRefreshProvider);
  final species = await ref.watch(allSpeciesProvider.future);
  final counts = await ref.watch(speciesImageRepositoryProvider).galleryCounts();
  final out = [
    for (final s in species)
      SpeciesImageAudit(
        species: s,
        hasFeatured: (s.heroImageUrl ?? '').trim().isNotEmpty,
        galleryCount: counts[s.id] ?? 0,
      ),
  ];
  out.sort((a, b) => a.species.commonName
      .toLowerCase()
      .compareTo(b.species.commonName.toLowerCase()));
  return out;
});
