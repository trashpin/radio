/// A player is "safely stopped" below this speed (~3.4 mph, brisk walking
/// pace) — the one signal gating interactive content while driving, shared
/// by the Treasure Map's clue viewer and the Guide's step content so both
/// apply the exact same rule rather than two slightly different ones.
const double kMovingSpeedThresholdMps = 1.5;

bool isMovingTooFastForInteraction(double? speedMps) =>
    (speedMps ?? 0) > kMovingSpeedThresholdMps;
