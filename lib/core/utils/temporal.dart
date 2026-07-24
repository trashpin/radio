/// Shared temporal/environment enums used across features.
///
/// These describe the environment a decision is made in (time of day, season)
/// plus a weather placeholder. They live in `core` so multiple engines (the
/// Radio AI Producer and the GPS Intelligence Engine) share ONE definition
/// instead of duplicating the logic.
library;

/// Coarse buckets of the day, derived from the clock.
enum TimeOfDayBucket {
  earlyMorning,
  morning,
  afternoon,
  evening,
  night;

  static TimeOfDayBucket fromDateTime(DateTime time) {
    final h = time.hour;
    if (h < 5) return TimeOfDayBucket.night;
    if (h < 9) return TimeOfDayBucket.earlyMorning;
    if (h < 12) return TimeOfDayBucket.morning;
    if (h < 17) return TimeOfDayBucket.afternoon;
    if (h < 21) return TimeOfDayBucket.evening;
    return TimeOfDayBucket.night;
  }
}

/// Season (northern-hemisphere mapping by default).
enum Season {
  spring,
  summer,
  autumn,
  winter;

  static Season fromDateTime(DateTime time) {
    switch (time.month) {
      case 3:
      case 4:
      case 5:
        return Season.spring;
      case 6:
      case 7:
      case 8:
        return Season.summer;
      case 9:
      case 10:
      case 11:
        return Season.autumn;
      default:
        return Season.winter;
    }
  }
}

/// Weather condition (PLACEHOLDER — always `unknown` until a weather service is
/// integrated).
enum WeatherCondition { unknown, clear, cloudy, rain, snow, fog }
