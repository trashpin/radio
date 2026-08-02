import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/admin/counties/county_config.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

void main() {
  group('CountyConfig — County Profile fields', () {
    test('fromJson/toWrite round-trip the new profile fields', () {
      final c = CountyConfig.fromJson({
        'id': '1',
        'name': 'Marion',
        'state': 'Florida',
        'welcome': 'Welcome to Marion County.',
        'seal_url': 'https://img/seal.png',
        'hero_image_url': 'https://img/hero.jpg',
        'welcome_narration_url': 'https://audio/welcome.mp3',
        'history': 'Founded in 1844...',
        'overview': 'Home to the Ocala National Forest.',
        'population': 375000,
        'size_sq_miles': 1663.8,
        'year_established': 1844,
        'facts': ['Horse Capital of the World', 'Over 600 natural springs'],
        'tourism_info': 'Visit the Ocala/Marion County Visitors Bureau.',
        'official_website': 'https://marioncountyfl.org',
        'gallery_images': ['https://img/a.jpg', 'https://img/b.jpg'],
      });

      expect(c.sealUrl, 'https://img/seal.png');
      expect(c.population, 375000);
      expect(c.sizeSqMiles, 1663.8);
      expect(c.yearEstablished, 1844);
      expect(c.facts, hasLength(2));
      expect(c.galleryImages, hasLength(2));

      final written = c.toWrite();
      expect(written['seal_url'], c.sealUrl);
      expect(written['population'], c.population);
      expect(written['gallery_images'], c.galleryImages);
    });

    test('profileCompleteness reflects how many profile fields are filled',
        () {
      const empty = CountyConfig(id: '1', name: 'Levy');
      expect(empty.profileCompleteness, 0);

      const full = CountyConfig(
        id: '1',
        name: 'Levy',
        sealUrl: 'x',
        heroImageUrl: 'x',
        welcomeNarrationUrl: 'x',
        history: 'x',
        overview: 'x',
        population: 1,
        sizeSqMiles: 1,
        yearEstablished: 1,
        facts: ['x'],
        tourismInfo: 'x',
        officialWebsite: 'x',
        galleryImages: ['x'],
      );
      expect(full.profileCompleteness, 1);
    });

    test('missing profile fields default to null/empty, not errors', () {
      final c = CountyConfig.fromJson({'id': '1', 'name': 'Citrus'});
      expect(c.sealUrl, isNull);
      expect(c.population, isNull);
      expect(c.facts, isEmpty);
      expect(c.galleryImages, isEmpty);
    });
  });

  group('MasterLocation — GPS trigger config', () {
    test('defaults match pre-migration behavior (arrival-only, no cooldown)',
        () {
      final l = MasterLocation.fromJson({
        'id': '1',
        'name': 'Silver Springs',
        'category': 'spring',
      });
      expect(l.arrivalTrigger, isTrue);
      expect(l.departureTrigger, isFalse);
      expect(l.playOnce, isFalse);
      expect(l.cooldownSeconds, isNull);
    });

    test('fromJson/toWrite round-trip explicit trigger config', () {
      final l = MasterLocation.fromJson({
        'id': '1',
        'name': 'Silver Springs',
        'category': 'spring',
        'arrival_trigger': true,
        'departure_trigger': true,
        'play_once': true,
        'cooldown_seconds': 3600,
      });
      expect(l.departureTrigger, isTrue);
      expect(l.playOnce, isTrue);
      expect(l.cooldownSeconds, 3600);

      final written = l.toWrite();
      expect(written['departure_trigger'], true);
      expect(written['play_once'], true);
      expect(written['cooldown_seconds'], 3600);
    });
  });

  group('MasterLocation — content status workflow', () {
    MasterLocation loc({
      bool active = true,
      bool hidden = false,
      double? lat,
      double? lng,
      List<String> images = const [],
      List<String> audioFiles = const [],
      String? contentStatus,
    }) =>
        MasterLocation.fromJson({
          'id': '1',
          'name': 'X',
          'category': 'point_of_interest',
          'active': active,
          'hidden': hidden,
          'latitude': lat,
          'longitude': lng,
          'images': images,
          'audio_files': audioFiles,
          if (contentStatus != null) 'content_status': contentStatus,
        });

    test('explicit content_status always wins', () {
      final l = loc(contentStatus: 'published');
      expect(l.contentStatus, ContentStatus.published);
      expect(l.effectiveContentStatus, ContentStatus.published);
    });

    test('archived when inactive or hidden, regardless of content', () {
      expect(loc(active: false).effectiveContentStatus, ContentStatus.archived);
      expect(loc(hidden: true).effectiveContentStatus, ContentStatus.archived);
    });

    test('needs GPS verification when no coordinates', () {
      expect(loc().effectiveContentStatus, ContentStatus.needsGpsVerification);
    });

    test('needs images once GPS is set but no images', () {
      final l = loc(lat: 29.2, lng: -82.1);
      expect(l.effectiveContentStatus, ContentStatus.needsImages);
    });

    test('needs narration once GPS + images are set but no audio', () {
      final l = loc(lat: 29.2, lng: -82.1, images: ['https://img/a.jpg']);
      expect(l.effectiveContentStatus, ContentStatus.needsNarration);
    });

    test('needs review once everything is present — never auto-published',
        () {
      final l = loc(
        lat: 29.2,
        lng: -82.1,
        images: ['https://img/a.jpg'],
        audioFiles: ['https://audio/a.mp3'],
      );
      expect(l.effectiveContentStatus, ContentStatus.needsReview);
    });

    test('ContentStatus.fromId is null for unknown/absent values', () {
      expect(ContentStatus.fromId(null), isNull);
      expect(ContentStatus.fromId('not_a_real_status'), isNull);
      expect(ContentStatus.fromId('draft'), ContentStatus.draft);
    });
  });
}
