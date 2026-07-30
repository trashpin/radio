import 'package:explorer_os_mobile/features/admin/media_search/logic/image_ranking.dart';
import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';

/// How the gallery is ordered after the quality gate + ranking.
enum ImageSort { relevance, newest, popular }

/// Orientation the admin wants to keep.
enum OrientationFilter { any, landscape, portrait }

/// The admin-tunable filter set for the search gallery.
class ImageFilters {
  const ImageFilters({
    this.orientation = OrientationFilter.any,
    this.minWidth = kMinImageWidth,
    this.licenseContains,
    this.photoOnly = true,
    this.excludeIllustrations = true,
    this.sort = ImageSort.relevance,
  });

  final OrientationFilter orientation;
  final int minWidth;

  /// When set, keep only licenses whose label contains this token (e.g. "cc0",
  /// "by", "public domain").
  final String? licenseContains;
  final bool photoOnly;
  final bool excludeIllustrations;
  final ImageSort sort;

  ImageFilters copyWith({
    OrientationFilter? orientation,
    int? minWidth,
    String? licenseContains,
    bool clearLicense = false,
    bool? photoOnly,
    bool? excludeIllustrations,
    ImageSort? sort,
  }) =>
      ImageFilters(
        orientation: orientation ?? this.orientation,
        minWidth: minWidth ?? this.minWidth,
        licenseContains:
            clearLicense ? null : (licenseContains ?? this.licenseContains),
        photoOnly: photoOnly ?? this.photoOnly,
        excludeIllustrations: excludeIllustrations ?? this.excludeIllustrations,
        sort: sort ?? this.sort,
      );

  bool _orientationOk(ImageSearchResult r) => switch (orientation) {
        OrientationFilter.any => true,
        OrientationFilter.landscape =>
          r.orientation == ImageOrientation.landscape ||
              r.orientation == ImageOrientation.square ||
              r.orientation == ImageOrientation.unknown,
        OrientationFilter.portrait =>
          r.orientation == ImageOrientation.portrait,
      };

  bool _licenseOk(ImageSearchResult r) {
    final want = licenseContains?.toLowerCase().trim();
    if (want == null || want.isEmpty) return true;
    return (r.license ?? '').toLowerCase().contains(want);
  }

  /// Applies the gate ([photoOnly]/[minWidth]), the orientation + license
  /// filters, then ranks + sorts. Order is preserved from the provider for
  /// [ImageSort.newest]/[ImageSort.popular] (providers return in that order).
  List<ImageSearchResult> apply(
    List<ImageSearchResult> input, {
    required String destinationName,
  }) {
    var kept = rankAndFilter(
      input,
      destinationName: destinationName,
      minWidth: minWidth,
      requirePhoto: photoOnly || excludeIllustrations,
    );
    kept = kept
        .where((r) => _orientationOk(r) && _licenseOk(r))
        .toList(growable: false);
    if (sort == ImageSort.relevance) return kept;
    // For newest/popular we keep the provider's native order but still apply
    // the gate + filters above (the provider was asked to sort accordingly).
    final order = {for (var i = 0; i < input.length; i++) input[i].id: i};
    final byNative = [...kept]
      ..sort((a, b) => (order[a.id] ?? 1 << 30).compareTo(order[b.id] ?? 1 << 30));
    return byNative;
  }
}
