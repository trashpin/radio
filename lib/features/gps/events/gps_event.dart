import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/speed_state.dart';

/// The event vocabulary published by the GPS Intelligence Engine.
///
/// WHY EVENTS: other systems (Radio Engine, AI Producer, Story Engine, UI)
/// should REACT to meaningful changes rather than constantly poll location.
/// The engine emits these on a single broadcast stream; subscribers filter for
/// the ones they care about. Using a `sealed` base enables exhaustive
/// `switch` handling at call sites.
sealed class GpsEvent {
  const GpsEvent(this.at);
  final DateTime at;
}

/// A new fix was processed (fires on every update).
class LocationUpdated extends GpsEvent {
  const LocationUpdated(super.at, this.location);
  final GPSLocation location;
}

class EnteredState extends GpsEvent {
  const EnteredState(super.at, this.code, this.name);
  final String code;
  final String name;
}

class ExitedState extends GpsEvent {
  const ExitedState(super.at, this.code, this.name);
  final String code;
  final String name;
}

class EnteredCounty extends GpsEvent {
  const EnteredCounty(super.at, this.countyId, this.name);
  final String countyId;
  final String name;
}

class ExitedCounty extends GpsEvent {
  const ExitedCounty(super.at, this.countyId, this.name);
  final String countyId;
  final String name;
}

class EnteredPark extends GpsEvent {
  const EnteredPark(super.at, this.parkId);
  final String parkId;
}

class ExitedPark extends GpsEvent {
  const ExitedPark(super.at, this.parkId);
  final String parkId;
}

class ApproachingDestination extends GpsEvent {
  const ApproachingDestination(super.at, this.destinationId);
  final String destinationId;
}

class ArrivedAtDestination extends GpsEvent {
  const ArrivedAtDestination(super.at, this.destinationId);
  final String destinationId;
}

class VisitingDestination extends GpsEvent {
  const VisitingDestination(super.at, this.destinationId);
  final String destinationId;
}

class LeavingDestination extends GpsEvent {
  const LeavingDestination(super.at, this.destinationId);
  final String destinationId;
}

class DestinationVisited extends GpsEvent {
  const DestinationVisited(super.at, this.destinationId);
  final String destinationId;
}

class NearbyDestinationDetected extends GpsEvent {
  const NearbyDestinationDetected(super.at, this.destinationId);
  final String destinationId;
}

class RouteChanged extends GpsEvent {
  const RouteChanged(super.at);
}

class HeadingChanged extends GpsEvent {
  const HeadingChanged(super.at, this.degrees);
  final double degrees;
}

class SpeedChanged extends GpsEvent {
  const SpeedChanged(super.at, this.speed);
  final SpeedState speed;
}

class TravelStarted extends GpsEvent {
  const TravelStarted(super.at);
}

class TravelStopped extends GpsEvent {
  const TravelStopped(super.at);
}

class GpsLost extends GpsEvent {
  const GpsLost(super.at);
}

class GpsRecovered extends GpsEvent {
  const GpsRecovered(super.at);
}

class BackgroundTrackingStarted extends GpsEvent {
  const BackgroundTrackingStarted(super.at);
}

class BackgroundTrackingStopped extends GpsEvent {
  const BackgroundTrackingStopped(super.at);
}
