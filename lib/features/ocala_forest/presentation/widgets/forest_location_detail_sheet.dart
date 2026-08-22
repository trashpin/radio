import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/services/forest_playback.dart';
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';

/// The shared "here's what this forest location is" bottom sheet — used by
/// the Explorer Map and Discoveries so there's one detail presentation, not
/// a copy per screen. Listen/Navigate reuse `forest_playback.dart`; Tell Me
/// More reuses the existing `/tell-me-more` route + the new `forest`
/// `TellMeMoreContext.contextKind` case.
void showForestLocationDetail(
  BuildContext context,
  WidgetRef ref,
  ForestLocation loc,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(loc.name, style: Theme.of(sheetContext).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(loc.category,
              style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    letterSpacing: 1.1,
                    color: Colors.grey.shade600,
                  )),
          if ((loc.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(loc.description!.trim()),
          ],
          if ((loc.source ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Source: ${loc.source}',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    )),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => playForestLocation(ref, loc),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Listen'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.push(
                    AppRoute.tellMeMore.path,
                    extra: TellMeMoreContext(
                      subject: loc.name,
                      locationId: loc.id,
                      contextKind: 'forest',
                      location:
                          GeoPoint(latitude: loc.latitude, longitude: loc.longitude),
                    ),
                  );
                },
                icon: const Icon(Icons.info_outline_rounded, size: 18),
                label: const Text('Tell Me More'),
              ),
              OutlinedButton.icon(
                onPressed: () => navigateToForestLocation(loc),
                icon: const Icon(Icons.directions_rounded, size: 18),
                label: const Text('Navigate'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
