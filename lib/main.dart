## Summary

This PR restores `lib/main.dart`, which was accidentally overwritten with shell/git text and prevented the Flutter app from compiling.

It also adds `lib/features/gps/presentation/geofence_manager_page.dart` as a temporary stub to satisfy missing imports until the real geofence UI is implemented.

## Changes

- Restored valid Dart entrypoint in `lib/main.dart`
- Added placeholder `GeofenceManagerPage` stub

## Notes

- This is a minimal fix to unblock builds and deployment.
- The stub should be replaced by the real geofence manager UI later.
- Once merged, `discover-area` should be redeployed in Vercel.

## Verification

- No runtime logic changes in this PR.
- Primary goal: unblock compilation and restore deployment readiness.
