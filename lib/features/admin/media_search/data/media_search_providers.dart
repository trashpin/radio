import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/media_manager/data/media_manager_repository.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/image_filters.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// The destination the admin is currently sourcing images for.
final selectedMediaDestinationProvider =
    NotifierProvider<SelectedMediaDestination, MasterLocation?>(
        SelectedMediaDestination.new);

class SelectedMediaDestination extends Notifier<MasterLocation?> {
  @override
  MasterLocation? build() => null;
  void select(MasterLocation? d) => state = d;
}

/// The active gallery filter set (shared by the Openverse + Wikimedia tabs).
final imageFiltersProvider =
    NotifierProvider<ImageFiltersNotifier, ImageFilters>(
        ImageFiltersNotifier.new);

class ImageFiltersNotifier extends Notifier<ImageFilters> {
  @override
  ImageFilters build() => const ImageFilters();
  void set(ImageFilters f) => state = f;
}

/// Rolled-up health metrics for the Media Search Center dashboard.
class MediaDashboard {
  const MediaDashboard({
    required this.imagesImported,
    required this.storageBytes,
    required this.destinationsTotal,
    required this.destinationsWithPhotos,
    required this.missingHero,
    required this.missingAttribution,
    required this.recentlyImported,
  });

  final int imagesImported;
  final int storageBytes;
  final int destinationsTotal;
  final int destinationsWithPhotos;
  final int missingHero;
  final int missingAttribution;
  final int recentlyImported; // last 7 days

  int get destinationsWithoutPhotos => destinationsTotal - destinationsWithPhotos;

  String get storageLabel {
    final mb = storageBytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}

/// Pure dashboard computation (unit-tested).
MediaDashboard computeMediaDashboard(
  List<MediaAsset> assets,
  List<MasterLocation> destinations, {
  DateTime? now,
}) {
  final images = assets.where((a) => a.isImage).toList();
  final withPhotos = destinations
      .where((d) => d.images.any((u) => u.trim().isNotEmpty))
      .length;
  final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 7));
  final recent = images
      .where((a) => (a.createdAt ?? a.updatedAt)?.isAfter(cutoff) ?? false)
      .length;
  final missingAttr = images
      .where((a) =>
          (a.photographer ?? '').trim().isEmpty &&
          (a.license ?? '').trim().isEmpty)
      .length;
  return MediaDashboard(
    imagesImported: images.length,
    storageBytes:
        images.fold<int>(0, (sum, a) => sum + (a.fileSize ?? 0)),
    destinationsTotal: destinations.length,
    destinationsWithPhotos: withPhotos,
    missingHero: destinations
        .where((d) => !d.images.any((u) => u.trim().isNotEmpty))
        .length,
    missingAttribution: missingAttr,
    recentlyImported: recent,
  );
}

final mediaSearchDashboardProvider = Provider<MediaDashboard>((ref) {
  final assets = ref.watch(mediaAssetsProvider).value ?? const [];
  final dests = ref.watch(masterLocationsProvider).value ?? const [];
  return computeMediaDashboard(assets, dests);
});
