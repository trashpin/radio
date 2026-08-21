/// A selectable narration topic for a chosen "What Is That?" candidate.
/// `id` matches the topic token the narration worker's `WIT_TOPICS` map
/// uses in `generation_jobs.notes` (`what_is_that:topic;...;topic=<id>`) —
/// keep the two in sync if either changes.
enum WhatIsThatTopic {
  history('history', 'History'),
  whatsHereNow('whats_here_now', "What's Here Now"),
  uniqueFeatures('unique_features', 'Unique Features'),
  peopleStories('people_stories', 'People & Stories'),
  accessibility('accessibility', 'Accessibility'),
  visitorInformation('visitor_information', 'Visitor Information'),
  tellMeMore('tell_me_more', 'Tell Me More');

  const WhatIsThatTopic(this.id, this.label);
  final String id;
  final String label;
}

/// A generated, topic-scoped result — a spoken script and (once the
/// narration worker has voiced it) an ElevenLabs audio URL. Mirrors one row
/// of `what_is_that_narrations`.
class WhatIsThatNarration {
  const WhatIsThatNarration({required this.script, this.audioUrl, this.voiceId});

  final String script;
  final String? audioUrl;
  final String? voiceId;

  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;

  factory WhatIsThatNarration.fromJson(Map<String, dynamic> j) =>
      WhatIsThatNarration(
        script: (j['script'] ?? '') as String,
        audioUrl: j['audio_url'] as String?,
        voiceId: j['voice_id'] as String?,
      );
}
