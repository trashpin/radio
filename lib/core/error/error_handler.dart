import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:explorer_os_mobile/core/error/app_exception.dart';

/// Translates low-level/backend errors into the app-wide [AppException].
///
/// Repositories catch raw errors and route them through [ErrorHandler.from] so
/// the rest of the app only ever deals with a single, friendly error type.
/// Centralizing this mapping lets us improve messages globally.
class ErrorHandler {
  const ErrorHandler._();

  static AppException from(Object error, [StackTrace? stackTrace]) {
    if (error is AppException) return error;

    if (error is PostgrestException) {
      return AppException(
        'We could not load that content. Please try again.',
        type: AppExceptionType.server,
        cause: error,
      );
    }

    if (error is AuthException) {
      return AppException(
        error.message,
        type: AppExceptionType.auth,
        cause: error,
      );
    }

    if (error is SocketException || error is TimeoutException) {
      return const AppException(
        'No internet connection. Please check your network and try again.',
        type: AppExceptionType.network,
      );
    }

    return AppException(
      'Something went wrong. Please try again.',
      type: AppExceptionType.unknown,
      cause: error,
    );
  }
}
