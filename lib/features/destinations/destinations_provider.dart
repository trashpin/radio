import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/app_exception.dart';
import '../../models/destination.dart';
import '../../services/supabase_service.dart';
import 'destination_repository.dart';

/// Asynchronously exposes the list of destinations to the UI.
///
/// The `DestinationsScreen` watches this provider and reacts to its three
/// states automatically: loading, error, and data. Because it's a
/// `FutureProvider`, refreshing is as easy as `ref.invalidate(...)`.
///
/// If the backend isn't configured (no `.env` values), we short-circuit with a
/// friendly [AppException] instead of letting the uninitialized Supabase client
/// throw a cryptic error — this drives the "connection failed" UI path.
final destinationsProvider = FutureProvider<List<Destination>>((ref) async {
  if (!SupabaseService.isConfigured) {
    throw const AppException(
      'Cannot reach the destinations service. Please check your connection '
      'and try again.',
      type: AppExceptionType.network,
    );
  }

  final repository = ref.watch(destinationRepositoryProvider);
  return repository.fetchDestinations();
});
