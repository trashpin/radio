import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/events/event_notification_repository.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/events/data/event_repository.dart';

final _testUsersProvider = FutureProvider<List<TestUserOption>>(
  (ref) => ref.watch(eventNotificationRepositoryProvider).listTestUsers(),
);
final _recentMatchesProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => ref.watch(eventNotificationRepositoryProvider).recentMatches(),
);

/// Admin -> Event Notifications: the required test mode (spec: "I should be
/// able to select Event + Test User and run Event -> Match -> Personalized
/// Script -> ElevenLabs Audio -> Push Notification Payload -> Deep Link
/// without sending anything to the general user population"). No real push
/// is ever sent from here or anywhere else in this app yet — see this
/// screen's own note in the result panel.
class EventNotificationTestPage extends ConsumerStatefulWidget {
  const EventNotificationTestPage({super.key});

  @override
  ConsumerState<EventNotificationTestPage> createState() => _EventNotificationTestPageState();
}

class _EventNotificationTestPageState extends ConsumerState<EventNotificationTestPage> {
  String? _eventId;
  String? _userId;
  bool _running = false;
  Map<String, dynamic>? _result;
  String? _error;

  Future<void> _runTest() async {
    if (_eventId == null || _userId == null) return;
    setState(() {
      _running = true;
      _result = null;
      _error = null;
    });
    try {
      final result =
          await ref.read(eventNotificationRepositoryProvider).runTest(_eventId!, _userId!);
      setState(() => _result = result);
      ref.invalidate(_recentMatchesProvider);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(adminEventsProvider);
    final usersAsync = ref.watch(_testUsersProvider);
    final matchesAsync = ref.watch(_recentMatchesProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Event Notification Test Mode',
          subtitle: 'Event -> Match -> Personalized Script -> ElevenLabs Audio -> '
              'Notification Payload -> Deep Link, for one chosen user. Never sends a '
              'real push — there is no push channel configured in this project yet.',
        ),
        const Gap.v(AppSpacing.xl),
        AdminSectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            eventsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Could not load events: $e'),
              data: (events) => DropdownButtonFormField<String>(
                initialValue: _eventId,
                decoration: const InputDecoration(labelText: 'Event'),
                items: [
                  for (final e in events)
                    DropdownMenuItem(value: e.id, child: Text(e.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _eventId = v),
              ),
            ),
            const Gap.v(AppSpacing.md),
            usersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Could not load test users: $e'),
              data: (users) => users.isEmpty
                  ? const Text('No users have selected any Discover interests yet.')
                  : DropdownButtonFormField<String>(
                      initialValue: _userId,
                      decoration: const InputDecoration(labelText: 'Test User'),
                      items: [
                        for (final u in users)
                          DropdownMenuItem(
                            value: u.id,
                            child: Text('${u.label} (${u.interests.length} interests)'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _userId = v),
                    ),
            ),
            const Gap.v(AppSpacing.lg),
            FilledButton.icon(
              onPressed: (_eventId != null && _userId != null && !_running) ? _runTest : null,
              icon: _running
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_running ? 'Running…' : 'Run Test'),
            ),
          ]),
        ),
        if (_error != null) ...[
          const Gap.v(AppSpacing.md),
          AdminSectionCard(child: Text('Error: $_error')),
        ],
        if (_result != null) ...[
          const Gap.v(AppSpacing.lg),
          _ResultPanel(result: _result!),
        ],
        const Gap.v(AppSpacing.xl),
        Text('Recent Matches', style: Theme.of(context).textTheme.titleMedium),
        const Gap.v(AppSpacing.md),
        matchesAsync.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => AdminEmptyState(message: 'Could not load matches: $e'),
          data: (rows) => rows.isEmpty
              ? const AdminEmptyState(message: 'No matches recorded yet.', icon: Icons.insights_rounded)
              : Column(children: [
                  for (final row in rows) ...[
                    _MatchRow(row: row),
                    const Gap.v(AppSpacing.xs),
                  ],
                ]),
        ),
      ],
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final match = (result['match'] as Map?)?.cast<String, dynamic>();
    final notification = (result['notification'] as Map?)?.cast<String, dynamic>();
    final narration = (result['narration'] as Map?)?.cast<String, dynamic>();
    final deepLink = result['deepLink'] as String?;
    final audioUrl = narration?['audioUrl'] as String?;

    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.science_rounded, size: 18),
          const SizedBox(width: 8),
          Text(result['note'] as String? ?? 'TEST MODE — no push notification was sent.',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const Gap.v(AppSpacing.md),
        if (match != null) ...[
          StatusBadge(
            switch (match['tier']) {
              'high' => BadgeStatus.published,
              'medium' => BadgeStatus.review,
              _ => BadgeStatus.draft,
            },
            label: '${(match['tier'] as String).toUpperCase()} MATCH '
                '(score ${(match['score'] as num).toStringAsFixed(2)})',
          ),
          const Gap.v(AppSpacing.xs),
          Text('Matched interests: ${(match['matched'] as List).join(', ')}'),
        ],
        if (notification != null) ...[
          const Gap.v(AppSpacing.md),
          Text('Notification', style: Theme.of(context).textTheme.labelLarge),
          Text('${notification['title']}\n${notification['body']}'),
        ],
        if (narration != null && (narration['text'] as String?)?.isNotEmpty == true) ...[
          const Gap.v(AppSpacing.md),
          Text('Personalized script', style: Theme.of(context).textTheme.labelLarge),
          Text(narration['text'] as String),
          if (audioUrl != null) ...[
            const Gap.v(AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse(audioUrl), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.headphones_rounded),
              label: const Text('Play generated audio'),
            ),
          ],
        ],
        if (deepLink != null) ...[
          const Gap.v(AppSpacing.md),
          Text('Deep link: $deepLink', style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final tier = row['match_tier'] as String? ?? '?';
    final status = row['status'] as String? ?? '?';
    return AdminSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(children: [
        StatusBadge(
          switch (tier) {
            'high' => BadgeStatus.published,
            'medium' => BadgeStatus.review,
            _ => BadgeStatus.draft,
          },
          label: tier.toUpperCase(),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text('event ${row['event_id']} · user ${row['user_id']} · $status',
              overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
    );
  }
}
