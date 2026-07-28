import 'package:explorer_os_mobile/features/dj/banter_studio/banter_category.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/dj_banter_clip.dart';

/// Seed banter lines per category — conversational, GPS-aware, and full of
/// `{placeholders}` the [GpsBanterDirector] fills at playback time. These let
/// the studio "Generate" clips instantly with no API key; the OpenAI CLI tool
/// (tool/dj_banter_generate.dart) produces larger, richer batches server-side.
const Map<BanterCategory, List<String>> kDjBanterTemplates = {
  BanterCategory.welcome: [
    "Welcome aboard {station} — you're rolling into {park}, and I'll be riding along the whole way.",
    "Good to have you with us on {station}. We're deep in {county} country now, so settle in.",
    "You've found {station}. Windows down, music up — {park} is calling.",
    "Hey there, {guide_mode}! This is {station}, your soundtrack through {park}.",
    "Glad you're here. From here on, every mile of {road} comes with a story.",
  ],
  BanterCategory.arrival: [
    "Looks like you're pulling into {upcoming_attraction} — perfect timing.",
    "We've arrived at {upcoming_attraction}. Take a breath and look around.",
    "Here we are: {upcoming_attraction}, one of the best stops in {park}.",
    "You made it to {upcoming_attraction}. I'll tell you what to look for in a moment.",
  ],
  BanterCategory.historyTease: [
    "You're getting close to {upcoming_attraction}. After this next song I'll tell you the story behind it.",
    "Coming up in {county}, there's more history here than you'd guess — stick around and I'll explain.",
    "This stretch of {road} has a past worth hearing. More on that right after the music.",
    "Ever wonder who came through {park} first? Stay with me — that story's next.",
  ],
  BanterCategory.wildlifeTease: [
    "If you're looking off to the right, this is excellent habitat for {nearby_wildlife}. We'll talk more about them in just a few minutes.",
    "Keep your eyes peeled out here — {nearby_wildlife} love this part of {park}. Story coming up.",
    "This is prime {nearby_wildlife} country. After the next song, I'll tell you how to spot them.",
    "Slow down through here; {nearby_wildlife} cross often. More on that in a bit.",
  ],
  BanterCategory.plantTease: [
    "The greenery along {road} isn't random — there's a reason it grows here. I'll get into it shortly.",
    "Notice the plants around {upcoming_attraction}? Some are found almost nowhere else. Story's coming.",
    "There's a botanical surprise near {nearby_trail}. Stay tuned and I'll share it.",
  ],
  BanterCategory.birdTease: [
    "Listen closely near {nearby_river} — this is a birder's paradise. I'll name a few after this track.",
    "The skies over {park} are busy this time of year. More on the birds in a minute.",
    "If you hear something overhead, it might just be one of our local specialties. Story coming up.",
  ],
  BanterCategory.geologyTease: [
    "You're near {nearby_spring} — and the reason that water stays crystal clear all year is a great story. I'll tell it after this song.",
    "The ground beneath {park} has been shaping this place for ages. Stay with me for the how.",
    "{nearby_spring} looks simple, but what's under it is anything but. More shortly.",
  ],
  BanterCategory.interestingFact: [
    "Quick one for you: {park} hides more surprises per mile than almost anywhere in Florida.",
    "Here's something fun about {county} you can share at dinner tonight.",
    "Did you know {upcoming_attraction} has a claim to fame? I'll spill it in a second.",
  ],
  BanterCategory.scenicObservation: [
    "Take a look around — the view along {road} right now is something special.",
    "That light over {park} this time of day is hard to beat.",
    "If you can, glance toward {nearby_lake}. Postcard stuff.",
  ],
  BanterCategory.photoOpportunity: [
    "Camera ready? {upcoming_attraction} is coming up and it's a photo you'll want.",
    "Pull over safely near {nearby_lake} — this is the shot.",
    "Golden hour plus {park} equals a photo op. Don't miss it.",
  ],
  BanterCategory.trailSuggestion: [
    "If you've got time, {nearby_trail} is worth the stretch of the legs.",
    "Looking to explore on foot? {nearby_trail} is a local favorite.",
    "There's a trailhead near {upcoming_attraction} — {nearby_trail} — that rewards the effort.",
  ],
  BanterCategory.songIntro: [
    "Here's a tune that fits the drive through {park} — turn it up.",
    "Up next on {station}, something for the road along {road}.",
    "This one's for everyone rolling through {county} right now.",
  ],
  BanterCategory.songOutro: [
    "That was a good one. More music and more {park} coming up on {station}.",
    "Keep it right here — plenty more where that came from.",
    "Beautiful day for a drive. Let's keep it rolling on {station}.",
  ],
  BanterCategory.stationId: [
    "You're listening to {station} — music, stories, and discovery across {park}.",
    "{station}: your guide to {county} and beyond.",
    "This is {station}, traveling right alongside you.",
  ],
  BanterCategory.promotion: [
    "Enjoying the ride? Tell a friend to tune into {station} on their next trip through {park}.",
    "{station} rides free with every mile — no ads, just the road and the story.",
    "Save your favorite stops as we go; {station} remembers them for you.",
  ],
  BanterCategory.departure: [
    "As you head out of {park}, thanks for riding along on {station}.",
    "Leaving {upcoming_attraction} behind — but the road's got more for us. Stay tuned.",
    "Safe travels out of {county}. {station} will be here whenever you're back.",
  ],
  BanterCategory.hiddenGem: [
    "Here's a local secret: near {upcoming_attraction}, most folks drive right past a real gem. I'll point it out.",
    "Off the beaten path around {nearby_trail}, there's something special few visitors find.",
    "Between you and me, {park} keeps a few hidden treasures. One's coming up.",
  ],
  BanterCategory.safetyReminder: [
    "Quick reminder from {station}: give {nearby_wildlife} plenty of space and pack out what you pack in.",
    "Stay hydrated out here in {park}, and keep an eye on the road along {road}.",
    "Safety first, {guide_mode} — watch for crossing wildlife through this stretch.",
  ],
  BanterCategory.familyActivity: [
    "Traveling with kids? {upcoming_attraction} has something the whole family will love.",
    "Here's a family-friendly idea near {nearby_trail} to stretch everyone's legs.",
    "Make it a scavenger hunt through {park} — see who spots {nearby_wildlife} first.",
  ],
};

/// Openers used to multiply template variety when generating many clips.
const List<String> _variationOpeners = [
  '',
  'Hey — ',
  'Alright, ',
  'Check this out: ',
  'So, ',
  'Real quick — ',
  'Heads up: ',
  'Fun one — ',
];

/// Builds up to [count] unique draft clips for [category], varying the opener so
/// large batches don't read identically. IDs are left blank (assigned by the
/// DB on insert).
List<DjBanterClip> buildBanterDrafts(
  BanterCategory category, {
  required int count,
  String? destinationCode,
  String? destinationId,
  String? gpsRegion,
  String? guideMode,
  String? voiceId,
  String? voiceName,
  BanterStatus status = BanterStatus.draft,
}) {
  final bases = kDjBanterTemplates[category] ?? const <String>[];
  if (bases.isEmpty) return const [];

  final seen = <String>{};
  final out = <DjBanterClip>[];
  var i = 0;
  // Cycle base × opener combinations until we have `count` unique lines (or run
  // out of combinations).
  final maxCombos = bases.length * _variationOpeners.length;
  while (out.length < count && i < maxCombos) {
    final base = bases[i % bases.length];
    final opener = _variationOpeners[(i ~/ bases.length) % _variationOpeners.length];
    final text = _applyOpener(base, opener);
    i++;
    if (!seen.add(text)) continue;
    out.add(DjBanterClip(
      id: '',
      category: category,
      text: text,
      destinationCode: destinationCode,
      destinationId: destinationId,
      gpsRegion: gpsRegion,
      guideMode: guideMode,
      voiceId: voiceId,
      voiceName: voiceName,
      status: status,
    ));
  }
  return out;
}

String _applyOpener(String base, String opener) {
  if (opener.isEmpty) return base;
  // Lowercase the first letter of the base so the opener reads naturally.
  final first = base.isEmpty ? base : base[0].toLowerCase() + base.substring(1);
  return '$opener$first';
}
