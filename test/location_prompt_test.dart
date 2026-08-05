import 'package:explorer_os_mobile/features/gps/models/gps_status.dart';
import 'package:explorer_os_mobile/features/gps/presentation/location_prompt.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class _FixedCenter extends MapCenter {
  _FixedCenter(this._v);
  final LatLng? _v;
  @override
  LatLng? build() => _v;
}

class _FixedGps extends GpsStatusController {
  _FixedGps(this._s);
  final GpsStatus _s;
  @override
  GpsStatus build() => _s;
}

Future<void> _pump(WidgetTester tester,
    {LatLng? center, required GpsStatus gps}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mapCenterProvider.overrideWith(() => _FixedCenter(center)),
      gpsStatusProvider.overrideWith(() => _FixedGps(gps)),
    ],
    child: const MaterialApp(home: Scaffold(body: LocationPrompt())),
  ));
  await tester.pump();
}

void main() {
  testWidgets('hidden once a location fix exists', (tester) async {
    await _pump(tester,
        center: const LatLng(29.19, -82.14), gps: GpsStatus.initial());
    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining('location'), findsNothing);
  });

  testWidgets('no permission yet → Enable location', (tester) async {
    await _pump(tester,
        gps: GpsStatus.initial()
            .copyWith(permission: LocationPermissionStatus.denied));
    expect(find.text('Turn on location'), findsOneWidget);
    expect(find.text('Enable location'), findsOneWidget);
  });

  testWidgets('permanently denied → Open settings', (tester) async {
    await _pump(tester,
        gps: GpsStatus.initial()
            .copyWith(permission: LocationPermissionStatus.deniedForever));
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('granted but no fix → searching + Retry', (tester) async {
    await _pump(tester,
        gps: GpsStatus.initial()
            .copyWith(permission: LocationPermissionStatus.grantedWhenInUse));
    expect(find.text('Finding your location…'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
