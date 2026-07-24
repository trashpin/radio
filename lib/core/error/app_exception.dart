/// A typed error model for ExplorerOS.
///
/// Rather than leaking backend-specific errors into the UI, the app converts
/// everything into an [AppException]. This gives one predictable error shape
/// that widgets can render consistently, and the `type` lets the UI react
/// differently (e.g. network vs. auth vs. not-found).
enum AppExceptionType { network, auth, notFound, server, unknown }

class AppException implements Exception {
  const AppException(
    this.message, {
    this.type = AppExceptionType.unknown,
    this.cause,
  });

  /// User-friendly message safe to show in the UI.
  final String message;

  /// Category of failure — drives icon/retry choices in the UI.
  final AppExceptionType type;

  /// Original error, kept for logging/debugging.
  final Object? cause;

  @override
  String toString() => 'AppException($type): $message';
}
