import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/constants/app_constants.dart';
import 'services/supabase_service.dart';

/// Application entry point for ExplorerOS-Mobile.
///
/// Responsibilities (kept deliberately small):
///   1. Ensure Flutter bindings are ready before any async work.
///   2. Load the `.env` file (optional) so backend config is available.
///   3. Initialize the Supabase backend connection (no-ops safely if the
///      SUPABASE_* config is not provided).
///   4. Wrap the whole app in a Riverpod `ProviderScope` so any widget can read
///      providers (this is the root of the state-management tree).
///   5. Launch the root `ExplorerApp` widget.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // `isOptional: true` means a missing `.env` won't crash the app — the app
  // still boots and simply reports that the backend isn't configured.
  await dotenv.load(fileName: AppConstants.envFileName, isOptional: true);

  await SupabaseService.initialize();

  runApp(
    const ProviderScope(
      child: ExplorerApp(),
    ),
  );
}
