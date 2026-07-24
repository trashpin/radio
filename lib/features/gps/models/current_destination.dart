import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';

/// The destination/park the user is currently at or engaging with.
///
/// A focused view (distinct from the nearby/upcoming lists) that the UI and
/// audio engines use to answer "where is the user right now, and what's their
/// relationship to it?" — including [arrivalStatus] and when they arrived.
class CurrentDestination {
  const CurrentDestination({
    required this.id,
    required this.arrivalStatus,
    this.name,
    this.parkId,
    this.since,
  });

  final String id;
  final ArrivalStatus arrivalStatus;
  final String? name;
  final String? parkId;
  final DateTime? since;
}
