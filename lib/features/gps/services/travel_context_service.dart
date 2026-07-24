import 'package:explorer_os_mobile/core/utils/temporal.dart';
import 'package:explorer_os_mobile/features/gps/models/current_destination.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_heading.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/nearby_destination.dart';
import 'package:explorer_os_mobile/features/gps/models/speed_state.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_statistics.dart';
import 'package:explorer_os_mobile/features/gps/models/upcoming_destination.dart';

/// Assembles the published [TravelContext] from the outputs of every other
/// service.
///
/// WHY THIS EXISTS: the individual services each answer one question; SOMETHING
/// has to compose their answers into the single object downstream systems
/// consume. Keeping that assembly here (rather than in the GPSService) isolates
/// "how the context is shaped" from "how tracking is orchestrated".
class TravelContextService {
  const TravelContextService();

  TravelContext build({
    required DateTime now,
    GPSLocation? location,
    String? stateCode,
    String? stateName,
    String? parkId,
    String? destinationId,
    CurrentDestination? currentDestination,
    ArrivalStatus? arrivalStatus,
    GPSHeading? heading,
    double? bearingDegrees,
    SpeedState? speed,
    bool isParked = false,
    double distanceTravelledMeters = 0,
    NearbyDestination? nearest,
    UpcomingDestination? next,
    Duration? estimatedArrival,
    List<NearbyDestination> nearby = const [],
    List<UpcomingDestination> upcoming = const [],
    List<String> visited = const [],
    TravelStatistics statistics = TravelStatistics.empty,
    WeatherCondition weather = WeatherCondition.unknown,
  }) {
    return TravelContext(
      timestamp: now,
      location: location,
      currentStateCode: stateCode,
      currentStateName: stateName,
      currentParkId: parkId,
      currentDestinationId: destinationId,
      currentDestination: currentDestination,
      heading: heading,
      bearingDegrees: bearingDegrees,
      altitudeMeters: location?.elevationMeters,
      speed: speed,
      travelMode: speed?.travelMode ?? TravelMode.stationary,
      movementState: speed?.movementState ?? MovementState.idle,
      arrivalStatus: arrivalStatus,
      isParked: isParked,
      distanceTravelledMeters: distanceTravelledMeters,
      nearestAttraction: nearest,
      nextAttraction: next,
      estimatedArrival: estimatedArrival,
      nearbyDestinations: nearby,
      upcomingDestinations: upcoming,
      visitedStopIds: visited,
      statistics: statistics,
      weather: weather,
    );
  }
}
