/// Time-of-day / season / weather awareness for banter selection.
///
/// These dimensions are encoded on a clip via its existing `tags` (e.g.
/// `morning`, `sunny`, `summer`) — so no schema change is needed. A clip with
/// no tag for a dimension is universal for that dimension; a clip tagged for a
/// dimension only plays when the live moment matches.
enum BanterTimeOfDay {
  morning('morning'),
  afternoon('afternoon'),
  evening('evening'),
  night('night');

  const BanterTimeOfDay(this.tag);
  final String tag;

  static BanterTimeOfDay fromHour(int hour) {
    if (hour < 6) return BanterTimeOfDay.night;
    if (hour < 12) return BanterTimeOfDay.morning;
    if (hour < 17) return BanterTimeOfDay.afternoon;
    if (hour < 21) return BanterTimeOfDay.evening;
    return BanterTimeOfDay.night;
  }
}

enum BanterSeason {
  winter('winter'),
  spring('spring'),
  summer('summer'),
  fall('fall');

  const BanterSeason(this.tag);
  final String tag;

  /// Northern-hemisphere season from month (1..12).
  static BanterSeason fromMonth(int month) {
    if (month == 12 || month <= 2) return BanterSeason.winter;
    if (month <= 5) return BanterSeason.spring;
    if (month <= 8) return BanterSeason.summer;
    return BanterSeason.fall;
  }
}

const _todTags = {'morning', 'afternoon', 'evening', 'night'};
const _seasonTags = {'winter', 'spring', 'summer', 'fall'};
const _weatherTags = {
  'sunny', 'cloudy', 'rain', 'storm', 'fog', 'windy', 'hot', 'cold',
};

/// Normalizes a free-form weather phrase (+ optional temp) into weather tags.
Set<String> weatherTagsFor(String? condition, {double? tempF}) {
  final c = (condition ?? '').toLowerCase();
  final out = <String>{};
  if (c.contains('storm') || c.contains('thunder')) out.add('storm');
  if (c.contains('rain') || c.contains('drizzle') || c.contains('shower')) {
    out.add('rain');
  }
  if (c.contains('fog') || c.contains('mist')) out.add('fog');
  if (c.contains('wind') || c.contains('breez')) out.add('windy');
  if (c.contains('cloud') || c.contains('overcast')) out.add('cloudy');
  if (c.contains('sun') || c.contains('clear')) out.add('sunny');
  if (tempF != null) {
    if (tempF >= 88) out.add('hot');
    if (tempF <= 45) out.add('cold');
  }
  return out;
}

/// The live moment used to filter banter.
class BanterMoment {
  const BanterMoment({
    required this.timeOfDay,
    required this.season,
    this.weather = const {},
  });

  final BanterTimeOfDay timeOfDay;
  final BanterSeason season;
  final Set<String> weather;

  factory BanterMoment.now({
    DateTime? at,
    String? weatherCondition,
    double? tempF,
  }) {
    final t = at ?? DateTime.now();
    return BanterMoment(
      timeOfDay: BanterTimeOfDay.fromHour(t.hour),
      season: BanterSeason.fromMonth(t.month),
      weather: weatherTagsFor(weatherCondition, tempF: tempF),
    );
  }
}

/// True if [clipTags] are compatible with [moment]: for each dimension the clip
/// tags, the moment must match at least one; untagged dimensions are universal.
bool clipMatchesMoment(List<String> clipTags, BanterMoment moment) {
  final tags = clipTags.map((t) => t.toLowerCase()).toSet();

  bool dimensionOk(Set<String> dimTags, Set<String> momentTags) {
    final clipDim = tags.intersection(dimTags);
    if (clipDim.isEmpty) return true; // clip is universal for this dimension
    if (momentTags.isEmpty) return true; // moment unknown → don't over-filter
    return clipDim.intersection(momentTags).isNotEmpty;
  }

  return dimensionOk(_todTags, {moment.timeOfDay.tag}) &&
      dimensionOk(_seasonTags, {moment.season.tag}) &&
      dimensionOk(_weatherTags, moment.weather);
}
