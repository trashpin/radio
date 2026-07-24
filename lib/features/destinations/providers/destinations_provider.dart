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

/// Looks up a single destination by id from the loaded list.
///
/// Used by the Destination Details screen so it can be opened by id (a
/// deep-link-friendly route) rather than passing the whole object around.
/// Returns null if the destination isn't among the loaded results.
final destinationByIdProvider =
    Provider.family<Destination?, String>((ref, id) {
  final all = ref.watch(destinationsProvider).value ?? const [];
  for (final destination in all) {
    if (destination.id == id) return destination;
  }
  return null;
});
