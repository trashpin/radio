import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/widgets/forest_audio_bar.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/widgets/forest_experience_card.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/forest_around_me_providers.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/ocala_forest_providers.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// WHAT'S AROUND ME — the forest's own version of the existing "What's
/// Around Me" feature. Reuses `Experience` (plain data) and
/// `explorerScore`/`ExplorerScoreInput` (pure ranking) from
/// `lib/features/around_me/` completely unmodified
/// (`forestAroundMeExperiencesProvider`); automatic arrival narration is
/// already handled feature-wide by `ForestExperienceController`, so this
/// screen is the ranked, browsable read side, not a second geofence
/// detector.
class ForestAroundMeScreen extends ConsumerWidget {
  const ForestAroundMeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasGpsFix = ref.watch(gpsControllerProvider).location != null;
    final experiences = ref.watch(forestAroundMeExperiencesProvider);
    final locations = ref.watch(forestLocationsProvider).value ?? const <ForestLocation>[];
    final byId = {for (final l in locations) l.id: l};

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(
                title: "What's Around Me", subtitle: 'Ocala National Forest'),
            const Padding(
              padding: EdgeInsets.fromLTRB(RD.lg, RD.sm, RD.lg, 0),
              child: ForestAudioBar(),
            ),
            Expanded(
              child: !hasGpsFix
                  ? Center(
                      child: Text('Waiting for a GPS fix…',
                          style: RD.body.copyWith(color: RD.textSecondary)),
                    )
                  : experiences.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(RD.xl),
                            child: Text(
                              'Nothing mapped near you in the forest yet.',
                              textAlign: TextAlign.center,
                              style: RD.body.copyWith(color: RD.textSecondary),
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(RD.lg),
                          children: [
                            for (final exp in experiences)
                              if (byId[exp.id] != null)
                                ForestExperienceCard(
                                  experience: exp,
                                  location: byId[exp.id]!,
                                  onTellMeMore: () => context.push(
                                    AppRoute.tellMeMore.path,
                                    extra: TellMeMoreContext(
                                      subject: exp.name,
                                      locationId: exp.id,
                                      contextKind: 'forest',
                                      location: GeoPoint(
                                          latitude: exp.latitude,
                                          longitude: exp.longitude),
                                    ),
                                  ),
                                ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
