import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_story_step.dart';

class PublishResult {
  const PublishResult.success(this.message) : ok = true;
  const PublishResult.failure(this.message) : ok = false;
  final bool ok;
  final String message;
}

/// Publishes a [MissionStoryStep]'s produced content (script + audio +
/// character) into the existing runtime table the live GPS/mission player
/// actually reads — [MissionStoryEngine]/[ActiveMissionController] never
/// read `mission_story_steps` directly, so this is the ONLY bridge between
/// the Story Builder's authoring/production workflow and live gameplay.
/// Nothing about the GPS/geofencing/trigger evaluation pipeline changes;
/// this only writes ordinary content fields onto rows that pipeline already
/// reads (missions/mission_stops/mission_travel_stories/old_worlds).
class StoryStepPublisher {
  const StoryStepPublisher(this._repo);
  final MissionRepository _repo;

  Future<PublishResult> publish(MissionStoryStep step) async {
    final script = (step.script ?? '').trim();
    if (script.isEmpty) {
      return const PublishResult.failure('Write a script before publishing this step.');
    }

    switch (step.stepType) {
      case kStepTypeMissionIntroduction:
        return _publishMissionIntroduction(step);
      case kStepTypeTravelStory:
      case kStepTypeApproachStory:
        return _publishTravelOrApproach(step);
      case kStepTypeArrival:
        return _publishArrival(step);
      case kStepTypeDiscovery:
      case kStepTypeQr:
      case kStepTypeOldWorld:
      case kStepTypeClue:
        return _publishOldWorld(step);
      case kStepTypeFinalReveal:
        return _publishFinalReveal(step);
      default:
        return PublishResult.failure('Unknown step type "${step.stepType}".');
    }
  }

  Future<PublishResult> _publishMissionIntroduction(MissionStoryStep step) async {
    await _repo.updateMission(step.missionId, {
      'opening_narration_text': step.script,
      'opening_narration_audio_url': step.audioUrl,
      'intro_character_id': step.characterId,
    });
    await _markPublished(step);
    return const PublishResult.success('Published to the mission\'s Adventure Introduction.');
  }

  Future<PublishResult> _publishTravelOrApproach(MissionStoryStep step) async {
    if ((step.stopId ?? '').isEmpty) {
      return const PublishResult.failure('A travel/approach step needs a mission stop selected.');
    }
    final row = {
      'mission_id': step.missionId,
      'stop_id': step.stopId,
      'trigger_type': step.stepType == kStepTypeApproachStory ? 'approach' : 'travel',
      'trigger_distance_meters': step.triggerDistanceMeters ?? 1609.344,
      'text': step.script,
      'audio_url': step.audioUrl,
      'character_id': step.characterId,
    };
    String targetId;
    if ((step.publishedRowId ?? '').isNotEmpty) {
      await _repo.updateTravelStory(step.publishedRowId!, row);
      targetId = step.publishedRowId!;
    } else {
      targetId = await _repo.createTravelStory(row);
    }
    await _markPublished(step, publishedRowId: targetId);
    return const PublishResult.success('Published as a travel story on this stop.');
  }

  Future<PublishResult> _publishArrival(MissionStoryStep step) async {
    if ((step.stopId ?? '').isEmpty) {
      return const PublishResult.failure('An arrival step needs a mission stop selected.');
    }
    await _repo.updateStop(step.stopId!, {
      'arrival_narration_text': step.script,
      'arrival_narration_audio_url': step.audioUrl,
      'arrival_character_id': step.characterId,
    });
    await _markPublished(step);
    return const PublishResult.success('Published as this stop\'s arrival narration.');
  }

  Future<PublishResult> _publishOldWorld(MissionStoryStep step) async {
    if ((step.stopId ?? '').isEmpty) {
      return const PublishResult.failure('A discovery/QR/Old World/clue step needs a mission stop selected.');
    }
    final stops = await _repo.stopsForMission(step.missionId);
    final stop = stops.where((s) => s.id == step.stopId).firstOrNull;
    if (stop == null || (stop.oldWorldId ?? '').isEmpty) {
      return const PublishResult.failure(
          'This stop has no Old World yet — create one from the Mission Stop page first '
          '("Create QR Portal + Old World"), then publish this step.');
    }
    final fields = <String, dynamic>{'character_id': step.characterId};
    if (step.stepType == kStepTypeClue) {
      fields['clue_text'] = step.script;
    } else {
      fields['narration_text'] = step.script;
      fields['narration_audio_url'] = step.audioUrl;
    }
    await _repo.updateOldWorld(stop.oldWorldId!, fields);
    await _markPublished(step);
    return const PublishResult.success('Published to this stop\'s Old World.');
  }

  Future<PublishResult> _publishFinalReveal(MissionStoryStep step) async {
    await _repo.updateMission(step.missionId, {'final_reveal_text': step.script});
    await _markPublished(step);
    return const PublishResult.success('Published as the mission\'s Final Reveal.');
  }

  Future<void> _markPublished(MissionStoryStep step, {String? publishedRowId}) =>
      _repo.updateStoryStep(step.id, {
        'production_status': kStatusPublished,
        'published_row_id': ?publishedRowId,
      });
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

final storyStepPublisherProvider =
    Provider<StoryStepPublisher>((ref) => StoryStepPublisher(ref.read(missionRepositoryProvider)));
