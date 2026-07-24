import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explorer_os_mobile/core/constants/app_constants.dart';
import 'package:explorer_os_mobile/core/error/error_handler.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// Data-access layer for destinations.
///
/// The ONLY place that knows how destinations are stored/queried in Supabase.
/// Keeping queries here (not in the UI or providers) isolates schema knowledge
/// and keeps the widget/provider layers thin and testable. The app is
/// read-only, so this class only reads.
class DestinationRepository {
  const DestinationRepository(this._client);

  final SupabaseClient _client;

  /// Loads all destinations from the `destinations` table, alphabetized.
  /// Backend/network errors are normalized to a friendly `AppException`.
  Future<List<Destination>> fetchDestinations() async {
    try {
      final rows = await _client
          .from(AppConstants.destinationsTable)
          .select()
          .order('name', ascending: true);

      return rows
          .map((row) => Destination.fromJson(row))
          .toList(growable: false);
    } catch (error, stackTrace) {
      throw ErrorHandler.from(error, stackTrace);
    }
  }
}

/// Provides a [DestinationRepository] wired to the shared Supabase client.
final destinationRepositoryProvider = Provider<DestinationRepository>((ref) {
  return DestinationRepository(ref.watch(supabaseClientProvider));
});
