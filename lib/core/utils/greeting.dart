/// Small pure helper that maps the current time to a friendly greeting.
///
/// Kept out of the UI layer (in `core/utils/`) so it's trivially unit-testable
/// and reusable by any widget (currently the dashboard hero header). This is a
/// deliberate example of separating simple business logic from presentation.
String greetingForTime(DateTime time) {
  final hour = time.hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}
