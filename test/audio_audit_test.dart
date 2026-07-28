import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/admin/audio_studio/logic/audio_audit.dart';
import 'package:explorer_os_mobile/features/admin/audio_studio/models/audio_asset.dart';

AudioRecordRef _rec(String id,
        {VoiceCategory cat = VoiceCategory.wildlife, String? audio}) =>
    AudioRecordRef(
        id: id, category: cat, title: 'Rec $id', existingAudioUrl: audio);

AudioAsset _asset(
  String id, {
  required String recordId,
  VoiceCategory cat = VoiceCategory.wildlife,
  AudioStatus status = AudioStatus.complete,
  String? url = 'https://cdn/a.mp3',
  int? fileSize = 12345,
  int version = kAudioGenerationVersion,
}) =>
    AudioAsset(
      id: id,
      recordId: recordId,
      recordType: cat.id,
      status: status,
      publicUrl: url,
      fileSize: fileSize,
      generationVersion: version,
    );

void main() {
  group('VoiceCategory.fromToken', () {
    test('maps tokens to categories', () {
      expect(VoiceCategory.fromToken('birds'), VoiceCategory.birds);
      expect(VoiceCategory.fromToken('mammals'), VoiceCategory.wildlife);
      expect(VoiceCategory.fromToken('trees'), VoiceCategory.plants);
      expect(VoiceCategory.fromToken('historic_sites'), VoiceCategory.history);
      expect(VoiceCategory.fromToken('unknown'), VoiceCategory.parkWelcome);
    });
  });

  group('auditAudio', () {
    test('missing when no asset and no existing url', () {
      final a = auditAudio([_rec('r1')], const []).single;
      expect(a.missingAudio, isTrue);
      expect(a.hasAudio, isFalse);
    });

    test('has audio via a complete asset', () {
      final a = auditAudio([_rec('r1')], [_asset('a1', recordId: 'r1')]).single;
      expect(a.hasAudio, isTrue);
      expect(a.missingAudio, isFalse);
    });

    test('has audio via the record own url', () {
      final a =
          auditAudio([_rec('r1', audio: 'https://cdn/own.mp3')], const []).single;
      expect(a.hasAudio, isTrue);
    });

    test('flags outdated (needs regen), zero-byte, broken and duplicate', () {
      final assets = [
        _asset('a1', recordId: 'r1', version: 0), // outdated
        _asset('z1', recordId: 'r2', fileSize: 0), // zero-byte
        _asset('b1', recordId: 'r3', url: 'garbage'), // broken
        _asset('d1', recordId: 'r4', url: 'https://cdn/dup.mp3'),
        _asset('d2', recordId: 'r5', url: 'https://cdn/dup.mp3'),
      ];
      final audits = auditAudio(
        [_rec('r1'), _rec('r2'), _rec('r3'), _rec('r4'), _rec('r5')],
        assets,
      );
      expect(audits[0].needsRegen, isTrue);
      expect(audits[1].zeroByte, isTrue);
      expect(audits[2].broken, isTrue);
      expect(audits[3].duplicate, isTrue);
      expect(audits[4].duplicate, isTrue);
    });
  });

  group('computeAudioDashboard', () {
    test('aggregates coverage, storage and completion', () {
      final records = [_rec('r1'), _rec('r2'), _rec('r3')];
      final assets = [
        _asset('a1', recordId: 'r1', fileSize: 1000),
        _asset('a2', recordId: 'r2', fileSize: 2000),
      ];
      final s = computeAudioDashboard(records, assets, queued: 5);
      expect(s.totalRecords, 3);
      expect(s.recordsWithAudio, 2);
      expect(s.recordsMissingAudio, 1);
      expect(s.storageUsedBytes, 3000);
      expect(s.queued, 5);
      expect(s.completionPercent, closeTo(66.7, 0.5));
      expect(s.estimatedRemaining(secondsPerRecord: 10),
          const Duration(seconds: 10));
    });

    test('empty inputs', () {
      final s = computeAudioDashboard(const [], const []);
      expect(s.totalRecords, 0);
      expect(s.completionPercent, 0);
    });
  });

  group('audioCsv', () {
    test('header + one row per record', () {
      final csv = audioCsv(auditAudio([_rec('r1'), _rec('r2')], const []));
      final lines = csv.split('\n');
      expect(lines.first, contains('record_id'));
      expect(lines.length, 3);
    });
  });

  group('formatBytes', () {
    test('formats sizes', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });
  });
}
