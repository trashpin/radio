import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_experience_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/forest_around_me_screen.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/forest_discoveries_screen.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/forest_stories_screen.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/forest_trails_screen.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/ocala_explorer_map_screen.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/ocala_forest_providers.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// OCALA NATIONAL FOREST EXPLORER — an isolated experimental feature (own
/// route `/ocala-forest`, own providers, own Supabase tables; see v1's
/// migration 0048 + v2's 0049). This hub is a category-grid, mirroring
/// `DiscoverAreaScreen`'s existing "Discover This Area" pattern
/// (`lib/features/discover_area/presentation/discover_area_screen.dart`):
/// four PRIMARY interactive experiences (Trails, Discoveries, Forest
/// Stories, What's Around Me) plus the original map, now demoted to one
/// more option ("Explorer Map") rather than the whole page.
///
/// Starts/stops the shared [ForestExperienceController] — the GPS/geofence
/// trigger engine every sub-experience's automatic narration relies on —
/// for exactly as long as the user is anywhere in this feature.
class OcalaForestScreen extends ConsumerStatefulWidget {
  const OcalaForestScreen({super.key});

  @override
  ConsumerState<OcalaForestScreen> createState() => _OcalaForestScreenState();
}

class _OcalaForestScreenState extends ConsumerState<OcalaForestScreen> {
  late final ForestExperienceController _experience;

  @override
  void initState() {
    super.initState();
    _experience = ref.read(forestExperienceControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _experience.start());
  }

  @override
  void dispose() {
    _experience.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasGpsFix = ref.watch(gpsControllerProvider).location != null;
    final insideForest = ref.watch(isInsideOcalaForestProvider);

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RadioSubPageBar(title: 'Ocala National Forest Explorer'),
            _StatusBanner(hasGpsFix: hasGpsFix, insideForest: insideForest),
            const SizedBox(height: RD.sm),
            Expanded(
              child: GridView.count(
                padding: const EdgeInsets.all(RD.lg),
                crossAxisCount: 2,
                mainAxisSpacing: RD.md,
                crossAxisSpacing: RD.md,
                childAspectRatio: 1.05,
                children: [
                  _ExperienceTile(
                    icon: Icons.hiking_rounded,
                    label: 'Trails',
                    color: const Color(0xFFCF7A3A),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ForestTrailsScreen())),
                  ),
                  _ExperienceTile(
                    icon: Icons.explore_rounded,
                    label: 'Discoveries',
                    color: const Color(0xFF4C9BE0),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ForestDiscoveriesScreen())),
                  ),
                  _ExperienceTile(
                    icon: Icons.auto_stories_rounded,
                    label: 'Forest Stories',
                    color: const Color(0xFF9B6ACB),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ForestStoriesScreen())),
                  ),
                  _ExperienceTile(
                    icon: Icons.near_me_rounded,
                    label: "What's Around Me",
                    color: const Color(0xFF5CA85C),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ForestAroundMeScreen())),
                  ),
                  _ExperienceTile(
                    icon: Icons.map_outlined,
                    label: 'Explorer Map',
                    color: RD.textSecondary,
                    secondary: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const OcalaExplorerMapScreen())),
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

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.hasGpsFix, required this.insideForest});
  final bool hasGpsFix;
  final bool? insideForest;

  @override
  Widget build(BuildContext context) {
    final String text;
    final Color color;
    if (!hasGpsFix) {
      text = 'Waiting for a GPS fix…';
      color = RD.textSecondary;
    } else if (insideForest == true) {
      text = '🌲 You are INSIDE Ocala National Forest';
      color = RD.greenBright;
    } else {
      text = '📍 You are OUTSIDE Ocala National Forest';
      color = RD.textSecondary;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RD.lg),
      child: Text(text, style: RD.body.copyWith(color: color)),
    );
  }
}

/// One primary-experience tile. [secondary] mutes an option visually (used
/// only for Explorer Map, per spec: "keep the existing map available...
/// rather than making it the entire experience").
class _ExperienceTile extends StatelessWidget {
  const _ExperienceTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.secondary = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      onTap: onTap,
      color: secondary ? RD.bgElevated : RD.panel,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: secondary ? 32 : 40, color: color),
          const SizedBox(height: RD.sm),
          Text(
            label,
            textAlign: TextAlign.center,
            style: secondary
                ? RD.caption.copyWith(color: RD.textSecondary)
                : RD.cardTitle.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
