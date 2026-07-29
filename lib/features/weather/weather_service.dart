import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// A compact, summarized weather snapshot — never raw data.
class WeatherData {
  const WeatherData({
    this.temperatureF,
    this.highF,
    this.lowF,
    this.condition = 'clear skies',
    this.rainChance,
    this.windMph,
    this.humidity,
  });

  final double? temperatureF;
  final double? highF;
  final double? lowF;
  final String condition; // human phrase, e.g. "partly cloudy"
  final int? rainChance; // 0..100
  final double? windMph;
  final int? humidity; // 0..100

  bool get windy => (windMph ?? 0) >= 18;
  bool get rainLikely => (rainChance ?? 0) >= 40;
  bool get coolMorning => (temperatureF ?? 99) <= 62;
  bool get sunny => condition.contains('clear') || condition.contains('sunny');
}

/// WMO weather interpretation codes → a natural phrase.
String weatherPhraseForCode(int code) {
  if (code == 0) return 'sunny skies';
  if (code <= 2) return 'partly cloudy skies';
  if (code == 3) return 'overcast skies';
  if (code == 45 || code == 48) return 'areas of fog';
  if (code >= 51 && code <= 57) return 'light drizzle';
  if (code >= 61 && code <= 67) return 'periods of rain';
  if (code >= 71 && code <= 77) return 'wintry weather';
  if (code >= 80 && code <= 82) return 'passing rain showers';
  if (code >= 95) return 'thunderstorms';
  return 'changing skies';
}

/// Turns weather into a conversational radio sentence (no raw numbers dumps).
String summarizeWeather(WeatherData w) {
  final parts = <String>[];
  final cond = w.condition;
  if (w.highF != null) {
    parts.add("Today's forecast is $cond with a high near "
        '${w.highF!.round()} degrees');
  } else if (w.temperatureF != null) {
    parts.add("It's currently ${w.temperatureF!.round()} degrees with $cond");
  } else {
    parts.add("Today's forecast calls for $cond");
  }
  final rain = w.rainChance ?? 0;
  if (rain >= 60) {
    parts.add('with a good chance of rain');
  } else if (rain >= 30) {
    parts.add('and a slight chance of afternoon showers');
  }
  if (w.windy) parts.add('and breezy conditions');
  return '${parts.join(' ').trim()}.';
}

abstract class WeatherClient {
  Future<WeatherData?> fetch(double latitude, double longitude);
}

/// Free, keyless weather via Open-Meteo.
class OpenMeteoClient implements WeatherClient {
  const OpenMeteoClient({this.getFn = _defaultGet});
  final Future<http.Response> Function(Uri) getFn;

  static Future<http.Response> _defaultGet(Uri u) =>
      http.get(u, headers: {'accept': 'application/json'});

  @override
  Future<WeatherData?> fetch(double latitude, double longitude) async {
    final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$latitude'
        '&longitude=$longitude'
        '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code'
        '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code'
        '&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto');
    try {
      final res = await getFn(uri);
      if (res.statusCode != 200) return null;
      return parseOpenMeteo(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// Pure parser for an Open-Meteo forecast response.
WeatherData parseOpenMeteo(Map<String, dynamic> j) {
  double? d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
  int? i(dynamic v) => v is num ? v.round() : int.tryParse('$v');
  T? first<T>(dynamic list) =>
      (list is List && list.isNotEmpty) ? list.first as T? : null;

  final cur = (j['current'] as Map?)?.cast<String, dynamic>() ?? const {};
  final daily = (j['daily'] as Map?)?.cast<String, dynamic>() ?? const {};
  final code = i(cur['weather_code']) ??
      i(first<dynamic>(daily['weather_code'])) ??
      0;
  return WeatherData(
    temperatureF: d(cur['temperature_2m']),
    highF: d(first<dynamic>(daily['temperature_2m_max'])),
    lowF: d(first<dynamic>(daily['temperature_2m_min'])),
    condition: weatherPhraseForCode(code),
    rainChance: i(first<dynamic>(daily['precipitation_probability_max'])),
    windMph: d(cur['wind_speed_10m']),
    humidity: i(cur['relative_humidity_2m']),
  );
}

final weatherClientProvider =
    Provider<WeatherClient>((ref) => const OpenMeteoClient());
