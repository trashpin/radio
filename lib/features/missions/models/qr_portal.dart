/// A physical QR marker (`qr_portals`, migration 0061). The QR code itself
/// encodes only [code] — never a URL — so scanning always interacts with the
/// game (spec: "The QR code should NOT simply open an external webpage").
class QrPortal {
  const QrPortal({
    required this.id,
    required this.code,
    this.missionStopId,
    this.oldWorldId,
    this.isGlobal = false,
    this.requiresGpsProximity = true,
    this.active = true,
  });

  final String id;
  final String code;
  final String? missionStopId;
  final String? oldWorldId;

  /// True: this marker resolves against whatever mission/stop the scanning
  /// player currently has active, rather than one hardcoded stop — the "same
  /// physical QR marker reusable across multiple missions" case.
  final bool isGlobal;
  final bool requiresGpsProximity;
  final bool active;

  factory QrPortal.fromJson(Map<String, dynamic> j) => QrPortal(
        id: (j['id'] ?? '').toString(),
        code: (j['code'] ?? '') as String,
        missionStopId: j['mission_stop_id']?.toString(),
        oldWorldId: j['old_world_id']?.toString(),
        isGlobal: (j['is_global'] ?? false) as bool,
        requiresGpsProximity: (j['requires_gps_proximity'] ?? true) as bool,
        active: (j['active'] ?? true) as bool,
      );

  Map<String, dynamic> toWrite() => {
        'code': code,
        'mission_stop_id': missionStopId,
        'old_world_id': oldWorldId,
        'is_global': isGlobal,
        'requires_gps_proximity': requiresGpsProximity,
        'active': active,
      };
}
