import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_home/controllers/discover_audio_controller.dart';
import 'package:explorer_os_mobile/features/discover_home/data/discover_interactions_repository.dart';
import 'package:explorer_os_mobile/features/discover_home/data/discover_narration_service.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';

/// "🎧 Hear About It" — always AI-synthesizes a short teaser (never just
/// reads a database field verbatim, per spec), routed through
/// [DiscoverAudioController] so it can never surface as radio content and
/// the radio is paused/resumed around it automatically.
Future<void> hearAboutIt(
  BuildContext context,
  WidgetRef ref,
  DiscoverableItem item, {
  Set<String> matchedInterests = const {},
}) async {
  ref.read(discoverInteractionsRepositoryProvider).log(item, 'heard');
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(
      content: Row(children: [
        SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Getting the story ready…'),
      ]),
      duration: Duration(seconds: 20),
    ),
  );
  final narration = await ref
      .read(discoverNarrationServiceProvider)
      .requestFor(item, kind: 'short', matchedInterests: matchedInterests);
  messenger.hideCurrentSnackBar();

  final audio = ref.read(discoverAudioControllerProvider.notifier);
  if (narration != null) {
    await audio.play(title: item.title, audioUrl: narration.audioUrl, spokenText: narration.text);
  } else if ((item.teaser ?? '').isNotEmpty) {
    // Generation failed — fall back to speaking what we already know rather
    // than doing nothing.
    await audio.play(title: item.title, spokenText: item.teaser);
  } else if (context.mounted) {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't load audio right now.")));
  }
}

/// "Tell Me More" (long-form) — used when the detail screen has no
/// substantive recorded/written history to show and the visitor asks to
/// hear more anyway.
Future<void> tellMeMoreAudio(
  BuildContext context,
  WidgetRef ref,
  DiscoverableItem item, {
  Set<String> matchedInterests = const {},
}) async {
  ref.read(discoverInteractionsRepositoryProvider).log(item, 'heard');
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(
      content: Row(children: [
        SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Putting together the full story…'),
      ]),
      duration: Duration(seconds: 20),
    ),
  );
  final narration = await ref
      .read(discoverNarrationServiceProvider)
      .requestFor(item, kind: 'long', matchedInterests: matchedInterests);
  messenger.hideCurrentSnackBar();

  final audio = ref.read(discoverAudioControllerProvider.notifier);
  if (narration != null) {
    await audio.play(title: item.title, audioUrl: narration.audioUrl, spokenText: narration.text);
  } else if (context.mounted) {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't load audio right now.")));
  }
}
