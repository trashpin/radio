// Unit tests for the Ocala Forest Explorer's point-in-polygon boundary
// check — pure geometry, no network. Exercises both a synthetic square (to
// confirm the ray-casting algorithm itself) and the REAL Ocala National
// Forest geometry embedded below (the exact `polygon` value seeded by
// supabase/migrations/0048_ocala_forest.sql, sourced from the USDA Forest
// Service's EDW_RangerDistricts_03 service — see that migration's header
// comment), confirming the actual seeded locations land inside it and
// nearby-but-outside places (downtown Ocala, Gainesville) do not.

import 'dart:convert';

import 'package:explorer_os_mobile/features/ocala_forest/models/forest_boundary.dart';
import 'package:explorer_os_mobile/features/ocala_forest/services/point_in_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

const _ocalaForestPolygonJson =
    '[[[[-81.84315,29.52132],[-81.8877,29.50945],[-81.90119,29.51615],[-81.91114,29.50549],[-81.90975,29.47811],[-81.92935,29.42762],[-81.90082,29.39383],[-81.90129,29.37152],[-81.88403,29.33867],[-81.91673,29.29576],[-81.9361,29.28475],[-81.9423,29.26508],[-81.96514,29.2541],[-81.96706,29.23835],[-81.98614,29.21475],[-81.95077,29.21192],[-81.865,29.17185],[-81.70839,29.17818],[-81.6509,29.167],[-81.62245,29.17142],[-81.57004,29.15348],[-81.52476,29.16314],[-81.53269,29.177],[-81.55498,29.18425],[-81.56159,29.19943],[-81.61226,29.20287],[-81.64923,29.29175],[-81.67513,29.3097],[-81.67813,29.33553],[-81.65651,29.34026],[-81.66299,29.36402],[-81.68663,29.38843],[-81.68336,29.39859],[-81.68039,29.39188],[-81.65962,29.39206],[-81.66516,29.39815],[-81.65636,29.41929],[-81.69329,29.43716],[-81.69064,29.47033],[-81.72921,29.48378],[-81.76966,29.47207],[-81.79411,29.49564],[-81.80768,29.49634],[-81.81103,29.50902],[-81.84315,29.52132]]],[[[-82.06082,29.82781],[-82.06347,29.83471],[-82.06913,29.83125],[-82.06344,29.83243],[-82.06082,29.82781]]],[[[-81.51845,29.14683],[-81.5238,29.16735],[-81.57004,29.15348],[-81.62245,29.17142],[-81.6509,29.167],[-81.70839,29.17818],[-81.86418,29.17176],[-81.95077,29.21192],[-81.98614,29.21475],[-81.995,29.20164],[-81.99236,29.18363],[-81.9656,29.17355],[-81.93349,29.14251],[-81.92367,29.1099],[-81.906,29.09144],[-81.85423,29.09154],[-81.84624,29.04397],[-81.83235,29.03476],[-81.82822,29.01489],[-81.80789,29.0079],[-81.80761,28.99676],[-81.82829,28.99349],[-81.80755,28.99347],[-81.77148,28.97552],[-81.71354,28.98947],[-81.65988,28.96626],[-81.65891,28.98583],[-81.65175,28.98579],[-81.65886,28.98938],[-81.65896,29.00407],[-81.6443,29.00381],[-81.62715,28.98789],[-81.63971,28.98945],[-81.63979,28.97848],[-81.6248,28.97098],[-81.61039,28.97862],[-81.61046,28.96759],[-81.58126,28.96023],[-81.54235,28.97545],[-81.5343,29.00333],[-81.51599,29.01457],[-81.47377,29.0168],[-81.4331,29.00403],[-81.38259,29.0082],[-81.4557,29.06278],[-81.45918,29.09363],[-81.48829,29.09247],[-81.51853,29.10791],[-81.5064,29.1243],[-81.51845,29.14683]]],[[[-81.09698,28.62736],[-81.09659,28.62701],[-81.0966,28.62736],[-81.09698,28.62736]]],[[[-81.09666,28.6474],[-81.10066,28.63461],[-81.09228,28.62735],[-81.09069,28.65301],[-81.09666,28.6474]]],[[[-81.10078,28.64373],[-81.09871,28.64496],[-81.1008,28.64494],[-81.10078,28.64373]]],[[[-81.09699,28.65784],[-81.09686,28.65282],[-81.09646,28.66387],[-81.09717,28.66387],[-81.09699,28.65784]]],[[[-81.48891,28.92028],[-81.48445,28.9167],[-81.4844,28.92043],[-81.48891,28.92028]]],[[[-81.43841,28.94894],[-81.43397,28.95622],[-81.4381,28.95622],[-81.43841,28.94894]]],[[[-81.42969,28.96344],[-81.42542,28.96752],[-81.42951,28.96754],[-81.42969,28.96344]]],[[[-81.51723,28.97813],[-81.51289,28.98212],[-81.51724,28.98217],[-81.51723,28.97813]]],[[[-81.52291,29.00016],[-81.52189,28.99313],[-81.51402,28.99669],[-81.51457,29.00021],[-81.52291,29.00016]]]]';

ForestBoundary _realOcalaBoundary() => ForestBoundary.fromJson({
      'id': 'test-ocala',
      'name': 'Ocala National Forest',
      'source': 'USDA Forest Service',
      'source_url': 'https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_RangerDistricts_03/MapServer/0',
      'polygon': jsonDecode(_ocalaForestPolygonJson),
      'acres': 443169.11,
    });

void main() {
  group('pointInRing', () {
    final square = <LatLngPoint>[
      (lat: 0, lng: 0),
      (lat: 0, lng: 10),
      (lat: 10, lng: 10),
      (lat: 10, lng: 0),
    ];

    test('a point in the middle of a square is inside', () {
      expect(pointInRing(5, 5, square), isTrue);
    });

    test('a point clearly outside a square is outside', () {
      expect(pointInRing(20, 20, square), isFalse);
    });

    test('a point just outside an edge is outside', () {
      expect(pointInRing(5, 10.001, square), isFalse);
    });

    test('a degenerate ring (fewer than 3 points) is never inside', () {
      expect(pointInRing(1, 1, [(lat: 0, lng: 0), (lat: 1, lng: 1)]), isFalse);
    });
  });

  group('ForestBoundary — real Ocala National Forest geometry', () {
    final boundary = _realOcalaBoundary();

    test('parses all 12 parts from the seeded MultiPolygon', () {
      expect(boundary.parts, hasLength(12));
    });

    // The exact 7 locations seeded by migration 0048_ocala_forest.sql.
    const seededLocations = {
      'Alexander Springs': (lat: 29.0788915, lng: -81.5780407),
      'Juniper Springs': (lat: 29.18389, lng: -81.71194),
      'Silver Glen Springs': (lat: 29.2468, lng: -81.6435),
      'Salt Springs': (lat: 29.35111, lng: -81.735),
      'Salt Springs Trailhead': (lat: 29.354897, lng: -81.734478),
      'Lake Dorr Recreation Area': (lat: 29.0143142, lng: -81.6357021),
      'Clearwater Lake Recreation Area': (lat: 28.97851, lng: -81.553909),
    };

    for (final entry in seededLocations.entries) {
      test('${entry.key} is inside the forest boundary', () {
        expect(boundary.contains(entry.value.lat, entry.value.lng), isTrue);
      });
    }

    test('a point inside a small detached inholding parcel is inside', () {
      // Centroid-ish point inside the small quadrilateral parcel near
      // (-81.10, 28.64) — proves multi-part handling works, not just the
      // two main forest bodies.
      expect(boundary.contains(28.6406, -81.0951), isTrue);
    });

    test('downtown Ocala (the city, not the forest) is outside', () {
      expect(boundary.contains(29.1872, -82.1401), isFalse);
    });

    test('Gainesville is outside', () {
      expect(boundary.contains(29.6516, -82.3248), isFalse);
    });
  });
}
