/// Central registry of bundled asset paths.
///
/// Referencing assets through named constants (instead of raw string paths
/// scattered in widgets) prevents typos and makes it trivial to rename or swap
/// assets in one place.
class AssetPaths {
  const AssetPaths._();

  static const String _images = 'assets/images';

  /// Full-bleed hero background used on the Home dashboard.
  static const String heroLandscape = '$_images/hero_landscape.png';
}
