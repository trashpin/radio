import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/weather/weather_service.dart';

/// Shared, throttled current-forecast cache. One place the radio (banter +
/// county welcome), Explore, and Explorer Mode can read the live weather —
/// fetched at most every 20 minutes (or when the user moves notably), so
/// weather-aware banter fires without hammering the API.
class CurrentWeather extends Notifier<WeatherData?> {
  DateTime? _lastFetch;
  double? _lat;
  double? _lng;

  @override
  WeatherData? build() => null;

  Future<void> refresh(double latitude, double longitude) async {
    final now = DateTime.now();
    final moved = _lat == null ||
        (latitude - _lat!).abs() + (longitude - _lng!).abs() > 0.03; // ~2mi
    final fresh = _lastFetch != null &&
        now.difference(_lastFetch!) < const Duration(minutes: 20);
    if (!moved && fresh && state != null) return;
    _lat = latitude;
    _lng = longitude;
    _lastFetch = now;
    try {
      final w = await ref.read(weatherClientProvider).fetch(latitude, longitude);
      if (w != null) state = w;
    } catch (_) {
      // Keep the last good forecast on failure.
    }
  }
}

final currentWeatherProvider =
    NotifierProvider<CurrentWeather, WeatherData?>(CurrentWeather.new);
