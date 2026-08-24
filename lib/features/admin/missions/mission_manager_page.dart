import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/missions/mission_stops_page.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';

/// Admin -> Mission Manager (spec Phase 9) — the minimum capability needed
/// to create and edit a Marion County Adventures mission: CREATE MISSION,
/// then drill into its stops (`MissionStopsPage`) to ADD STOP / ADD TRAVEL
/// STORY / ADD APPROACH STORY / ADD ARRIVAL STORY / ASSIGN QR / CREATE OLD
/// WORLD / ADD CLUE / ASSIGN NEXT STOP, and PUBLISH. Deliberately not a full
/// CMS — reuses the same AdminSectionCard/StatusBadge/AdminPageHeader
/// widgets every other admin module already uses.
class MissionManagerPage extends ConsumerWidget {
  const MissionManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminMissionsProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AdminPageHeader(
          title: 'Mission Manager',
          subtitle: 'Marion County Adventures — create an adventure, add its stops, travel '
              'stories, QR portals, and Old World content, then publish it.',
          actions: [
            FilledButton.icon(
              onPressed: () => _createMission(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Mission'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AdminEmptyState(message: 'Could not load missions: $e'),
          data: (missions) => missions.isEmpty
              ? const AdminEmptyState(
                  message: 'No missions yet. Create one to get started.',
                  icon: Icons.explore_outlined)
              : Column(children: [
                  for (final m in missions) ...[
                    _MissionRow(mission: m),
                    const SizedBox(height: 8),
                  ],
                ]),
        ),
      ],
    );
  }

  Future<void> _createMission(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New mission'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, titleController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    await ref.read(missionRepositoryProvider).createMission({
      'title': title,
      'published': false,
      'completion_reward_xp': 0,
    });
    ref.read(missionsRefreshProvider.notifier).bump();
  }
}

class _MissionRow extends ConsumerWidget {
  const _MissionRow({required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminSectionCard(
      child: ListTile(
        title: Text(mission.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([
          if ((mission.category ?? '').isNotEmpty) mission.category,
          if ((mission.difficulty ?? '').isNotEmpty) mission.difficulty,
        ].whereType<String>().join(' · ')),
        leading: mission.published
            ? const StatusBadge(BadgeStatus.published, label: 'Published')
            : const StatusBadge(BadgeStatus.draft, label: 'Draft'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            final repo = ref.read(missionRepositoryProvider);
            switch (v) {
              case 'publish':
                await repo.updateMission(mission.id, {'published': !mission.published});
                ref.read(missionsRefreshProvider.notifier).bump();
              case 'delete':
                await repo.deleteMission(mission.id);
                ref.read(missionsRefreshProvider.notifier).bump();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
                value: 'publish',
                child: Text(mission.published ? 'Unpublish' : 'Publish')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MissionStopsPage(mission: mission)),
        ),
      ),
    );
  }
}
