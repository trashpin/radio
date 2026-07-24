import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_exception.dart';

/// Translates low-level/backend errors into our app-wide [AppException].
///
/// Services (see `lib/services/`) should catch raw errors and route them
/// through [ErrorHandler.from] so the rest of the app only ever deals with a
/// single, friendly error type. Keeping this mapping in one place means we can
/// improve error messages globally without touching every call site.
class ErrorHandler {
  const ErrorHandler._();

  static AppException from(Object error, [StackTrace? stackTrace]) {
    // Already normalized — pass through unchanged.
    if (error is AppException) return error;

    // Supabase / Postgrest database errors.
    if (error is PostgrestException) {
      return AppException(
        'We could not load that content. Please try again.',
        type: AppExceptionType.server,
        cause: error,
      );
    }

    // Supabase authentication errors.
    if (error is AuthException) {
      return AppException(
        error.message,
        type: AppExceptionType.auth,
        cause: error,
      );
    }

    // Connectivity problems.
    if (error is SocketException || error is TimeoutException) {
      return const AppException(
        'No internet connection. Please check your network and try again.',
        type: AppExceptionType.network,
      );
    }

    // Anything else falls back to a generic message.
    return AppException(
      'Something went wrong. Please try again.',
      type: AppExceptionType.unknown,
      cause: error,
    );
  }
}
