/// Normalizes an image filename into a `match_key` used to match species.
///
/// Rules (in order): drop the extension, lowercase, spaces → underscores,
/// remove punctuation (keep a–z, 0–9, underscore), collapse duplicate
/// underscores, trim leading/trailing underscores.
///
/// Example: `Florida Black Bear.jpg` → `florida_black_bear`.
String matchKeyFromFilename(String filename) {
  var name = filename.trim();
  // Remove the file extension (last dot, if any).
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  return normalizeMatchKey(name);
}

/// Normalizes an arbitrary label (e.g. a species common name) into a match_key
/// using the same rules — so filenames and species names match consistently.
String normalizeMatchKey(String value) {
  var s = value.toLowerCase();
  s = s.replaceAll(RegExp(r'\s+'), '_'); // spaces → underscore
  s = s.replaceAll(RegExp(r'[^a-z0-9_]'), ''); // remove punctuation
  s = s.replaceAll(RegExp(r'_+'), '_'); // collapse duplicate underscores
  s = s.replaceAll(RegExp(r'^_+|_+$'), ''); // trim leading/trailing underscores
  return s;
}
