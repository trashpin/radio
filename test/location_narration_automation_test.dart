import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/locations/data/location_narration_automation.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

MasterLocation _loc({List<String> audioFiles = const []}) =>
    MasterLocation.fromJson({
      'id': 'loc-1',
      'name': 'Silver Springs',
      'category': 'spring',
      'audio_files': audioFiles,
    });

void main() {
  group('LocationNarrationAutomation', () {
    test('skips immediately when the location already has audio', () async {
      final automation = LocationNarrationAutomation(
        enqueue: (_) async => throw StateError('should not be called'),
        triggerWorker: () async => throw StateError('should not be called'),
        checkStatus: (_) async => throw StateError('should not be called'),
      );
      final results =
          await automation.run(_loc(audioFiles: ['a.mp3'])).toList();
      expect(results, hasLength(1));
      expect(results.single.stage, NarrationAutomationStage.skipped);
      expect(results.single.isSuccess, isTrue);
    });

    test('happy path: enqueue -> generating -> completed', () async {
      var statusCalls = 0;
      final automation = LocationNarrationAutomation(
        enqueue: (_) async => 'job-1',
        triggerWorker: () async => true,
        checkStatus: (jobId) async {
          statusCalls++;
          expect(jobId, 'job-1');
          // Pending on the first poll, completed on the second.
          return statusCalls == 1
              ? {'status': 'pending', 'message': null}
              : {'status': 'completed', 'message': null};
        },
        pollInterval: Duration.zero,
      );
      final results = await automation.run(_loc()).toList();
      expect(
        results.map((r) => r.stage),
        [
          NarrationAutomationStage.enqueuing,
          NarrationAutomationStage.generating,
          NarrationAutomationStage.done,
        ],
      );
      expect(results.last.isSuccess, isTrue);
    });

    test('enqueue failure surfaces a meaningful message and stops', () async {
      final automation = LocationNarrationAutomation(
        enqueue: (_) async => throw Exception('network down'),
        triggerWorker: () async => true,
        checkStatus: (_) async => null,
        pollInterval: Duration.zero,
      );
      final results = await automation.run(_loc()).toList();
      expect(results.last.stage, NarrationAutomationStage.failed);
      expect(results.last.message, contains('network down'));
    });

    test('null job id (Supabase not configured) fails clearly', () async {
      final automation = LocationNarrationAutomation(
        enqueue: (_) async => null,
        triggerWorker: () async => true,
        checkStatus: (_) async => null,
        pollInterval: Duration.zero,
      );
      final results = await automation.run(_loc()).toList();
      expect(results.last.stage, NarrationAutomationStage.failed);
      expect(results.last.message, contains('not configured'));
    });

    test('job failure surfaces the worker-reported reason', () async {
      final automation = LocationNarrationAutomation(
        enqueue: (_) async => 'job-1',
        triggerWorker: () async => true,
        checkStatus: (_) async =>
            {'status': 'failed', 'message': 'ELEVENLABS_API_KEY not set'},
        pollInterval: Duration.zero,
      );
      final results = await automation.run(_loc()).toList();
      expect(results.last.stage, NarrationAutomationStage.failed);
      expect(results.last.message, contains('ELEVENLABS_API_KEY not set'));
      expect(results.last.isSuccess, isFalse);
    });

    test('a worker-trigger failure is non-fatal — polling still proceeds',
        () async {
      final automation = LocationNarrationAutomation(
        enqueue: (_) async => 'job-1',
        triggerWorker: () async => throw Exception('function not deployed'),
        checkStatus: (_) async => {'status': 'completed', 'message': null},
        pollInterval: Duration.zero,
      );
      final results = await automation.run(_loc()).toList();
      expect(results.last.stage, NarrationAutomationStage.done);
    });

    test('gives up gracefully after maxAttempts with a non-alarming message',
        () async {
      final automation = LocationNarrationAutomation(
        enqueue: (_) async => 'job-1',
        triggerWorker: () async => true,
        checkStatus: (_) async => {'status': 'pending', 'message': null},
        pollInterval: Duration.zero,
        maxAttempts: 3,
      );
      final results = await automation.run(_loc()).toList();
      // Timing out on a slow-but-healthy pipeline is deliberately NOT a
      // failure — it's the non-alarming "still working, check back" stage.
      expect(results.last.stage, NarrationAutomationStage.stillPending);
      expect(results.last.message, contains('background'));
    });

    test('a checkStatus exception mid-poll is swallowed and polling continues',
        () async {
      var calls = 0;
      final automation = LocationNarrationAutomation(
        enqueue: (_) async => 'job-1',
        triggerWorker: () async => true,
        checkStatus: (_) async {
          calls++;
          if (calls == 1) throw Exception('transient error');
          return {'status': 'completed', 'message': null};
        },
        pollInterval: Duration.zero,
      );
      final results = await automation.run(_loc()).toList();
      expect(results.last.stage, NarrationAutomationStage.done);
    });
  });
}
