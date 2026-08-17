import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/radio_scheduler/controllers/rundown_playback_controller.dart';
import 'package:explorer_os_mobile/features/radio_scheduler/data/rundown_repository.dart';
import 'package:explorer_os_mobile/features/radio_scheduler/models/rundown.dart';

/// Admin → Radio Scheduler: a professional radio rundown builder.
///
/// LEFT = Content Library (tap or drag a type onto the timeline), CENTER =
/// drag-to-reorder Timeline (start/name/type/duration/end + enable/delete),
/// RIGHT = Item Properties. A top bar creates/names/schedules/publishes
/// rundowns; a transport bar previews the rundown through the EXISTING radio
/// audio engine (via [RundownPlaybackController]); and a Now-Playing panel
/// shows current/next/upcoming + elapsed/remaining.
class RundownBuilderPage extends ConsumerStatefulWidget {
  const RundownBuilderPage({super.key});

  @override
  ConsumerState<RundownBuilderPage> createState() => _RundownBuilderPageState();
}

class _RundownBuilderPageState extends ConsumerState<RundownBuilderPage> {
  final _nameCtrl = TextEditingController(text: 'Untitled rundown');

  String? _rundownId; // null = unsaved new rundown
  DateTime? _scheduledAt;
  RundownRecurrence _recurrence = RundownRecurrence.none;
  bool _published = false;
  bool _active = true;

  List<RundownItem> _items = [];
  final Set<String> _deletedIds = {};
  String? _selectedItemId;
  int _tmpCounter = 0;
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  RundownRepository get _repo => ref.read(rundownRepositoryProvider);

  RundownItem? get _selected {
    for (final i in _items) {
      if (i.id == _selectedItemId) return i;
    }
    return null;
  }

  // --- Rundown lifecycle -----------------------------------------------------

  void _newRundown() {
    setState(() {
      _rundownId = null;
      _nameCtrl.text = 'Untitled rundown';
      _scheduledAt = null;
      _recurrence = RundownRecurrence.none;
      _published = false;
      _active = true;
      _items = [];
      _deletedIds.clear();
      _selectedItemId = null;
      _dirty = true;
    });
  }

  Future<void> _loadRundown(Rundown r) async {
    final items = await _repo.items(r.id);
    if (!mounted) return;
    setState(() {
      _rundownId = r.id;
      _nameCtrl.text = r.name;
      _scheduledAt = r.scheduledAt;
      _recurrence = r.recurrence;
      _published = r.published;
      _active = r.active;
      _items = items;
      _deletedIds.clear();
      _selectedItemId = null;
      _dirty = false;
    });
  }

  Future<void> _save({bool publish = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (publish) _published = true;
      final name =
          _nameCtrl.text.trim().isEmpty ? 'Untitled rundown' : _nameCtrl.text.trim();

      var id = _rundownId;
      id ??= await _repo.createRundown(name);
      if (id == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Could not save — Supabase is not configured.')));
        return;
      }
      await _repo.updateRundown(id, {
        'name': name,
        'scheduled_at': _scheduledAt?.toUtc().toIso8601String(),
        'recurrence': _recurrence.id,
        'published': _published,
        'active': _active,
      });

      for (final del in _deletedIds) {
        await _repo.deleteItem(del);
      }
      _deletedIds.clear();

      // Persist items with their current order + rundown id.
      final toSave = [
        for (var i = 0; i < _items.length; i++)
          _items[i].copyWith(rundownId: id, sortOrder: i)
      ];
      await _repo.saveItems(toSave);

      ref.read(rundownRefreshProvider.notifier).bump();
      // Reload so locally-created items pick up their real database ids.
      final fresh = await _repo.withItems(id);
      if (!mounted) return;
      setState(() {
        _rundownId = id;
        if (fresh != null) {
          _published = fresh.published;
          _active = fresh.active;
          _items = fresh.items;
        }
        _selectedItemId = null;
        _dirty = false;
      });
      messenger.showSnackBar(SnackBar(
          content: Text(publish ? 'Rundown published.' : 'Rundown saved.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteRundown() async {
    final id = _rundownId;
    if (id == null) {
      _newRundown();
      return;
    }
    await _repo.deleteRundown(id);
    ref.read(rundownRefreshProvider.notifier).bump();
    _newRundown();
  }

  // --- Item editing ----------------------------------------------------------

  void _addItem(RundownItemType type) {
    final item = RundownItem(
      id: 'tmp_${_tmpCounter++}',
      rundownId: _rundownId ?? '',
      type: type,
      sortOrder: _items.length,
      name: '',
      durationSeconds: 0,
      enabled: true,
    );
    setState(() {
      _items = [..._items, item];
      _selectedItemId = item.id;
      _dirty = true;
    });
  }

  void _updateSelected(RundownItem Function(RundownItem) f) {
    final id = _selectedItemId;
    if (id == null) return;
    setState(() {
      _items = [
        for (final i in _items) if (i.id == id) f(i) else i,
      ];
      _dirty = true;
    });
  }

  void _deleteItem(RundownItem item) {
    if (!RundownRepository.isNewId(item.id)) _deletedIds.add(item.id);
    setState(() {
      _items = [for (final i in _items) if (i.id != item.id) i];
      if (_selectedItemId == item.id) _selectedItemId = null;
      _dirty = true;
    });
  }

  // onReorderItem already adjusts newIndex for the removed item, so no manual
  // "-1 when moving down" fixup is needed here.
  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final list = [..._items];
      final moved = list.removeAt(oldIndex);
      list.insert(newIndex, moved);
      _items = list;
      _dirty = true;
    });
  }

  // --- Preview transport -----------------------------------------------------

  void _preview() =>
      ref.read(rundownPlaybackControllerProvider.notifier).play(_items);
  void _previewFromSelected() {
    final id = _selectedItemId;
    if (id == null) return;
    ref
        .read(rundownPlaybackControllerProvider.notifier)
        .startFromItem(_items, id);
  }

  @override
  Widget build(BuildContext context) {
    final rundowns = ref.watch(rundownsProvider).value ?? const <Rundown>[];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(rundowns),
          const SizedBox(height: 12),
          _transportBar(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 220, child: _contentLibrary()),
                const SizedBox(width: 12),
                Expanded(child: _timeline()),
                const SizedBox(width: 12),
                SizedBox(width: 320, child: _properties()),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _nowPlaying(),
        ],
      ),
    );
  }

  // --- Top bar ---------------------------------------------------------------

  Widget _topBar(List<Rundown> rundowns) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String?>(
              value: rundowns.any((r) => r.id == _rundownId) ? _rundownId : null,
              hint: const Text('New rundown'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('New rundown')),
                for (final r in rundowns)
                  DropdownMenuItem<String?>(
                    value: r.id,
                    child: Text(
                        '${r.name}${r.published ? " ·published" : ""}'),
                  ),
              ],
              onChanged: (id) {
                if (id == null) {
                  _newRundown();
                } else {
                  final r = rundowns.firstWhere((x) => x.id == id);
                  _loadRundown(r);
                }
              },
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _newRundown,
              icon: const Icon(Icons.add),
              label: const Text('New'),
            ),
            SizedBox(
              width: 240,
              child: TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Rundown name',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _dirty = true,
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _pickDateTime,
              icon: const Icon(Icons.schedule),
              label: Text(_scheduledAt == null
                  ? 'Set date/time'
                  : _fmtDateTime(_scheduledAt!)),
            ),
            if (_scheduledAt != null)
              IconButton(
                tooltip: 'Clear date/time',
                onPressed: () => setState(() {
                  _scheduledAt = null;
                  _dirty = true;
                }),
                icon: const Icon(Icons.clear),
              ),
            DropdownButton<RundownRecurrence>(
              value: _recurrence,
              items: [
                for (final r in RundownRecurrence.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => setState(() {
                _recurrence = r ?? RundownRecurrence.none;
                _dirty = true;
              }),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Active'),
              Switch(
                value: _active,
                onChanged: (v) => setState(() {
                  _active = v;
                  _dirty = true;
                }),
              ),
            ]),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _saving ? null : () => _save(),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_dirty ? 'Save*' : 'Save'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  minimumSize: const Size(0, 44)),
              onPressed: _saving ? null : () => _save(publish: true),
              icon: const Icon(Icons.publish),
              label: Text(_published ? 'Published' : 'Publish'),
            ),
            IconButton(
              tooltip: 'Delete rundown',
              onPressed: _deleteRundown,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? now),
    );
    if (!mounted) return;
    setState(() {
      _scheduledAt = DateTime(date.year, date.month, date.day,
          time?.hour ?? 0, time?.minute ?? 0);
      _dirty = true;
    });
  }

  // --- Transport -------------------------------------------------------------

  Widget _transportBar() {
    final state = ref.watch(rundownPlaybackControllerProvider);
    final ctrl = ref.read(rundownPlaybackControllerProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.preview),
            const SizedBox(width: 8),
            const Text('Preview', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _items.isEmpty ? null : _preview,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Pause',
              onPressed: state.playing && !state.paused ? ctrl.pause : null,
              icon: const Icon(Icons.pause),
            ),
            IconButton(
              tooltip: 'Resume',
              onPressed: state.paused ? ctrl.resume : null,
              icon: const Icon(Icons.play_circle),
            ),
            IconButton(
              tooltip: 'Skip',
              onPressed: state.active ? ctrl.skip : null,
              icon: const Icon(Icons.skip_next),
            ),
            IconButton(
              tooltip: 'Stop',
              onPressed: state.active ? ctrl.stop : null,
              icon: const Icon(Icons.stop),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _selectedItemId == null ? null : _previewFromSelected,
              icon: const Icon(Icons.play_for_work),
              label: const Text('Start from selected'),
            ),
            const SizedBox(width: 16),
            Text('Total: ${formatClockSeconds(_totalSeconds())}'),
          ],
        ),
      ),
    );
  }

  int _totalSeconds() => _items
      .where((i) => i.enabled)
      .fold(0, (s, i) => s + i.effectiveSeconds);

  // --- Content library -------------------------------------------------------

  Widget _contentLibrary() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Content Library',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final type in RundownItemType.values)
                  _libraryEntry(type),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _libraryEntry(RundownItemType type) {
    final tile = Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: Icon(type.icon),
        title: Text(type.label),
        subtitle: Text('${type.defaultSeconds}s default'),
        trailing: const Icon(Icons.add_circle_outline),
        onTap: () => _addItem(type),
      ),
    );
    return LongPressDraggable<RundownItemType>(
      data: type,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(type.icon),
            const SizedBox(width: 8),
            Text(type.label),
          ]),
        ),
      ),
      child: tile,
    );
  }

  // --- Timeline --------------------------------------------------------------

  Widget _timeline() {
    // Compute clock offsets across enabled items, in order.
    final offsets = <String, int>{};
    var running = 0;
    for (final i in _items) {
      offsets[i.id] = running;
      if (i.enabled) running += i.effectiveSeconds;
    }

    return DragTarget<RundownItemType>(
      onAcceptWithDetails: (d) => _addItem(d.data),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return Card(
          color: highlighted
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Timeline',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              _timelineHeader(),
              const Divider(height: 1),
              Expanded(
                child: _items.isEmpty
                    ? const Center(
                        child: Text(
                          'Tap or drag content from the library to build '
                          'your rundown.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.all(8),
                        itemCount: _items.length,
                        onReorderItem: _reorder,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _timelineRow(
                              item, index, offsets[item.id] ?? 0);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _timelineHeader() {
    const style = TextStyle(fontWeight: FontWeight.w600, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 4, 12, 4),
      child: Row(
        children: const [
          SizedBox(width: 64, child: Text('Start', style: style)),
          Expanded(flex: 3, child: Text('Item', style: style)),
          Expanded(flex: 2, child: Text('Type', style: style)),
          SizedBox(width: 64, child: Text('Dur', style: style)),
          SizedBox(width: 64, child: Text('End', style: style)),
          SizedBox(width: 96, child: Text('', style: style)),
        ],
      ),
    );
  }

  Widget _timelineRow(RundownItem item, int index, int startOffset) {
    final selected = item.id == _selectedItemId;
    final end = startOffset + item.effectiveSeconds;
    final disabled = !item.enabled;
    final playable = item.isPlayable;
    return Container(
      key: ValueKey(item.id),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .5)
            : null,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedItemId = item.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.drag_indicator, size: 20),
                ),
              ),
              SizedBox(
                  width: 64,
                  child: Text(disabled ? '—' : formatClockSeconds(startOffset))),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Icon(item.type.icon, size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        item.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          decoration:
                              disabled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (!playable)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Tooltip(
                          message: 'No audio or script — will be skipped',
                          child: Icon(Icons.warning_amber_rounded,
                              size: 16, color: Colors.orange),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(flex: 2, child: Text(item.type.label)),
              SizedBox(
                  width: 64,
                  child: Text(formatClockSeconds(item.effectiveSeconds))),
              SizedBox(
                  width: 64,
                  child: Text(disabled ? '—' : formatClockSeconds(end))),
              SizedBox(
                width: 96,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: item.enabled ? 'Disable' : 'Enable',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        _items = [
                          for (final i in _items)
                            if (i.id == item.id)
                              i.copyWith(enabled: !i.enabled)
                            else
                              i
                        ];
                        _dirty = true;
                      }),
                      icon: Icon(item.enabled
                          ? Icons.toggle_on
                          : Icons.toggle_off_outlined),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _deleteItem(item),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Properties ------------------------------------------------------------

  Widget _properties() {
    final item = _selected;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Item Properties',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          Expanded(
            child: item == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Select a timeline item to edit it.'),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: _propertyFields(item),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _propertyFields(RundownItem item) {
    return [
      DropdownButtonFormField<RundownItemType>(
        initialValue: item.type,
        decoration: const InputDecoration(
            labelText: 'Type', border: OutlineInputBorder(), isDense: true),
        items: [
          for (final t in RundownItemType.values)
            DropdownMenuItem(
                value: t,
                child: Row(children: [
                  Icon(t.icon, size: 16),
                  const SizedBox(width: 6),
                  Text(t.label),
                ])),
        ],
        onChanged: (t) {
          if (t != null) _updateSelected((i) => i.copyWith(type: t));
        },
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: ValueKey('name-${item.id}'),
        initialValue: item.name,
        decoration: InputDecoration(
          labelText: 'Name',
          hintText: item.type.label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) => _updateSelected((i) => i.copyWith(name: v)),
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: ValueKey('dur-${item.id}'),
        initialValue:
            item.durationSeconds > 0 ? item.durationSeconds.toString() : '',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Duration (seconds)',
          hintText: '${item.type.defaultSeconds} (default)',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) => _updateSelected(
            (i) => i.copyWith(durationSeconds: int.tryParse(v.trim()) ?? 0)),
      ),
      if (!item.type.isSilence) ...[
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('audio-${item.id}'),
          initialValue: item.audioUrl ?? '',
          decoration: const InputDecoration(
            labelText: 'Audio URL',
            hintText: 'https://…  (recorded clip)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => _updateSelected(
              (i) => i.copyWith(audioUrl: v.trim().isEmpty ? null : v.trim())),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('script-${item.id}'),
          initialValue: item.script ?? '',
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Script (spoken via TTS when no audio URL)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => _updateSelected(
              (i) => i.copyWith(script: v.trim().isEmpty ? null : v.trim())),
        ),
      ],
      const SizedBox(height: 12),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enabled'),
        value: item.enabled,
        onChanged: (v) => _updateSelected((i) => i.copyWith(enabled: v)),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _previewFromSelected,
        icon: const Icon(Icons.play_for_work),
        label: const Text('Start preview here'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        onPressed: () => _deleteItem(item),
        icon: const Icon(Icons.delete_outline),
        label: const Text('Delete item'),
      ),
    ];
  }

  // --- Now Playing -----------------------------------------------------------

  Widget _nowPlaying() {
    final state = ref.watch(rundownPlaybackControllerProvider);
    final current = state.current;
    if (!state.active || current == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: const [
              Icon(Icons.radio),
              SizedBox(width: 8),
              Text('Now Playing — idle. Press Play to preview the rundown.'),
            ],
          ),
        ),
      );
    }
    final next = state.next;
    final upcoming = state.upcoming;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(current.type.icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'NOW: ${current.displayName}  ·  ${current.type.label}'
                    '${state.paused ? "  (paused)" : ""}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                    '${formatClockSeconds(state.elapsedSeconds)} / '
                    '${formatClockSeconds(current.effectiveSeconds)}'
                    '  (-${formatClockSeconds(state.remainingSeconds)})'),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: current.effectiveSeconds == 0
                  ? 0
                  : (state.elapsedSeconds / current.effectiveSeconds)
                      .clamp(0.0, 1.0),
            ),
            const SizedBox(height: 8),
            Text('NEXT: ${next?.displayName ?? "— end of rundown —"}'),
            if (upcoming.length > 1) ...[
              const SizedBox(height: 4),
              Text(
                'UPCOMING: ${upcoming.skip(1).take(4).map((i) => i.displayName).join("  →  ")}',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
