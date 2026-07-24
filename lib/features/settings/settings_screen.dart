import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../services/supabase_service.dart';

/// The Settings screen.
///
/// Reached from the Profile tab (it is a pushed route, not a bottom-nav tab).
/// Phase 1 placeholder that also surfaces useful diagnostic info — e.g. whether
/// the Supabase backend is configured — which is handy while wiring up the
/// backend connection during development.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        children: [
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('App'),
            subtitle: Text(AppConstants.appName),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Backend connection'),
            subtitle: Text(
              SupabaseService.isConfigured
                  ? 'Supabase configured'
                  : 'Not configured (set SUPABASE_URL / SUPABASE_ANON_KEY)',
            ),
          ),
        ],
      ),
    );
  }
}
