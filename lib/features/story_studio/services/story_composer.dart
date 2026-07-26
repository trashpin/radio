import 'dart:math';

import 'package:explorer_os_mobile/features/story_studio/models/story_category.dart';

/// A generated story draft (before review/audio).
class GeneratedStory {
  const GeneratedStory({
    required this.title,
    required this.transcript,
    required this.variation,
  });
  final String title;
  final String transcript;
  final StoryVariation variation;
  int get wordCount => transcript.split(RegExp(r'\s+')).length;
}

/// Produces varied, interpreter-style story drafts from templates + context.
///
/// This is the deterministic "generator" the pipeline uses today (an LLM key can
/// later replace [_body] to pull verified facts). It composes an opening +
/// category body + variation angle + closing, rotating phrasing so repeated
/// generations for the same place rarely read the same.
class StoryComposer {
  StoryComposer({Random? rng}) : _rng = rng ?? Random();
  final Random _rng;

  static const _openings = [
    'As you arrive at {location}, take a moment to look around.',
    'Welcome to {location}, one of the special places in {park}.',
    "You've reached {location} — and it has quite a story to tell.",
    'Right here at {location}, the landscape of {park} reveals its character.',
    'Slow down as you approach {location}; there\'s more here than meets the eye.',
  ];

  static const _closings = [
    'Take your time here, and leave it as beautiful as you found it.',
    "That's just a glimpse of {location} — every visit reveals something new.",
    'Thanks for exploring {location} with us here in {park}.',
    'Keep your eyes and ears open as you continue through {park}.',
    'Enjoy the moment — places like {location} are why we protect {park}.',
  ];

  String _categoryBody(StoryCategory c) {
    switch (c) {
      case StoryCategory.parkHistory:
        return 'For generations, this ground has drawn people who valued its '
            'water, its shade, and its quiet. The story of {park} is written in '
            'the land itself.';
      case StoryCategory.springs:
        return 'The crystal-clear water here stays a steady seventy-two degrees '
            'year round, bubbling up from the aquifer far below — a window into '
            'Florida\'s hidden rivers of stone.';
      case StoryCategory.wildlife:
        return 'Watch the edges of the clearing and the water\'s surface: '
            'white-tailed deer, wading birds, and if you\'re lucky, a river '
            'otter all make their living here.';
      case StoryCategory.geology:
        return 'Beneath your feet lies ancient limestone, slowly dissolved by '
            'rainwater over millions of years to create the springs and sinks '
            'that define this landscape.';
      case StoryCategory.trees:
      case StoryCategory.plants:
        return 'The longleaf pines and sand-pine scrub around you are a fire-'
            'adapted community — some seeds only open after the heat of a '
            'natural burn.';
      case StoryCategory.nightSky:
        return 'After dark, far from city lights, the sky here fills with stars '
            'and the faint band of the Milky Way — one of Florida\'s best '
            'stargazing spots.';
      case StoryCategory.safety:
        return 'A quick reminder: keep your distance from wildlife, carry water, '
            'and let someone know your plans before heading out on the trails.';
      case StoryCategory.legends:
      case StoryCategory.folklore:
        return 'Local lore says travelers have long told stories around these '
            'waters — tales passed from one generation of visitors to the next.';
      case StoryCategory.nativeAmericanHistory:
        return 'Long before it was a park, Indigenous peoples camped, fished, '
            'and gathered here, drawn by the same clear water you see today.';
      case StoryCategory.ccc:
        return 'In the 1930s, young men of the Civilian Conservation Corps built '
            'trails, cabins, and bridges here — much of what you enjoy today is '
            'their legacy.';
      default:
        return 'This spot is a wonderful place to learn about ${'{location}'} '
            'and everything that makes {park} worth protecting.';
    }
  }

  String _variationAngle(StoryVariation v) {
    switch (v) {
      case StoryVariation.historical:
        return 'Picture the people who came before you, and how little — and how '
            'much — has changed.';
      case StoryVariation.wildlife:
        return 'Move slowly and stay quiet, and the animals here will show '
            'themselves.';
      case StoryVariation.familyFriendly:
        return 'Kids, see how many different birds and critters you can spot '
            'before you leave!';
      case StoryVariation.photography:
        return 'Golden hour, just after sunrise or before sunset, is the perfect '
            'time to capture this place.';
      case StoryVariation.adventure:
        return 'Lace up and explore — the trails from here lead to even more '
            'hidden corners.';
      case StoryVariation.nativePlants:
        return 'Look closely at the ground cover; many of these native plants '
            'grow nowhere else on Earth.';
      case StoryVariation.funFacts:
        return 'Here\'s something surprising to share with your travel companions '
            'on the road ahead.';
    }
  }

  String _fill(String s, String location, String park) =>
      s.replaceAll('{location}', location).replaceAll('{park}', park);

  /// Composes one story for a location/category/variation.
  String compose({
    required String location,
    required StoryCategory category,
    StoryVariation variation = StoryVariation.historical,
    String park = 'Ocala National Forest',
  }) {
    final open = _openings[_rng.nextInt(_openings.length)];
    final close = _closings[_rng.nextInt(_closings.length)];
    final body = '${_categoryBody(category)} ${_variationAngle(variation)}';
    return _fill('$open $body $close', location, park)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Generates [count] varied drafts (cycling variation styles) for a location.
  List<GeneratedStory> generateVariations({
    required String location,
    required StoryCategory category,
    int count = 5,
    String park = 'Ocala National Forest',
  }) {
    final out = <GeneratedStory>[];
    for (var i = 0; i < count; i++) {
      final v = StoryVariation.values[i % StoryVariation.values.length];
      out.add(GeneratedStory(
        title: '$location — ${v.label}',
        transcript: compose(
            location: location, category: category, variation: v, park: park),
        variation: v,
      ));
    }
    return out;
  }
}
