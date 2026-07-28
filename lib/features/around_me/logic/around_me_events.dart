/// The event vocabulary the Around Me / GPS Intelligence layer publishes.
///
/// These describe meaningful changes in the visitor's surroundings. Like the
/// core [GpsEvent]s, they are emitted on a stream and carry NO audio: the
/// Playback Manager (a later phase) subscribes and decides what, if anything,
/// to play. Using a `sealed` base enables exhaustive `switch` handling.
sealed class AroundMeEvent {
  const AroundMeEvent(this.at);
  final DateTime at;
}

/// The set of nearby experiences changed (something appeared or dropped off).
class NearbyExperiencesUpdated extends AroundMeEvent {
  const NearbyExperiencesUpdated(super.at, this.count);
  final int count;
}

/// The visitor came within trigger range of a point of interest.
class EnteredPoi extends AroundMeEvent {
  const EnteredPoi(super.at, this.id, this.name);
  final String id;
  final String name;
}

/// The visitor moved out of a point of interest's trigger range.
class ExitedPoi extends AroundMeEvent {
  const ExitedPoi(super.at, this.id, this.name);
  final String id;
  final String name;
}

/// The visitor entered a trail's trigger range.
class EnteredTrail extends AroundMeEvent {
  const EnteredTrail(super.at, this.id, this.name);
  final String id;
  final String name;
}

/// The visitor left a trail's trigger range.
class ExitedTrail extends AroundMeEvent {
  const ExitedTrail(super.at, this.id, this.name);
  final String id;
  final String name;
}

/// The current zone (park/area) changed.
class ZoneChanged extends AroundMeEvent {
  const ZoneChanged(super.at, this.zone);
  final String? zone;
}

/// The visitor stopped moving (vehicle/walking → stationary).
class VehicleStopped extends AroundMeEvent {
  const VehicleStopped(super.at);
}

/// The visitor started moving again.
class VehicleMoving extends AroundMeEvent {
  const VehicleMoving(super.at);
}

/// Positioning was lost.
class GpsSignalLost extends AroundMeEvent {
  const GpsSignalLost(super.at);
}

/// Positioning was restored.
class GpsSignalRestored extends AroundMeEvent {
  const GpsSignalRestored(super.at);
}
