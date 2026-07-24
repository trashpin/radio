import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'services/supabase_service.dart';

/// Application entry point for ExplorerOS-Mobile.
///
/// Responsibilities (kept deliberately small):
///   1. Ensure Flutter bindings are ready before any async work.
///   2. Initialize the Supabase backend connection (no-ops safely if the
///      SUPABASE_* config is not provided).
///   3. Wrap the whole app in a Riverpod `ProviderScope` so any widget can read
///      providers (this is the root of the state-management tree).
///   4. Launch the root `ExplorerApp` widget.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseService.initialize();

  runApp(
    const ProviderScope(
      child: ExplorerApp(),
    ),
  );
}
