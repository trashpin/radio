import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/narration/models/narration_type.dart';

/// Composes a structured, tour-guide narration script from a record's existing
/// data — deterministically, with no external AI call.
///
/// This is the "AI Script Generator" content-creation step: it runs once during
/// authoring (never during user playback) and produces a script with a friendly
/// intro, identification, background, facts, habitat, safety, conservation, and
/// a closing line. The [compose] method is a pure function (easily unit-tested);
/// swap in a real LLM later by implementing the same signature behind a seam.
class NarrationScriptComposer {
  const NarrationScriptComposer();

  /// Average narration pace (~150 words/min) used for speaking-time estimates.
  static const double wordsPerSecond = 2.5;

  String composeForSpecies(Species s,
      {NarrationType type = NarrationType.standardRanger}) {
    final name = s.commonName;
    final sections = <String>[];

    // 1. Friendly introduction (tone varies by style).
    sections.add(_intro(type, name));

    // 2. Identification.
    final id = _identification(s);
    if (id != null && type != NarrationType.safetyInformation) {
      sections.add(id);
    }

    // 3. History / background.
    if (_has(s.description) &&
        type != NarrationType.safetyInformation &&
        type != NarrationType.kidsGuide) {
      sections.add(s.description!.trim());
    }

    // 4. Interesting facts.
    if (_has(s.funFacts) &&
        (type == NarrationType.natureFacts ||
            type == NarrationType.deepDive ||
            type == NarrationType.standardRanger ||
            type == NarrationType.kidsGuide ||
            type == NarrationType.familyGuide)) {
      sections.add("Here's something interesting: ${_clean(s.funFacts!)}");
    }

    // 5. Diet / behavior (habitat-style context).
    if (type == NarrationType.deepDive || type == NarrationType.natureFacts) {
      if (_has(s.diet)) sections.add('Diet: ${_clean(s.diet!)}');
      if (_has(s.behavior)) sections.add('Behavior: ${_clean(s.behavior!)}');
    }

    // 6. Photographer tips (uses appearance cues).
    if (type == NarrationType.photographerTips) {
      sections.add(_photoTip(s));
    }

    // 7. Safety.
    if (_has(s.safetyInfo)) {
      sections.add('A quick safety note: ${_clean(s.safetyInfo!)}');
    } else if (type == NarrationType.safetyInformation) {
      sections.add(
          'Always observe wildlife from a safe distance and never feed or approach animals.');
    }

    // 8. Conservation.
    if (_has(s.conservationStatus)) {
      sections.add(
          'Conservation status: ${_clean(s.conservationStatus!)}. Every visitor helps protect this species by staying on trails and leaving no trace.');
    }

    // 9. Closing.
    sections.add(_closing(type, name));

    return sections.map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n\n');
  }

  /// Estimated speaking time in seconds for a script.
  int estimateSeconds(String script) {
    final words = script.trim().isEmpty
        ? 0
        : script.trim().split(RegExp(r'\s+')).length;
    return (words / wordsPerSecond).round();
  }

  int wordCount(String script) =>
      script.trim().isEmpty ? 0 : script.trim().split(RegExp(r'\s+')).length;

  // --- helpers ---

  bool _has(String? v) => v != null && v.trim().isNotEmpty;
  String _clean(String v) {
    final t = v.trim();
    return t.endsWith('.') || t.endsWith('!') || t.endsWith('?') ? t : '$t.';
  }

  String _intro(NarrationType type, String name) {
    switch (type) {
      case NarrationType.adventureGuide:
        return "Alright explorers — keep your eyes open, because up ahead is the $name!";
      case NarrationType.familyGuide:
        return "Gather round, everyone. Let's meet the $name together.";
      case NarrationType.kidsGuide:
        return "Hey there, junior ranger! Guess what we found — a $name!";
      case NarrationType.photographerTips:
        return "If you've got your camera ready, the $name makes a wonderful subject.";
      case NarrationType.natureFacts:
        return "Let's talk about the $name.";
      case NarrationType.safetyInformation:
        return "Before we go on, here's what you should know about the $name.";
      case NarrationType.deepDive:
        return "Welcome to a deep dive on the $name.";
      case NarrationType.seasonal:
        return "This time of year is a great time to spot the $name.";
      case NarrationType.standardRanger:
        return "Welcome. Let's take a closer look at the $name.";
    }
  }

  String? _identification(Species s) {
    final bits = <String>[
      if (_has(s.scientificName)) 'known to scientists as ${s.scientificName}',
      if (_has(s.size)) 'about ${_clean(s.size!).replaceAll('.', '')}',
      if (_has(s.color)) 'with ${_clean(s.color!).replaceAll('.', '')} coloring',
      if (_has(s.specialMarkings)) _clean(s.specialMarkings!).replaceAll('.', ''),
    ];
    if (bits.isEmpty) return null;
    return 'You can recognize the ${s.commonName} — ${bits.join(', ')}.';
  }

  String _photoTip(Species s) {
    final light = _has(s.color)
        ? 'Soft morning light brings out its ${_clean(s.color!).replaceAll('.', '')} tones.'
        : 'Soft morning or late-afternoon light works best.';
    return "Photography tip: $light Keep a respectful distance and use a longer lens.";
  }

  String _closing(NarrationType type, String name) {
    switch (type) {
      case NarrationType.kidsGuide:
        return "Great spotting! Let's see what else we can find.";
      case NarrationType.adventureGuide:
        return "Onward, explorers — the trail has more surprises ahead.";
      case NarrationType.familyGuide:
        return "Take a moment to enjoy the $name, then let's continue our journey.";
      default:
        return "Thanks for exploring the $name with us. Keep discovering.";
    }
  }
}
