import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/app/app.dart';
import 'package:explorer_os_mobile/core/config/env_config.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// Application entry point for ExplorerOS.
///
/// Kept deliberately small:
///   1. Ensure Flutter bindings are ready before async work.
///   2. Load the `.env` file (optional) so backend config is available.
///   3. Initialize Supabase (no-ops safely if config is missing).
///   4. Wrap the app in a Riverpod `ProviderScope` (root of state management).
///   5. Launch the root `ExplorerApp`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // `isOptional: true` → a missing `.env` won't crash the app; features simply
  // report the backend isn't configured.
  await dotenv.load(fileName: EnvConfig.fileName, isOptional: true);

  await SupabaseService.initialize();

  runApp(const ProviderScope(child: ExplorerApp()));
}
