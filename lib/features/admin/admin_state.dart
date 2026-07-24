import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/admin_modules.dart';

/// Currently selected sidebar module (drives the content pane + breadcrumb).
final adminSelectedModuleProvider =
    NotifierProvider<AdminSelectedModule, AdminModule>(AdminSelectedModule.new);

class AdminSelectedModule extends Notifier<AdminModule> {
  @override
  AdminModule build() => AdminModule.dashboard;

  void select(AdminModule module) => state = module;
}

/// Admin light/dark theme mode (defaults to light, like Shopify/WP admin).
final adminThemeModeProvider =
    NotifierProvider<AdminThemeMode, ThemeMode>(AdminThemeMode.new);

class AdminThemeMode extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;

  void toggle() => state =
      state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
}

/// Global search query (top bar). Consumed by pages to filter their lists.
final adminSearchProvider =
    NotifierProvider<AdminSearch, String>(AdminSearch.new);

class AdminSearch extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
  void clear() => state = '';
}
