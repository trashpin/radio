import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_theme.dart';
import 'package:explorer_os_mobile/features/admin/admin_state.dart';
import 'package:explorer_os_mobile/features/admin/presentation/admin_shell.dart';

/// Root of the ExplorerOS Admin (a separate Flutter-web target).
///
/// Reuses the app's [AppTheme] (light + dark) and shares the same Supabase
/// backend, models, repositories, and services as the mobile client. The active
/// theme is driven by [adminThemeModeProvider] (top-bar toggle).
class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(adminThemeModeProvider);
    return MaterialApp(
      title: 'ExplorerOS Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      home: const AdminShell(),
    );
  }
}
