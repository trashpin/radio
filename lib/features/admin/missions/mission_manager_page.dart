import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/missions/mission_facts_puzzles_page.dart';
import 'package:explorer_os_mobile/features/admin/missions/mission_image_picker.dart';
import 'package:explorer_os_mobile/features/admin/missions/mission_stops_page.dart';
import 'package:explorer_os_mobile/features/admin/missions/story_builder_page.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';

const List<String> _kDifficulties = ['easy', 'adventure', 'challenge', 'master'];

/// Admin -> Mission Manager (spec Phase 9) — the minimum capability needed
/// to create and edit a Marion County Adventures mission: CREATE MISSION
/// (with every Phase-1 field, not just a title), then drill into its stops
/// (`MissionStopsPage`) to ADD STOP / ADD TRAVEL STORY / ADD APPROACH STORY
/// / ADD ARRIVAL STORY / ASSIGN QR / CREATE OLD WORLD / ADD CLUE / ASSIGN
/// NEXT STOP, and PUBLISH. Deliberately not a full CMS — reuses the same
/// AdminSectionCard/StatusBadge/AdminPageHeader widgets every other admin
/// module already uses.
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
              onPressed: () => showMissionEditorDialog(context, ref),
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
          if (mission.estimatedDurationMinutes != null) '${mission.estimatedDurationMinutes} min',
        ].whereType<String>().join(' · ')),
        leading: mission.published
            ? const StatusBadge(BadgeStatus.published, label: 'Published')
            : const StatusBadge(BadgeStatus.draft, label: 'Draft'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Manage stops',
            icon: const Icon(Icons.pin_drop_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MissionStopsPage(mission: mission)),
            ),
          ),
          IconButton(
            tooltip: 'Facts & final puzzle',
            icon: const Icon(Icons.psychology_alt_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MissionFactsPuzzlesPage(mission: mission)),
            ),
          ),
          IconButton(
            tooltip: 'Story Builder',
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StoryBuilderPage(mission: mission)),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final repo = ref.read(missionRepositoryProvider);
              switch (v) {
                case 'edit':
                  await showMissionEditorDialog(context, ref, mission: mission);
                case 'publish':
                  await repo.updateMission(mission.id, {'published': !mission.published});
                  ref.read(missionsRefreshProvider.notifier).bump();
                case 'delete':
                  await repo.deleteMission(mission.id);
                  ref.read(missionsRefreshProvider.notifier).bump();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit details')),
              PopupMenuItem(
                  value: 'publish',
                  child: Text(mission.published ? 'Unpublish' : 'Publish')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MissionStopsPage(mission: mission)),
        ),
      ),
    );
  }
}

/// The full mission create/edit dialog — every Phase-1 field. Used for both
/// "New Mission" (no [mission]) and "Edit details".
Future<void> showMissionEditorDialog(BuildContext context, WidgetRef ref, {Mission? mission}) async {
  final title = TextEditingController(text: mission?.title ?? '');
  final description = TextEditingController(text: mission?.description ?? '');
  final category = TextEditingController(text: mission?.category ?? '');
  final duration = TextEditingController(text: mission?.estimatedDurationMinutes?.toString() ?? '');
  final introCharacter = TextEditingController(text: mission?.introCharacterName ?? '');
  final openingText = TextEditingController(text: mission?.openingNarrationText ?? '');
  final missionBrief = TextEditingController(text: mission?.missionBriefText ?? '');
  final rewardXp = TextEditingController(text: '${mission?.completionRewardXp ?? 0}');
  final badge = TextEditingController(text: mission?.completionBadge ?? '');
  final finalReveal = TextEditingController(text: mission?.finalRevealText ?? '');
  final realHistory = TextEditingController(text: mission?.realHistoryText ?? '');
  final heroImageUrl = TextEditingController(text: mission?.heroImageUrl ?? '');
  final storyHook = TextEditingController(text: mission?.storyHook ?? '');
  final imageClueText = TextEditingController(text: mission?.imageClueText ?? '');
  var difficulty = mission?.difficulty;
  var introCharacterId = mission?.introCharacterId;
  final characters = await ref.read(missionRepositoryProvider).allCharacters();

  if (!context.mounted) return;
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(mission == null ? 'New mission' : 'Edit mission'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: category,
                    decoration: const InputDecoration(
                        labelText: 'Category (history, mystery, nature...)',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: difficulty,
                    decoration:
                        const InputDecoration(labelText: 'Difficulty', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final d in _kDifficulties) DropdownMenuItem(value: d, child: Text(d)),
                    ],
                    onChanged: (v) => setState(() => difficulty = v),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Estimated duration (minutes)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              const Text('Adventure Card', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text(
                'The storefront: mystery artwork and a curiosity-only teaser. Never reveal '
                'destinations, stops, the route, or the answer — the image should represent the '
                'mystery, not the place. Reused on the Mission Introduction screen too.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    controller: heroImageUrl,
                    decoration: const InputDecoration(
                        labelText: 'Introduction image URL', border: OutlineInputBorder()),
                  ),
                ),
                if (mission != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final changed = await showMissionImagePicker(context, mission);
                      if (changed && dialogContext.mounted) {
                        final refreshed = await ref.read(missionRepositoryProvider).byId(mission.id);
                        if (refreshed != null) {
                          heroImageUrl.text = refreshed.heroImageUrl ?? '';
                          setState(() {});
                        }
                      }
                    },
                    icon: const Icon(Icons.image_search_rounded, size: 16),
                    label: const Text('Find'),
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: storyHook,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Story hook (curiosity only — never the destination)',
                    helperText: 'e.g. "Someone disappeared following a trail through Marion '
                        'County. The evidence survived. Can you figure out what it means?"',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: imageClueText,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Image clue (admin-only — never shown to players)',
                    helperText: 'What the image secretly hints at, so a later story step can '
                        'pay it off — e.g. "The lantern matches the one in the final reveal."',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              const Text('Adventure Introduction',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const Text(
                'Shown BEFORE the map/GPS player — the story that pulls the player in.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              if (characters.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: characters.any((c) => c.id == introCharacterId) ? introCharacterId : null,
                  decoration: const InputDecoration(
                      labelText: 'Character who speaks the introduction',
                      helperText: 'Their assigned voice speaks the opening narration below.',
                      border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— none / use free text below —')),
                    for (final c in characters) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => introCharacterId = v),
                ),
              const SizedBox(height: 8),
              TextField(
                  controller: introCharacter,
                  decoration: const InputDecoration(
                      labelText: 'Or: speaker name as free text (no character record)',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                controller: openingText,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Opening narration (the story itself)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: missionBrief,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'YOUR MISSION (what to find / why / what to figure out)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              const Text('Completion', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: finalReveal,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Final reveal (how the clues connected, optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: realHistory,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: '"THE REAL HISTORY" (optional)',
                    helperText: 'What\'s historically verified, what source supports it, what '
                        'was fictionalized, and why it matters. Shown separately from the '
                        'dramatic final reveal above — never present invented dialogue as an '
                        'authentic historical quote.',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: rewardXp,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Completion reward XP', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: badge,
                    decoration: const InputDecoration(
                        labelText: 'Completion badge (optional)', border: OutlineInputBorder()),
                  ),
                ),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(mission == null ? 'Create' : 'Save')),
        ],
      ),
    ),
  );

  if (saved != true || title.text.trim().isEmpty) return;
  final row = {
    'title': title.text.trim(),
    'description': description.text.trim().isEmpty ? null : description.text.trim(),
    'category': category.text.trim().isEmpty ? null : category.text.trim(),
    'difficulty': difficulty,
    'estimated_duration_minutes': int.tryParse(duration.text.trim()),
    'opening_narration_text': openingText.text.trim().isEmpty ? null : openingText.text.trim(),
    'intro_character_name': introCharacter.text.trim().isEmpty ? null : introCharacter.text.trim(),
    'intro_character_id': introCharacterId,
    'mission_brief_text': missionBrief.text.trim().isEmpty ? null : missionBrief.text.trim(),
    'final_reveal_text': finalReveal.text.trim().isEmpty ? null : finalReveal.text.trim(),
    'real_history_text': realHistory.text.trim().isEmpty ? null : realHistory.text.trim(),
    'completion_reward_xp': int.tryParse(rewardXp.text.trim()) ?? 0,
    'completion_badge': badge.text.trim().isEmpty ? null : badge.text.trim(),
    'hero_image_url': heroImageUrl.text.trim().isEmpty ? null : heroImageUrl.text.trim(),
    'story_hook': storyHook.text.trim().isEmpty ? null : storyHook.text.trim(),
    'image_clue_text': imageClueText.text.trim().isEmpty ? null : imageClueText.text.trim(),
  };
  final repo = ref.read(missionRepositoryProvider);
  if (mission == null) {
    row['published'] = false;
    await repo.createMission(row);
  } else {
    await repo.updateMission(mission.id, row);
  }
  ref.read(missionsRefreshProvider.notifier).bump();
}
