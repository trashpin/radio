import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_audio_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';

/// Shared "Listen"/"Navigate" actions for [ForestLocation] — used by
/// Discoveries, What's Around Me, and Trails so every experience screen
/// plays through the SAME dedicated forest audio player
/// ([ForestAudioController]), never the shared Radio Engine. That engine
/// is a perpetual rotation service (it auto-fills silence with music once
/// anything it played finishes) — fine for the radio itself, wrong for a
/// one-shot "play this forest clip" request, which is what caused radio
/// music to start playing when a visitor asked for forest information.
void playForestLocation(WidgetRef ref, ForestLocation loc) {
  final text = (loc.narrationShort ?? loc.description ?? '').trim();
  ref.read(forestAudioControllerProvider.notifier).play(
        title: loc.name,
        audioUrl: loc.hasAudio ? loc.audioUrl : null,
        spokenText: loc.hasAudio ? null : (text.isNotEmpty ? text : "That's ${loc.name}."),
      );
}

Future<void> navigateToForestLocation(ForestLocation loc) async {
  final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${loc.latitude},${loc.longitude}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
