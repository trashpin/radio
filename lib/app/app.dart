import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/core/constants/app_constants.dart';
import 'package:explorer_os_mobile/core/navigation/app_router.dart';
import 'package:explorer_os_mobile/core/theme/app_theme.dart';

/// The root widget of ExplorerOS.
///
/// Wires the three foundations together: the design-system [AppTheme] (light +
/// dark), navigation via [AppRouter] (go_router), and the app identity. Uses
/// `MaterialApp.router` because navigation is declarative. `themeMode: system`
/// lets the OS choose light/dark.
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
