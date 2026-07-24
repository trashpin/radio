/// A typed error model for ExplorerOS-Mobile.
///
/// Instead of throwing raw `Exception`s or leaking backend-specific errors into
/// the UI, the app converts everything into an [AppException]. This gives us a
/// single, predictable error shape that widgets can display and that we can log
/// consistently. The `type` field lets the UI react differently to, say, a
/// network problem vs. an authentication problem.
enum AppExceptionType {
  network,
  auth,
  notFound,
  server,
  unknown,
}

class AppException implements Exception {
  const AppException(
    this.message, {
    this.type = AppExceptionType.unknown,
    this.cause,
  });

  /// A user-friendly message safe to show in the UI.
  final String message;

  /// The category of failure, used to pick icons/retry behavior in the UI.
  final AppExceptionType type;

  /// The original error (e.g. a `PostgrestException`) kept for logging/debugging.
  final Object? cause;

  @override
  String toString() => 'AppException($type): $message';
}
