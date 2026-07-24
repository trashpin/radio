import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/config/env_config.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/admin/admin_app.dart';

/// Entry point for the ExplorerOS Admin (Flutter web).
///
/// Build/run with:
///   flutter run   -d chrome     -t lib/main_admin.dart
///   flutter build web            -t lib/main_admin.dart
///
/// Shares the mobile app's Supabase config (`.env`). Browser clients MUST use
/// the `sb_publishable_` key — Supabase blocks `sb_secret_` keys from browsers.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: EnvConfig.fileName, isOptional: true);
  await SupabaseService.initialize();
  runApp(const ProviderScope(child: AdminApp()));
}
