import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/events/event_image_picker.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/events/data/event_repository.dart';
import 'package:explorer_os_mobile/features/events/models/local_event.dart';

/// Admin → Events Manager: the ONE place to add/edit the EVENT tier of the
/// location-aware player (EVENT > PARK > SPRING > TOWN > COUNTY) — previously
/// this table had no admin UI at all and required direct Supabase edits.
class EventsManagerPage extends ConsumerWidget {
  const EventsManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminEventsProvider);
    final items = async.value ?? const <LocalEvent>[];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Events Manager',
          subtitle: 'Local events — the highest-priority tier the '
              'location-aware player shows (EVENT beats Park/Spring/Town/'
              'County when one is happening nearby).',
          actions: [
            FilledButton.icon(
              onPressed: () => _edit(context, ref),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add event'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.md),
        if (async.isLoading)
          const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()))
        else if (items.isEmpty)
          const AdminEmptyState(
              message: 'No events yet. Add one, or run migration 0043 if '
                  'you see a load error.',
              icon: Icons.event_rounded)
        else
          for (final e in items) ...[
            _EventCard(event: e, onEdit: () => _edit(context, ref, event: e)),
            const Gap.v(AppSpacing.sm),
          ],
      ],
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref,
      {LocalEvent? event}) async {
    final saved = await showDialog<bool>(
        context: context, builder: (_) => _EventEditor(event: event));
    if (saved == true) ref.read(eventsRefreshProvider.notifier).bump();
  }
}

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.event, required this.onEdit});
  final LocalEvent event;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final when = [
      if (event.eventDate != null)
        '${event.eventDate!.year}-${event.eventDate!.month.toString().padLeft(2, '0')}-${event.eventDate!.day.toString().padLeft(2, '0')}',
      if ((event.startTime ?? '').isNotEmpty) event.startTime,
    ].whereType<String>().join(' · ');

    return AdminSectionCard(
      child: Row(children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showEventImagePicker(context, event),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (event.imageUrl ?? '').isNotEmpty
                ? Image.network(event.imageUrl!,
                    width: 56, height: 56, fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => _NoPhotoTile(event: event))
                : _NoPhotoTile(event: event),
          ),
        ),
        const Gap.h(AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                  child: Text(event.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              const Gap.h(AppSpacing.sm),
              if (event.active)
                const StatusBadge(BadgeStatus.published, label: 'Active')
              else
                const StatusBadge(BadgeStatus.draft, label: 'Inactive'),
            ]),
            const Gap.v(AppSpacing.xs),
            Text(
              [
                if (when.isNotEmpty) when,
                if ((event.city ?? '').isNotEmpty) event.city,
                if ((event.county ?? '').isNotEmpty) '${event.county} County',
              ].whereType<String>().join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ]),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) async {
            final repo = ref.read(eventRepositoryProvider);
            switch (v) {
              case 'edit':
                onEdit();
              case 'find_photo':
                await showEventImagePicker(context, event);
              case 'toggle':
                await repo.update(event.id, {'active': !event.active});
                ref.read(eventsRefreshProvider.notifier).bump();
              case 'delete':
                await repo.delete(event.id);
                ref.read(eventsRefreshProvider.notifier).bump();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'find_photo', child: Text('Find photo')),
            PopupMenuItem(
                value: 'toggle',
                child: Text(event.active ? 'Set inactive' : 'Set active')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ]),
    );
  }
}

/// The card's photo slot when there is no `image_url` yet — a tappable
/// prompt (not a dead gray box) toward the same Wikimedia/Openverse search
/// the location Media Search Center already uses, per this feature's own
/// "find real images, and if none exist, a clear bright placeholder"
/// direction. The category icon system (shared/design/category_visuals.dart)
/// supplies the bright color/icon once a real search result is saved and
/// shown as a normal image elsewhere in the app.
class _NoPhotoTile extends StatelessWidget {
  const _NoPhotoTile({required this.event});
  final LocalEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Icon(Icons.add_photo_alternate_outlined,
          color: Theme.of(context).colorScheme.primary, size: 22),
    );
  }
}

class _EventEditor extends ConsumerStatefulWidget {
  const _EventEditor({this.event});
  final LocalEvent? event;
  @override
  ConsumerState<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends ConsumerState<_EventEditor> {
  late final _name = TextEditingController(text: widget.event?.name ?? '');
  late final _shortDesc =
      TextEditingController(text: widget.event?.shortDescription ?? '');
  late final _desc =
      TextEditingController(text: widget.event?.description ?? '');
  late final _image = TextEditingController(text: widget.event?.imageUrl ?? '');
  late final _lat =
      TextEditingController(text: widget.event?.latitude?.toString() ?? '');
  late final _lng =
      TextEditingController(text: widget.event?.longitude?.toString() ?? '');
  late final _county = TextEditingController(text: widget.event?.county ?? '');
  late final _city = TextEditingController(text: widget.event?.city ?? '');
  late final _website =
      TextEditingController(text: widget.event?.externalWebsite ?? '');
  late DateTime? _eventDate = widget.event?.eventDate;
  late TimeOfDay? _startTime = _parseTime(widget.event?.startTime);
  late TimeOfDay? _endTime = _parseTime(widget.event?.endTime);
  late bool _active = widget.event?.active ?? true;
  bool _saving = false;

  static TimeOfDay? _parseTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String? _timeToSql(TimeOfDay? t) => t == null
      ? null
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  @override
  void dispose() {
    for (final c in [
      _name,
      _shortDesc,
      _desc,
      _image,
      _lat,
      _lng,
      _county,
      _city,
      _website,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final res =
        await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final url = await ref
          .read(eventRepositoryProvider)
          .uploadImage(res.files.first.bytes!, res.files.first.name);
      setState(() => _image.text = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (start ? _startTime : _endTime) ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => start ? _startTime = picked : _endTime = picked);
    }
  }

  String? _nn(String s) => s.trim().isEmpty ? null : s.trim();

  Map<String, dynamic> _rowMap() => {
        'name': _name.text.trim(),
        'short_description': _nn(_shortDesc.text),
        'description': _nn(_desc.text),
        'image_url': _nn(_image.text),
        'latitude': double.tryParse(_lat.text.trim()),
        'longitude': double.tryParse(_lng.text.trim()),
        'county': _nn(_county.text),
        'city': _nn(_city.text),
        'external_website': _nn(_website.text),
        'event_date': _eventDate == null
            ? null
            : '${_eventDate!.year.toString().padLeft(4, '0')}-'
                '${_eventDate!.month.toString().padLeft(2, '0')}-'
                '${_eventDate!.day.toString().padLeft(2, '0')}',
        'start_time': _timeToSql(_startTime),
        'end_time': _timeToSql(_endTime),
        'active': _active,
      };

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Name is required.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(eventRepositoryProvider);
      if (widget.event == null) {
        await repo.create(_rowMap());
      } else {
        await repo.update(widget.event!.id, _rowMap());
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.event == null ? 'Add event' : 'Edit event'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _f(_name, 'Event name *'),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(child: _f(_image, 'Image URL')),
              const Gap.h(AppSpacing.xs),
              IconButton(
                tooltip: 'Upload',
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.upload_rounded),
              ),
            ]),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickDate,
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(_eventDate == null
                      ? 'Event date'
                      : '${_eventDate!.year}-${_eventDate!.month.toString().padLeft(2, '0')}-${_eventDate!.day.toString().padLeft(2, '0')}'),
                ),
              ),
              const Gap.h(AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _pickTime(true),
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(_startTime?.format(context) ?? 'Start time'),
                ),
              ),
              const Gap.h(AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _pickTime(false),
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(_endTime?.format(context) ?? 'End time'),
                ),
              ),
            ]),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(child: _f(_lat, 'Latitude')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_lng, 'Longitude')),
            ]),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(child: _f(_city, 'City')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_county, 'County')),
            ]),
            const Gap.v(AppSpacing.sm),
            _f(_shortDesc, 'Short description', maxLines: 2),
            const Gap.v(AppSpacing.sm),
            _f(_desc, 'Full description', maxLines: 4),
            const Gap.v(AppSpacing.sm),
            _f(_website, 'External website'),
            const Gap.v(AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Active (visible to travelers)'),
            ),
            if (_saving) ...[
              const Gap.v(AppSpacing.sm),
              const LinearProgressIndicator(),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(widget.event == null ? 'Create' : 'Save')),
      ],
    );
  }

  Widget _f(TextEditingController c, String label, {int maxLines = 1}) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
            labelText: label, isDense: true, border: const OutlineInputBorder()),
      );
}
