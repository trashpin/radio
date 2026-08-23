import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_home/models/discover_interest.dart';
import 'package:explorer_os_mobile/features/discover_home/providers/discover_interests_provider.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// Multi-select interest picker — "select interests such as Outdoors,
/// Springs & Water, Hiking & Trails, …". Reachable from a first-run prompt
/// on Discover's home screen and any time after via its header.
class DiscoverInterestsScreen extends ConsumerStatefulWidget {
  const DiscoverInterestsScreen({super.key});

  @override
  ConsumerState<DiscoverInterestsScreen> createState() => _DiscoverInterestsScreenState();
}

class _DiscoverInterestsScreenState extends ConsumerState<DiscoverInterestsScreen> {
  late Set<String> _selected;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(discoverInterestsProvider);
    if (!_initialized) {
      _selected = {...saved};
      _initialized = true;
    }

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(
              title: 'What are you into?',
              subtitle: 'Pick as many as you like — you can change these any time.',
            ),
            Expanded(
              child: GridView.count(
                padding: const EdgeInsets.fromLTRB(RD.lg, 0, RD.lg, RD.xl),
                crossAxisCount: 2,
                childAspectRatio: 2.6,
                mainAxisSpacing: RD.sm,
                crossAxisSpacing: RD.sm,
                children: [
                  for (final interest in discoverInterests)
                    _InterestChip(
                      interest: interest,
                      selected: _selected.contains(interest.token),
                      onTap: () => setState(() {
                        if (!_selected.remove(interest.token)) {
                          _selected.add(interest.token);
                        }
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(RD.lg, 0, RD.lg, RD.lg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await ref.read(discoverInterestsProvider.notifier).setInterests(_selected);
                    if (context.mounted) Navigator.of(context).maybePop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: RD.green,
                    foregroundColor: RD.onGreen,
                    minimumSize: const Size(0, 52),
                  ),
                  child: Text(_selected.isEmpty ? 'Skip for now' : 'Save my interests'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InterestChip extends StatelessWidget {
  const _InterestChip({required this.interest, required this.selected, required this.onTap});
  final DiscoverInterest interest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? RD.green.withValues(alpha: 0.18) : RD.panel,
      borderRadius: BorderRadius.circular(RD.rMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(RD.rMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: RD.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RD.rMd),
            border: Border.all(color: selected ? RD.green : RD.stroke),
          ),
          child: Row(children: [
            Icon(interest.icon, size: 20, color: selected ? RD.green : RD.textSecondary),
            const SizedBox(width: RD.sm),
            Expanded(
              child: Text(interest.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RD.body.copyWith(
                      color: selected ? RD.textPrimary : RD.textSecondary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
            ),
            if (selected) const Icon(Icons.check_circle_rounded, color: RD.green, size: 18),
          ]),
        ),
      ),
    );
  }
}
