import 'package:explorer_os_mobile/core/utils/temporal.dart';
import 'package:explorer_os_mobile/features/gps/models/destination_context.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_heading.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/nearby_destination.dart';
import 'package:explorer_os_mobile/features/gps/models/route_progress.dart';
import 'package:explorer_os_mobile/features/gps/models/speed_state.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_session.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_statistics.dart';
import 'package:explorer_os_mobile/features/gps/models/upcoming_destination.dart';

/// THE published output of the GPS Intelligence Engine.
///
/// This immutable snapshot bundles everything downstream systems need to make
/// audio decisions: where the user is (state/park/destination/road), how
/// they're moving (heading/speed/mode/movement), what's around and ahead
/// (nearest/next attraction + distance/ETA), what they've seen (visited stops),
/// and the environment (time of day/season/weather placeholder).
///
/// The AI Producer maps this directly into its `ProducerContext`, and the Radio
/// Engine uses it to interrupt/insert location audio. It is produced by the
/// TravelContextService and re-emitted on every meaningful location update.
class TravelContext {
  const TravelContext({
    required this.timestamp,
    this.location,
    this.currentStateCode,
    this.currentStateName,
    this.currentCity,
    this.currentCounty,
    this.currentRegion,
    this.currentParkId,
    this.currentDestinationId,
    this.currentDestination,
    this.currentRoad,
    this.heading,
    this.bearingDegrees,
    this.altitudeMeters,
    this.speed,
    this.travelMode = TravelMode.stationary,
    this.movementState = MovementState.idle,
    this.arrivalStatus,
    this.isParked = false,
    this.distanceTravelledMeters = 0,
    this.nearestAttraction,
    this.nextAttraction,
    this.estimatedArrival,
    this.nearbyDestinations = const [],
    this.upcomingDestinations = const [],
    this.visitedStopIds = const [],
    this.routeProgress,
    this.distanceRemainingMeters,
    this.statistics = TravelStatistics.empty,
    this.travelSession,
    this.currentRadioStationId,
    this.weather = WeatherCondition.unknown,
  });

  final DateTime timestamp;

  // Where.
  final GPSLocation? location;
  final String? currentStateCode;
  final String? currentStateName;
  final String? currentCity; // placeholder (reverse-geocoding not implemented)
  final String? currentCounty; // placeholder
  final String? currentRegion; // placeholder
  final String? currentParkId;
  final String? currentDestinationId;
  final DestinationContext? currentDestination;
  final String? currentRoad; // placeholder (reverse-geocoding not implemented)

  // How.
  final GPSHeading? heading;
  final double? bearingDegrees;
  final double? altitudeMeters;
  final SpeedState? speed;
  final TravelMode travelMode;
  final MovementState movementState;
  final ArrivalStatus? arrivalStatus;
  final bool isParked;
  final double distanceTravelledMeters;

  // What's around / ahead.
  final NearbyDestination? nearestAttraction;
  final UpcomingDestination? nextAttraction;
  final Duration? estimatedArrival;
  final List<NearbyDestination> nearbyDestinations;
  final List<UpcomingDestination> upcomingDestinations;

  // What's been seen.
  final List<String> visitedStopIds;

  // Journey progress.
  final RouteProgress? routeProgress;

  /// Distance remaining to the next stop/attraction (route-aware), when known.
  final double? distanceRemainingMeters;

  // Cumulative trip stats + the owning session.
  final TravelStatistics statistics;
  final TravelSession? travelSession;

  // Environment / cross-system placeholders.
  /// The active Explorer Radio station (placeholder; set by the coordinator that
  /// bridges GPS ↔ Radio, so downstream systems can read it from context).
  final String? currentRadioStationId;
  final WeatherCondition weather;

  bool get isMoving => movementState == MovementState.moving;

  /// Distance to the next attraction ahead, when known.
  double? get distanceToNextMeters => nextAttraction?.distanceMeters;

  TimeOfDayBucket get timeOfDay => TimeOfDayBucket.fromDateTime(timestamp);
  Season get season => Season.fromDateTime(timestamp);

  /// An empty starting context (no fix yet).
  factory TravelContext.initial() =>
      TravelContext(timestamp: DateTime.fromMillisecondsSinceEpoch(0));
}
