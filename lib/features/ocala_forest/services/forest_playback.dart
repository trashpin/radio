import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';

/// Shared "Listen"/"Navigate" actions for [ForestLocation] — used by
/// Discoveries, What's Around Me, and Trails so every experience screen
/// plays through the exact same existing mechanism
/// (`requestInterruption` + play-if-idle) rather than each rolling its own.
/// `contextKind: 'forest'` lets the existing "Tell Me More" button (on
/// whatever segment ends up playing) resolve through the new forest case in
/// `tell_me_more_mapping.dart`.
void playForestLocation(WidgetRef ref, ForestLocation loc) {
  final radio = ref.read(radioEngineControllerProvider.notifier);
  final text = (loc.narrationShort ?? loc.description ?? '').trim();
  radio.requestInterruption(
    AudioSegment(
      id: 'forest:manual:${loc.id}:${DateTime.now().microsecondsSinceEpoch}',
      title: loc.name,
      artist: 'DJ Sunny',
      type: AudioSegmentType.gpsNarration,
      priority: PlaybackPriority.scheduledAnnouncement,
      imageUrl: loc.imageUrl,
      audioUrl: loc.hasAudio ? loc.audioUrl : null,
      spokenText:
          loc.hasAudio ? null : (text.isNotEmpty ? text : "That's ${loc.name}."),
      location: GeoPoint(latitude: loc.latitude, longitude: loc.longitude),
      tags: const ['ocala_forest'],
      interruptible: true,
      resumeAfter: true,
      tellMeMoreContext: TellMeMoreContext(
        subject: loc.name,
        locationId: loc.id,
        contextKind: 'forest',
        location: GeoPoint(latitude: loc.latitude, longitude: loc.longitude),
      ),
    ),
  );
  if (ref.read(radioEngineControllerProvider).status != PlaybackStatus.playing) {
    radio.play();
  }
}

Future<void> navigateToForestLocation(ForestLocation loc) async {
  final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${loc.latitude},${loc.longitude}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
