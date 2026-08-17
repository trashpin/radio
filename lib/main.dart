import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/app/app.dart';
import 'package:explorer_os_mobile/core/config/env_config.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/auth/auth_controller.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_providers.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/gps/repositories/park_boundary_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: EnvConfig.fileName, isOptional: true);
  await SupabaseService.initialize();

  final container = ProviderContainer();
  await _seedGpsEngine(container);
  await _startGpsTracking(container);

  authController.start();

  runApp(
    UncontrolledProviderScope(container: container, child: const ExplorerApp()),
  );
}

Future<void> _seedGpsEngine(ProviderContainer container) async {
  if (!SupabaseService.isConfigured) return;
  try {
    final parkBoundaries =
        await container.read(parkBoundaryRepositoryProvider).getAll();
    container.read(gpsServiceProvider).configure(parks: parkBoundaries);
  } catch (error, stackTrace) {
    debugPrint('GPS engine seed failed: $error');
    debugPrint('$stackTrace');
  }
}

Future<void> _startGpsTracking(ProviderContainer container) async {
  try {
    await container.read(gpsStatusProvider.notifier).requestAndStart();
  } catch (error, stackTrace) {
    debugPrint('GPS start failed: $error');
    debugPrint('$stackTrace');
  }
}
