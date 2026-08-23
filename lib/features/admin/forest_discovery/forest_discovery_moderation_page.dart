import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// DISCOVER moderation (spec §11) — the base `forest_discovery_reports`
/// table has no anon/authenticated SELECT policy at all (migration 0051,
/// deliberately, so exact sensitive coordinates can never leak through a
/// direct query). This page is the one place that's allowed to see and
/// change every row, via the `forest_discovery_admin_list`/
/// `forest_discovery_admin_set_status` SECURITY DEFINER RPC functions
/// (migration 0051) rather than reopening the table.
class ForestDiscoveryModerationPage extends StatefulWidget {
  const ForestDiscoveryModerationPage({super.key});

  @override
  State<ForestDiscoveryModerationPage> createState() => _ForestDiscoveryModerationPageState();
}

class _ForestDiscoveryModerationPageState extends State<ForestDiscoveryModerationPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  static const _moderationStatuses = ['pending', 'confirmed', 'needs_review', 'rejected'];
  static const _visibilities = ['public', 'generalized', 'private'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await SupabaseService.client.rpc('forest_discovery_admin_list');
      setState(() {
        _rows = (res as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load discoveries: $e';
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(String id, {String? moderationStatus, String? visibility}) async {
    try {
      await SupabaseService.client.rpc('forest_discovery_admin_set_status', params: {
        'p_id': id,
        'p_moderation_status': moderationStatus,
        'p_visibility': visibility,
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('No DISCOVER reports yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        final r = _rows[i];
        final id = r['id'] as String;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (r['identification'] as String?)?.trim().isNotEmpty == true
                    ? r['identification'] as String
                    : 'Unidentified (${r['category']})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                'AI suggested: ${r['ai_identification'] ?? '—'} '
                '(${r['ai_confidence'] ?? 'n/a'} confidence) · '
                'user: ${r['user_confirmation']} · '
                '${r['latitude']}, ${r['longitude']} · '
                'sensitive: ${r['is_sensitive']}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              if ((r['user_notes'] as String?)?.isNotEmpty ?? false)
                Text('Note: ${r['user_notes']}', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  DropdownButton<String>(
                    value: r['moderation_status'] as String,
                    items: [
                      for (final s in _moderationStatuses)
                        DropdownMenuItem(value: s, child: Text('Status: $s')),
                    ],
                    onChanged: (v) {
                      if (v != null) _setStatus(id, moderationStatus: v);
                    },
                  ),
                  DropdownButton<String>(
                    value: r['visibility'] as String,
                    items: [
                      for (final v in _visibilities)
                        DropdownMenuItem(value: v, child: Text('Visibility: $v')),
                    ],
                    onChanged: (v) {
                      if (v != null) _setStatus(id, visibility: v);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
