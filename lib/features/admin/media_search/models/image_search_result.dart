/// The open-license image sources the Media Search Center can query.
enum ImageSource {
  openverse('Openverse'),
  wikimedia('Wikimedia Commons'),
  upload('Upload'),
  // Future providers (scaffolded so the UI + ranking already handle them).
  flickr('Flickr Creative Commons'),
  nps('National Park Service'),
  floridaStateParks('Florida State Parks');

  const ImageSource(this.label);
  final String label;

  static ImageSource fromString(String? s) {
    final n = (s ?? '').toLowerCase();
    for (final v in ImageSource.values) {
      if (v.name.toLowerCase() == n || v.label.toLowerCase() == n) return v;
    }
    if (n.contains('openverse')) return ImageSource.openverse;
    if (n.contains('wiki')) return ImageSource.wikimedia;
    if (n.contains('flickr')) return ImageSource.flickr;
    if (n.contains('nps') || n.contains('national park')) return ImageSource.nps;
    return ImageSource.upload;
  }
}

/// Image aspect orientation.
enum ImageOrientation { landscape, portrait, square, unknown }

/// A single image returned by an [ImageSource] search — a provider-agnostic
/// shape the gallery, ranking, filters, preview, and importer all consume.
class ImageSearchResult {
  const ImageSearchResult({
    required this.source,
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.thumbnailUrl,
    this.width,
    this.height,
    this.photographer,
    this.license,
    this.licenseUrl,
    this.foreignLandingUrl,
    this.mimeType,
    this.fileSize,
    this.description,
  });

  final ImageSource source;

  /// Stable id within the provider (used for de-dup + "already imported").
  final String id;
  final String title;

  /// Full-resolution image URL (what we download on import).
  final String imageUrl;

  /// A smaller URL suitable for the gallery grid.
  final String thumbnailUrl;

  final int? width;
  final int? height;
  final String? photographer;

  /// Human license label, e.g. "CC BY-SA 4.0", "Public Domain".
  final String? license;
  final String? licenseUrl;

  /// The provider's landing/detail page (attribution + terms).
  final String? foreignLandingUrl;
  final String? mimeType;
  final int? fileSize;
  final String? description;

  int get pixels => (width ?? 0) * (height ?? 0);

  ImageOrientation get orientation {
    final w = width, h = height;
    if (w == null || h == null || w == 0 || h == 0) {
      return ImageOrientation.unknown;
    }
    final ratio = w / h;
    if (ratio > 1.15) return ImageOrientation.landscape;
    if (ratio < 0.87) return ImageOrientation.portrait;
    return ImageOrientation.square;
  }

  String get resolutionLabel {
    if (width == null || height == null) return 'Unknown size';
    return '$width × $height';
  }

  ImageSearchResult copyWith({int? width, int? height}) => ImageSearchResult(
        source: source,
        id: id,
        title: title,
        imageUrl: imageUrl,
        thumbnailUrl: thumbnailUrl,
        width: width ?? this.width,
        height: height ?? this.height,
        photographer: photographer,
        license: license,
        licenseUrl: licenseUrl,
        foreignLandingUrl: foreignLandingUrl,
        mimeType: mimeType,
        fileSize: fileSize,
        description: description,
      );
}
