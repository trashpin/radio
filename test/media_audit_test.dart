import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/admin/media_manager/logic/media_audit.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/models/media_record.dart';

MediaRecord _rec(
  String id, {
  MediaRecordType type = MediaRecordType.animals,
  String? hero,
  String? audio,
  String? alt,
  String? copyright,
  String? credits,
}) =>
    MediaRecord(
      id: id,
      type: type,
      title: 'Record $id',
      category: type.name,
      heroImageUrl: hero,
      audioUrl: audio,
      altText: alt,
      copyright: copyright,
      credits: credits,
    );

MediaAsset _asset(
  String id, {
  required String recordId,
  MediaRecordType type = MediaRecordType.animals,
  MediaType media = MediaType.image,
  bool hero = false,
  String? url,
  String? alt,
  String? copyright,
  String? photographer,
}) =>
    MediaAsset(
      id: id,
      recordId: recordId,
      recordType: type.name,
      mediaType: media,
      isHero: hero,
      publicUrl: url,
      altText: alt,
      copyright: copyright,
      photographer: photographer,
    );

void main() {
  group('MediaRecordType.fromToken', () {
    test('maps common tokens to normalized categories', () {
      expect(MediaRecordType.fromToken('birds'), MediaRecordType.birds);
      expect(MediaRecordType.fromToken('wildflowers'),
          MediaRecordType.wildflowers);
      expect(MediaRecordType.fromToken('scenic_overlooks'),
          MediaRecordType.scenicDrives);
      expect(MediaRecordType.fromToken('mammals'), MediaRecordType.animals);
      expect(MediaRecordType.fromToken('something-odd'),
          MediaRecordType.other);
    });
  });

  group('isBrokenUrl', () {
    test('flags malformed URLs but not empty or valid ones', () {
      expect(isBrokenUrl(null), isFalse);
      expect(isBrokenUrl(''), isFalse);
      expect(isBrokenUrl('https://cdn.example/x.jpg'), isFalse);
      expect(isBrokenUrl('not a url'), isTrue);
      expect(isBrokenUrl('ftp://cdn/x.jpg'), isTrue);
    });
  });

  group('duplicateUrls', () {
    test('returns urls used by more than one asset', () {
      final dupes = duplicateUrls([
        _asset('1', recordId: 'a', url: 'https://c/x.jpg'),
        _asset('2', recordId: 'b', url: 'https://c/x.jpg'),
        _asset('3', recordId: 'c', url: 'https://c/y.jpg'),
      ]);
      expect(dupes, contains('https://c/x.jpg'));
      expect(dupes, isNot(contains('https://c/y.jpg')));
    });
  });

  group('auditRecords', () {
    test('flags a completely empty record as missing everything', () {
      final audits = auditRecords([_rec('a')], const []);
      final a = audits.single;
      expect(a.missingHero, isTrue);
      expect(a.missingGallery, isTrue);
      expect(a.missingAudio, isTrue);
      expect(a.missingAltText, isTrue);
      expect(a.missingCopyright, isTrue);
      expect(a.missingCredits, isTrue);
      expect(a.completion, 0);
    });

    test('a fully-populated record reports complete', () {
      final rec = _rec('a',
          hero: 'https://c/hero.jpg',
          audio: 'https://c/a.mp3',
          alt: 'A deer',
          copyright: '© NPS',
          credits: 'J. Doe');
      final assets = [
        _asset('g1', recordId: 'a', hero: false, url: 'https://c/g1.jpg'),
      ];
      final a = auditRecords([rec], assets).single;
      expect(a.missingHero, isFalse);
      expect(a.missingGallery, isFalse);
      expect(a.missingAudio, isFalse);
      expect(a.missingAltText, isFalse);
      expect(a.missingCopyright, isFalse);
      expect(a.missingCredits, isFalse);
      expect(a.completion, 1.0);
    });

    test('hero from an asset counts even without a record hero field', () {
      final assets = [
        _asset('h', recordId: 'a', hero: true, url: 'https://c/h.jpg'),
      ];
      final a = auditRecords([_rec('a')], assets).single;
      expect(a.missingHero, isFalse);
      expect(a.missingGallery, isTrue); // hero isn't gallery
    });

    test('detects broken and duplicate files', () {
      final assets = [
        _asset('1', recordId: 'a', url: 'https://c/x.jpg'),
        _asset('2', recordId: 'b', url: 'https://c/x.jpg'), // dup
        _asset('3', recordId: 'c', url: 'garbage'), // broken
      ];
      final audits = auditRecords(
        [_rec('a'), _rec('b'), _rec('c')],
        assets,
      );
      expect(audits[0].duplicateFile, isTrue);
      expect(audits[1].duplicateFile, isTrue);
      expect(audits[2].brokenFile, isTrue);
    });
  });

  group('computeDashboard', () {
    test('aggregates counts and completion', () {
      final records = [
        _rec('a', hero: 'https://c/h.jpg', copyright: '© NPS'),
        _rec('b'),
      ];
      final assets = [
        _asset('i1', recordId: 'a', media: MediaType.image),
        _asset('v1', recordId: 'a', media: MediaType.video),
        _asset('au1', recordId: 'a', media: MediaType.audio),
      ];
      final s = computeDashboard(records, assets);
      expect(s.totalRecords, 2);
      expect(s.totalImages, 1);
      expect(s.totalVideos, 1);
      expect(s.totalAudio, 1);
      expect(s.recordsMissingHero, 1); // only b
      expect(s.completionPercent, greaterThan(0));
      expect(s.completionPercent, lessThanOrEqualTo(100));
    });

    test('empty inputs → empty stats', () {
      final s = computeDashboard(const [], const []);
      expect(s.totalRecords, 0);
      expect(s.completionPercent, 0);
    });
  });

  group('auditCsv', () {
    test('has a header and one row per record', () {
      final csv = auditCsv(auditRecords([_rec('a'), _rec('b')], const []));
      final lines = csv.split('\n');
      expect(lines.first, contains('record_id'));
      expect(lines.length, 3); // header + 2
      expect(lines[1], contains('YES')); // missing flags present
    });
  });
}
