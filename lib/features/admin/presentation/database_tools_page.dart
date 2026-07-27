import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/db_tools/db_tools.dart';
import 'package:explorer_os_mobile/features/admin/db_tools/db_tools_repository.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';

/// Admin → Database Tools: an in-dashboard database management center so
/// routine work doesn't need the Supabase SQL editor. Dashboard (live counts),
/// Tables (browse/delete), Maintenance (one-click safe checks/fixes), and
/// Export (CSV). All operations run through PostgREST within the app's RLS —
/// raw SQL / backups / migrations remain in the Supabase editor by design.
class DatabaseToolsPage extends StatelessWidget {
  const DatabaseToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.dashboard_rounded), text: 'Dashboard'),
                Tab(icon: Icon(Icons.table_rows_rounded), text: 'Tables'),
                Tab(icon: Icon(Icons.build_rounded), text: 'Maintenance'),
                Tab(icon: Icon(Icons.download_rounded), text: 'Export'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                _DashboardTab(),
                _TablesTab(),
                _MaintenanceTab(),
                _ExportTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dashboard ─────────────────────────────────────────────────────────────────

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(dbCountsProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Database Dashboard',
          subtitle: 'Live record counts across the app\'s tables.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(dbCountsProvider),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('$e'),
          data: (counts) => GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 900 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 1.5,
            children: [
              for (final t in kDashboardTables)
                AdminStatCard(
                  label: t.label,
                  value: (counts[t.name] ?? -1) < 0
                      ? '—'
                      : '${counts[t.name]}',
                  icon: Icons.storage_rounded,
                  hint: (counts[t.name] ?? -1) < 0 ? 'no table' : null,
                ),
            ],
          ),
        ),
        const Gap.v(AppSpacing.lg),
        Text(
          'Raw SQL, backups, and migrations remain in the Supabase SQL editor. '
          'Everyday browsing, checks, fixes, and exports are here.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

// ── Tables browser ────────────────────────────────────────────────────────────

class _TablesTab extends ConsumerStatefulWidget {
  const _TablesTab();
  @override
  ConsumerState<_TablesTab> createState() => _TablesTabState();
}

class _TablesTabState extends ConsumerState<_TablesTab> {
  DbTable _table = kDbTables.first;
  late Future<({int count, List<Map<String, dynamic>> rows})> _future = _load();
  String _q = '';

  Future<({int count, List<Map<String, dynamic>> rows})> _load() async {
    final repo = ref.read(dbToolsRepositoryProvider);
    final count = await repo.count(_table.name);
    final rows = await repo.rows(_table.name, limit: 100);
    return (count: count, rows: rows);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Table Browser',
          subtitle: 'Browse recent rows, search, and delete.',
          actions: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<DbTable>(
                initialValue: _table,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Table', isDense: true, border: OutlineInputBorder()),
                items: [
                  for (final t in kDbTables)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) {
                  if (t != null) setState(() => _table = t);
                  _reload();
                },
              ),
            ),
          ],
        ),
        const Gap.v(AppSpacing.md),
        TextField(
          onChanged: (v) => setState(() => _q = v.toLowerCase()),
          decoration: const InputDecoration(
              labelText: 'Search loaded rows',
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder()),
        ),
        const Gap.v(AppSpacing.lg),
        FutureBuilder<({int count, List<Map<String, dynamic>> rows})>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Center(child: CircularProgressIndicator()));
            }
            final count = snap.data?.count ?? -1;
            final all = snap.data?.rows ?? const [];
            final rows = all.where((r) {
              if (_q.isEmpty) return true;
              return r.values.any((v) => '$v'.toLowerCase().contains(_q));
            }).toList();
            if (rows.isEmpty) {
              return AdminSectionCard(
                  child: AdminEmptyState(
                      icon: Icons.table_rows_rounded,
                      message: count < 0
                          ? 'Table "${_table.name}" not found.'
                          : 'No rows.'));
            }
            return AdminSectionCard(
              child: Column(children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                        '$count total in ${_table.name}'
                        '${all.length < count ? ' (showing first ${all.length})' : ''}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
                for (final r in rows) _row(context, r),
              ]),
            );
          },
        ),
      ],
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> r) {
    final theme = Theme.of(context);
    final id = r['id'] ?? r['media_id'] ?? r['species_id'] ?? r['story_id'];
    final title = (r['title'] ?? r['name'] ?? r['common_name'] ?? id ?? '(row)')
        .toString();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: id != null ? Text('$id', style: theme.textTheme.bodySmall) : null,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in r.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text('${e.key}: ${e.value}',
                      style: theme.textTheme.bodySmall),
                ),
              if (id != null) ...[
                const Gap.v(AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _confirmDelete(context, id),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete row'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, dynamic id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this row?'),
        content: Text('Table: ${_table.name}\nid: $id\n\nThis cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(dbToolsRepositoryProvider).deleteRow(_table.name, id);
      _reload();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }
}

// ── Maintenance ──────────────────────────────────────────────────────────────

class _MaintenanceTab extends ConsumerStatefulWidget {
  const _MaintenanceTab();
  @override
  ConsumerState<_MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends ConsumerState<_MaintenanceTab> {
  final Map<String, String> _results = {};
  bool _busy = false;

  Future<void> _run(MaintenanceScript s) async {
    setState(() => _busy = true);
    final repo = ref.read(dbToolsRepositoryProvider);
    try {
      if (s.isDestructive) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(s.label),
            content: Text('${s.description}\n\nApply this change to all matching '
                'rows in ${s.table}?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Apply')),
            ],
          ),
        );
        if (ok != true) {
          setState(() => _busy = false);
          return;
        }
        final n = await repo.runFix(s);
        setState(() => _results[s.id] = 'Updated $n row(s).');
      } else {
        final rows = await repo.runCheck(s);
        final sample = rows
            .take(5)
            .map((r) =>
                (r['title'] ?? r['name'] ?? r['common_name'] ?? r['id'] ?? '?')
                    .toString())
            .join(', ');
        setState(() => _results[s.id] =
            '${rows.length} match(es)${sample.isNotEmpty ? ': $sample' : ''}');
      }
    } catch (e) {
      setState(() => _results[s.id] = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Maintenance',
          subtitle: 'One-click checks and safe fixes. Destructive actions ask '
              'for confirmation.',
        ),
        const Gap.v(AppSpacing.lg),
        for (final s in kMaintenanceScripts) ...[
          AdminSectionCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(s.isDestructive ? Icons.warning_amber_rounded : Icons.search_rounded,
                    color: s.isDestructive ? Colors.orange : theme.colorScheme.primary),
                const Gap.h(AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.label,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${s.description}  (${s.table})',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                (s.isDestructive
                        ? FilledButton.icon(
                            onPressed: _busy ? null : () => _run(s),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 40),
                                backgroundColor: Colors.orange.shade800),
                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                            label: const Text('Run fix'))
                        : OutlinedButton.icon(
                            onPressed: _busy ? null : () => _run(s),
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 40)),
                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                            label: const Text('Run'))),
              ]),
              if (_results[s.id] != null) ...[
                const Gap.v(AppSpacing.sm),
                Text(_results[s.id]!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
          const Gap.v(AppSpacing.md),
        ],
      ],
    );
  }
}

// ── Export ────────────────────────────────────────────────────────────────────

class _ExportTab extends ConsumerStatefulWidget {
  const _ExportTab();
  @override
  ConsumerState<_ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends ConsumerState<_ExportTab> {
  DbTable _table = kDbTables.first;
  bool _busy = false;
  String? _csv;
  int _rows = 0;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _csv = null;
    });
    try {
      final rows =
          await ref.read(dbToolsRepositoryProvider).rows(_table.name, limit: 1000);
      setState(() {
        _rows = rows.length;
        _csv = csvEncode(rows);
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _csv = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Export',
          subtitle: 'Export a table to CSV (up to 1000 rows).',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<DbTable>(
                  initialValue: _table,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Table', isDense: true, border: OutlineInputBorder()),
                  items: [
                    for (final t in kDbTables)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (t) => setState(() => _table = t ?? _table),
                ),
              ),
              const Gap.h(AppSpacing.md),
              FilledButton.icon(
                onPressed: _busy ? null : _export,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download_rounded, size: 18),
                label: const Text('Export CSV'),
              ),
            ]),
            if (_csv != null) ...[
              const Gap.v(AppSpacing.md),
              Row(children: [
                Text('$_rows rows', style: theme.textTheme.bodySmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _csv ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('CSV copied to clipboard')));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy CSV'),
                ),
              ]),
              Container(
                height: 300,
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(_csv!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}
