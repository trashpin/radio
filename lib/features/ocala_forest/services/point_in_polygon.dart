/// A single lat/lng vertex of a polygon ring.
typedef LatLngPoint = ({double lat, double lng});

/// Standard ray-casting point-in-polygon test — counts how many times a
/// horizontal ray from [lat],[lng] crosses the ring's edges; an odd count
/// means the point is inside. This is genuinely new to the app: existing
/// boundary checks (`CountyBoundary`/`StateBoundary`) are bounding boxes and
/// `ParkBoundary` is a circle — nothing here does real polygon containment,
/// because nothing needed to until an irregular, authoritative boundary
/// (the actual Ocala National Forest shape) was required.
///
/// [ring] should be closed or open (first/last point equal or not) — both
/// work identically since the loop wraps `j` around regardless.
bool pointInRing(double lat, double lng, List<LatLngPoint> ring) {
  if (ring.length < 3) return false;
  var inside = false;
  var j = ring.length - 1;
  for (var i = 0; i < ring.length; i++) {
    final pi = ring[i];
    final pj = ring[j];
    final crosses = (pi.lat > lat) != (pj.lat > lat);
    if (crosses) {
      final xIntersect =
          (pj.lng - pi.lng) * (lat - pi.lat) / (pj.lat - pi.lat) + pi.lng;
      if (lng < xIntersect) inside = !inside;
    }
    j = i;
  }
  return inside;
}
