import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/destinations/data/destination_repository.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// Asynchronously exposes the list of destinations to the UI.
///
/// The presentation layer watches this and reacts to its loading/error/data
/// states automatically. If the backend isn't configured we short-circuit with
/// a friendly [AppException] instead of letting the uninitialized Supabase
/// client throw — this drives the "connection failed" UI path.
final destinationsProvider = FutureProvider<List<Destination>>((ref) async {
  if (!SupabaseService.isConfigured) {
    throw const AppException(
      'Cannot reach the destinations service. Please check your connection '
      'and try again.',
      type: AppExceptionType.network,
    );
  }

  return ref.watch(destinationRepositoryProvider).fetchDestinations();
});
