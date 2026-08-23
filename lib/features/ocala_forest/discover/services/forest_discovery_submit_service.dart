import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// Everything needed to save one DISCOVER report (spec §5/§6/§8) — the
/// photo bytes plus every field the capture flow collected.
class DiscoverySubmission {
  const DiscoverySubmission({
    required this.photoBytes,
    required this.mimeType,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.forestId,
    this.trailId,
    this.subtype,
    this.identification,
    this.scientificName,
    this.userConfirmation = 'unknown',
    this.userNotes,
    this.aiIdentification,
    this.aiScientificName,
    this.aiConfidence,
    this.aiExplanation,
    this.aiCaveats,
  });

  final Uint8List photoBytes;
  final String mimeType;
  final String category;
  final String? subtype;
  final String? identification;
  final String? scientificName;
  final String userConfirmation;
  final double latitude;
  final double longitude;
  final String? forestId;
  final String? trailId;
  final String? userNotes;
  final String? aiIdentification;
  final String? aiScientificName;
  final String? aiConfidence;
  final String? aiExplanation;
  final String? aiCaveats;
}

/// Uploads the photo (`forest_discovery_photos` bucket, mirroring
/// `MusicStorageService`'s exact upload pattern) then inserts the report
/// row. Generates the row's id CLIENT-SIDE and never calls `.select()`
/// after insert — the base table has no anon/authenticated SELECT policy
/// by design (migration 0051), so the confirmation screen renders from the
/// [DiscoverySubmission] the caller already has, not a re-fetch.
class ForestDiscoverySubmitService {
  ForestDiscoverySubmitService(this._client);

  final SupabaseClient _client;
  static const String _bucket = 'forest_discovery_photos';
  static const _uuid = Uuid();

  /// Returns the new discovery's id on success, or null on any failure —
  /// the caller must show a real error state, never assume success.
  Future<String?> submit(DiscoverySubmission s) async {
    try {
      final id = _uuid.v4();
      final ext = s.mimeType == 'image/png' ? 'png' : 'jpg';
      final path = '${s.category}/$id.$ext';
      await _client.storage.from(_bucket).uploadBinary(
            path,
            s.photoBytes,
            fileOptions: FileOptions(upsert: true, contentType: s.mimeType),
          );
      final photoUrl = _client.storage.from(_bucket).getPublicUrl(path);

      await _client.from('forest_discovery_reports').insert({
        'id': id,
        'forest_id': s.forestId,
        'trail_id': s.trailId,
        'category': s.category,
        'subtype': s.subtype,
        'identification': s.identification,
        'scientific_name': s.scientificName,
        'user_confirmation': s.userConfirmation,
        'photo_url': photoUrl,
        'latitude': s.latitude,
        'longitude': s.longitude,
        'user_notes': s.userNotes,
        'ai_identification': s.aiIdentification,
        'ai_scientific_name': s.aiScientificName,
        'ai_confidence': s.aiConfidence,
        'ai_explanation': s.aiExplanation,
        'ai_caveats': s.aiCaveats,
      });
      return id;
    } catch (_) {
      return null;
    }
  }

  /// "Add a note" (spec §6) — appends to an existing report the visitor
  /// just saved. Update is open the same way insert is (migration 0051).
  Future<bool> addNote(String discoveryId, String note) async {
    try {
      await _client
          .from('forest_discovery_reports')
          .update({'user_notes': note}).eq('id', discoveryId);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final forestDiscoverySubmitServiceProvider = Provider<ForestDiscoverySubmitService>((ref) {
  return ForestDiscoverySubmitService(ref.watch(supabaseClientProvider));
});
