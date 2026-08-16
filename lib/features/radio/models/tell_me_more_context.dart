import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';

/// Structured context describing what the DJ was just talking about, captured
/// at the moment a banter/narration segment is created so the future "Tell Me
/// More" feature can answer without re-deriving it from raw audio.
///
/// This is a data carrier only — it does not call an AI, fetch content, or
/// decide anything. [RadioScreen] reads it off the currently-playing
/// [AudioSegment] to enable/populate the "TELL ME MORE" button.
class TellMeMoreContext {
  const TellMeMoreContext({
    this.subject,
    this.locationId,
    this.destinationId,
    this.destinationCode,
    this.category,
    this.banterText,
    this.knowledgeContentId,
    this.location,
    this.contextKind,
  });

  /// What the DJ was talking about, in plain language (e.g. a place name).
  final String? subject;

  /// The `locations` record this moment relates to, if any. Also carries an
  /// `events` row id when [contextKind] is `'event'`.
  final String? locationId;

  /// The destination this banter was scoped to, if any.
  final String? destinationId;
  final String? destinationCode;

  /// The banter category token (e.g. `historyTease`, `hiddenGem`).
  final String? category;

  /// The exact line the DJ spoke, with placeholders already filled in.
  final String? banterText;

  /// Id of the source content/knowledge record backing this line, if any.
  final String? knowledgeContentId;

  /// Where the listener was when this played.
  final GeoPoint? location;

  /// Which location-aware player tier this came from — `'event'`, `'park'`,
  /// `'spring'`, `'town'`, or `'county'` — so the narration lookup knows
  /// which content source to query (an `events`/`locations` row, or the
  /// current county's profile). Null for the original DJ-banter-category
  /// path (unchanged).
  final String? contextKind;

  bool get hasContext =>
      (subject ?? banterText ?? destinationId ?? locationId) != null;
}
