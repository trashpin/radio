import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// An official printable/scannable trail map, shown full-screen and
/// pinch-to-zoom (spec §2: "Allow the user to enlarge it... easy to view
/// on a phone"), with its source attribution always visible (spec §4). No
/// trail has one attached as of this phase (see migration 0052's doc
/// comment — USFS publishes none for Ocala), but the path is built so an
/// admin can attach one to any trail later with zero app changes.
class ForestTrailMapImageScreen extends StatelessWidget {
  const ForestTrailMapImageScreen({super.key, required this.trail});
  final ForestTrail trail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            RadioSubPageBar(
              title: (trail.trailName?.trim().isNotEmpty ?? false)
                  ? trail.trailName!
                  : 'Trail ${trail.trailNo}',
              subtitle: 'Official trail map',
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    trail.mapImageUrl!,
                    errorBuilder: (context, error, stack) => Text(
                      'Could not load the map image.',
                      style: RD.body.copyWith(color: RD.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(RD.md),
              child: Text(
                'Source: ${trail.mapSourceName ?? 'Unknown'}'
                '${trail.mapRetrievedAt != null ? ' · retrieved ${trail.mapRetrievedAt!.toLocal().toString().split(' ').first}' : ''}'
                '${trail.mapDocumentId != null ? ' · doc ${trail.mapDocumentId}' : ''}',
                textAlign: TextAlign.center,
                style: RD.caption.copyWith(color: RD.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
