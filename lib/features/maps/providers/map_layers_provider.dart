import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/destinations/data/stop_repository.dart';
import 'package:explorer_os_mobile/shared/models/stop.dart';

/// Toggleable map layers. Each maps to a Supabase-driven marker/overlay set.
enum MapLayer {
  parks('Parks', Icons.forest_rounded),
  boundaries('Park boundaries', Icons.crop_free_rounded),
  locations('Locations', Icons.place_rounded),
  sightings('Sightings', Icons.visibility_rounded);

  const MapLayer(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The currently-visible layers (all on by default).
final mapLayersProvider =
    NotifierProvider<MapLayers, Set<MapLayer>>(MapLayers.new);

class MapLayers extends Notifier<Set<MapLayer>> {
  @override
  Set<MapLayer> build() => MapLayer.values.toSet();

  void toggle(MapLayer layer) {
    final next = {...state};
    next.contains(layer) ? next.remove(layer) : next.add(layer);
    state = next;
  }

  bool isOn(MapLayer layer) => state.contains(layer);
}

/// All stops (Locations layer). Reads the Base44 `stops` table; empty if none.
final allStopsProvider = FutureProvider<List<Stop>>(
  (ref) => ref.watch(stopRepositoryProvider).getAll(),
);
