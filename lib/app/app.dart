import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';

/// The root widget of ExplorerOS-Mobile.
///
/// It wires together the three foundational pieces:
///   • Theme       → `AppTheme.light` / `AppTheme.dark`
///   • Navigation  → `AppRouter.router` (go_router)
///   • App identity→ `AppConstants.appName`
///
/// We use `MaterialApp.router` (not plain `MaterialApp`) because navigation is
/// driven declaratively by go_router. `themeMode: system` lets the OS decide
/// light vs. dark.
class ExplorerApp extends StatelessWidget {
  const ExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.router,
    );
  }
}
