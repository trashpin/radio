import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/error_handler.dart';
import '../../models/destination.dart';
import '../../services/supabase_service.dart';

/// Data-access layer for destinations.
///
/// This is the ONLY place that knows how destinations are stored/queried in
/// Supabase. Keeping the query here (rather than in the UI) means the widget
/// layer stays dumb and testable, and any change to the backend schema is
/// isolated to this file. The app is read-only, so this class only reads.
class DestinationRepository {
  const DestinationRepository(this._client);

  final SupabaseClient _client;

  /// Loads all destinations from the `destinations` table.
  ///
  /// Any backend/network error is normalized to a friendly [AppException] via
  /// [ErrorHandler] so the UI can show a consistent message.
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
