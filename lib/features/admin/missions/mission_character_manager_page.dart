import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_character.dart';
import 'package:explorer_os_mobile/features/narration/data/voice_repository.dart';
import 'package:explorer_os_mobile/features/narration/models/voice.dart';

/// Admin -> Character Manager: create/edit the reusable characters every
/// Marion County Adventures story scene can use. CHARACTER -> VOICE ID is
/// set here, once, and every scene naming that character inherits it
/// automatically — nothing else in the app lets a scene pick a voice
/// directly once a character is assigned.
///
/// The voice picker reuses the SAME ElevenLabs voice catalog
/// (`voicesProvider`/`Voice`) the existing Voice Manager already reads —
/// no second voice list, no live ElevenLabs API call (the existing catalog
/// is a curated bundled asset, same as everywhere else this app picks a
/// voice from).
class MissionCharacterManagerPage extends ConsumerWidget {
  const MissionCharacterManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(missionCharactersProvider);
    final voicesAsync = ref.watch(voicesProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AdminPageHeader(
          title: 'Character Manager',
          subtitle: 'Marion County Adventures — reusable characters. Assign each one an '
              'ElevenLabs voice once; every story scene that names the character speaks '
              'in that voice automatically.',
          actions: [
            FilledButton.icon(
              onPressed: () => showCharacterEditorDialog(context, ref, voices: voicesAsync.value ?? const []),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Character'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AdminEmptyState(message: 'Could not load characters: $e'),
          data: (characters) => characters.isEmpty
              ? const AdminEmptyState(
                  message: 'No characters yet. Create one to give your adventures a voice.',
                  icon: Icons.theater_comedy_outlined)
              : Column(children: [
                  for (final c in characters) ...[
                    _CharacterRow(character: c, voices: voicesAsync.value ?? const []),
                    const SizedBox(height: 8),
                  ],
                ]),
        ),
      ],
    );
  }
}

class _CharacterRow extends ConsumerWidget {
  const _CharacterRow({required this.character, required this.voices});
  final MissionCharacter character;
  final List<Voice> voices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceName = voices
        .where((v) => v.voiceId == character.voiceId)
        .map((v) => v.name)
        .firstOrNull;
    return AdminSectionCard(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.teal.withValues(alpha: 0.15),
          backgroundImage:
              (character.imageUrl ?? '').isNotEmpty ? NetworkImage(character.imageUrl!) : null,
          child: (character.imageUrl ?? '').isEmpty
              ? const Icon(Icons.person_rounded, color: Colors.teal)
              : null,
        ),
        title: Text(character.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([
          if ((character.characterType ?? '').isNotEmpty) character.characterType,
          if ((character.role ?? '').isNotEmpty) character.role,
          if (voiceName != null) 'Voice: $voiceName' else if (character.hasVoice) 'Voice: ${character.voiceId}',
        ].whereType<String>().join(' · ')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          StatusBadge(
            character.active ? BadgeStatus.published : BadgeStatus.draft,
            label: character.active ? 'Active' : 'Inactive',
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final repo = ref.read(missionRepositoryProvider);
              switch (v) {
                case 'edit':
                  await showCharacterEditorDialog(context, ref, character: character, voices: voices);
                case 'toggle':
                  await repo.updateCharacter(character.id, {'active': !character.active});
                  ref.read(missionsRefreshProvider.notifier).bump();
                case 'delete':
                  await repo.deleteCharacter(character.id);
                  ref.read(missionsRefreshProvider.notifier).bump();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                  value: 'toggle', child: Text(character.active ? 'Deactivate' : 'Activate')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        onTap: () => showCharacterEditorDialog(context, ref, character: character, voices: voices),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// The character create/edit dialog — name, type, personality, role, image,
/// and the voice picker (falls back to a plain voice-id text field if the
/// catalog hasn't loaded, so a character can still be created offline).
Future<void> showCharacterEditorDialog(
  BuildContext context,
  WidgetRef ref, {
  MissionCharacter? character,
  required List<Voice> voices,
}) async {
  final name = TextEditingController(text: character?.name ?? '');
  final description = TextEditingController(text: character?.description ?? '');
  final personality = TextEditingController(text: character?.personality ?? '');
  final role = TextEditingController(text: character?.role ?? '');
  final imageUrl = TextEditingController(text: character?.imageUrl ?? '');
  final manualVoiceId = TextEditingController(text: character?.voiceId ?? '');
  final heygenAvatarId = TextEditingController(text: character?.heygenAvatarId ?? '');
  var characterType = character?.characterType;
  var voiceId = character?.voiceId;
  var active = character?.active ?? true;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(character == null ? 'New character' : 'Edit character'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: characterType,
                    decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final t in kMissionCharacterTypes) DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: (v) => setState(() => characterType = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: role,
                    decoration: const InputDecoration(
                        labelText: 'Role (e.g. "Explorer")', border: OutlineInputBorder()),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: personality,
                decoration: const InputDecoration(
                    labelText: 'Personality (e.g. "Curious, determined, mysterious")',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: imageUrl,
                  decoration: const InputDecoration(
                      labelText: 'Character image URL', border: OutlineInputBorder())),
              const SizedBox(height: 20),
              const Text('Voice', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text(
                'Every story scene that uses this character speaks in this voice automatically.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              if (voices.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: voices.any((v) => v.voiceId == voiceId) ? voiceId : null,
                  decoration: const InputDecoration(
                      labelText: 'ElevenLabs voice', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— none assigned yet —')),
                    for (final v in voices) DropdownMenuItem(value: v.voiceId, child: Text(v.name)),
                  ],
                  onChanged: (v) => setState(() => voiceId = v),
                )
              else
                TextField(
                  controller: manualVoiceId,
                  decoration: const InputDecoration(
                      labelText: 'ElevenLabs Voice ID', border: OutlineInputBorder()),
                ),
              const SizedBox(height: 20),
              const Text('Avatar', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text(
                'HeyGen isn\'t connected yet — this is stored for when avatar video '
                'presentation is wired up, so nothing needs re-entering later.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: heygenAvatarId,
                decoration: const InputDecoration(
                    labelText: 'HeyGen Avatar ID (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                onChanged: (v) => setState(() => active = v),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(character == null ? 'Create' : 'Save')),
        ],
      ),
    ),
  );

  if (saved != true || name.text.trim().isEmpty) return;
  final row = {
    'name': name.text.trim(),
    'character_type': characterType,
    'role': role.text.trim().isEmpty ? null : role.text.trim(),
    'personality': personality.text.trim().isEmpty ? null : personality.text.trim(),
    'description': description.text.trim().isEmpty ? null : description.text.trim(),
    'image_url': imageUrl.text.trim().isEmpty ? null : imageUrl.text.trim(),
    'voice_id': voices.isNotEmpty
        ? voiceId
        : (manualVoiceId.text.trim().isEmpty ? null : manualVoiceId.text.trim()),
    'heygen_avatar_id': heygenAvatarId.text.trim().isEmpty ? null : heygenAvatarId.text.trim(),
    'active': active,
  };
  final repo = ref.read(missionRepositoryProvider);
  if (character == null) {
    await repo.createCharacter(row);
  } else {
    await repo.updateCharacter(character.id, row);
  }
  ref.read(missionsRefreshProvider.notifier).bump();
}
