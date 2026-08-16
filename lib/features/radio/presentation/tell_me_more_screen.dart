import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';
import 'package:explorer_os_mobile/features/radio/services/tell_me_more_mapping.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// "Tell Me More" — a temporary excursion away from the radio, not a second
/// player. The listener taps TELL ME MORE on the Radio screen with whatever
/// [tellMeMoreContext] the current player card was showing (event/park/
/// spring/town/county, or a DJ-banter tease — see [TellMeMoreContext]),
/// lands here on a photo + history + practical-info page
/// ([tellMeMoreResultProvider] routes to the right content source), and
/// presses Back to return to the radio exactly where they left off: this
/// screen pauses playback on the way in and resumes it (only if it was
/// actually playing before) on the way out.
class TellMeMoreScreen extends ConsumerStatefulWidget {
  const TellMeMoreScreen({super.key, this.tellMeMoreContext});

  final TellMeMoreContext? tellMeMoreContext;

  @override
  ConsumerState<TellMeMoreScreen> createState() => _TellMeMoreScreenState();
}

class _TellMeMoreScreenState extends ConsumerState<TellMeMoreScreen> {
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    // Capture + pause exactly once, before anything else can change the
    // engine's state — the existing Play/Pause toggle's own pause(), so
    // resuming later is the same tested "no restart" behavior.
    final controller = ref.read(radioEngineControllerProvider.notifier);
    _wasPlaying =
        ref.read(radioEngineControllerProvider).status == PlaybackStatus.playing;
    if (_wasPlaying) controller.pause();
  }

  @override
  void dispose() {
    // Back (system gesture, AppBar arrow, or any other pop) always runs
    // this — restore the exact prior state, never a random resume.
    if (_wasPlaying) {
      ref.read(radioEngineControllerProvider.notifier).play();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.tellMeMoreContext;
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const RadioSubPageBar(
                  title: 'Tell Me More',
                  subtitle: 'An interactive extension of the radio.',
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RD.lg),
                    child: ctx == null || !ctx.hasContext
                        ? const _NoContext()
                        : _ResultLookup(ctx: ctx),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultLookup extends ConsumerWidget {
  const _ResultLookup({required this.ctx});

  final TellMeMoreContext ctx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tellMeMoreResultProvider(ctx));
    return async.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: RD.green)),
      error: (_, _) => _Fallback(ctx: ctx),
      data: (result) => result == null || (result.history ?? '').trim().isEmpty
          ? _Fallback(ctx: ctx)
          : _InfoPage(result: result),
    );
  }
}

/// The full information page — photo, history, and whichever practical
/// fields the source record actually has. Sections with no data simply
/// don't render; nothing here is ever invented.
class _InfoPage extends StatelessWidget {
  const _InfoPage({required this.result});

  final TellMeMoreResult result;

  Future<void> _navigate(BuildContext context) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${result.latitude},${result.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWebsite(BuildContext context) async {
    final uri = Uri.tryParse(result.website ?? '');
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      ?result.locationLabel,
      ?result.eventDateLabel,
      ?result.eventTimeLabel,
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: RD.lg),
          if ((result.imageUrl ?? '').isNotEmpty)
            _Photo(imageUrl: result.imageUrl!)
          else
            const Center(child: _Badge(icon: Icons.auto_stories_rounded)),
          const SizedBox(height: RD.lg),
          Text(
            result.title,
            textAlign: TextAlign.center,
            style: RD.title.copyWith(fontSize: 20),
          ),
          if (subtitleParts.isNotEmpty) ...[
            const SizedBox(height: RD.xs),
            Text(
              subtitleParts.join(' · '),
              textAlign: TextAlign.center,
              style: RD.caption.copyWith(color: RD.green),
            ),
          ],
          const SizedBox(height: RD.lg),
          GlassPanel(
            child: Text(
              result.history ?? '',
              style: RD.body.copyWith(height: 1.5),
            ),
          ),
          if (result.hours != null || result.admission != null) ...[
            const SizedBox(height: RD.md),
            _FactRow(
              icon: Icons.schedule_rounded,
              label: 'Hours',
              value: result.hours,
            ),
            _FactRow(
              icon: Icons.local_activity_rounded,
              label: 'Admission',
              value: result.admission,
            ),
          ],
          if (result.activities.isNotEmpty) ...[
            const SizedBox(height: RD.lg),
            const _SectionLabel('Highlights'),
            const SizedBox(height: RD.sm),
            _ChipWrap(items: result.activities),
          ],
          if (result.goodToKnow.isNotEmpty) ...[
            const SizedBox(height: RD.lg),
            const _SectionLabel('Good to know'),
            const SizedBox(height: RD.sm),
            ...result.goodToKnow.map((g) => _BulletLine(text: g)),
          ],
          if (result.canNavigate || result.hasWebsite) ...[
            const SizedBox(height: RD.lg),
            Row(
              children: [
                if (result.canNavigate)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _navigate(context),
                      icon: const Icon(Icons.directions_rounded, color: RD.green),
                      label: const Text('Navigate',
                          style: TextStyle(color: RD.green)),
                    ),
                  ),
                if (result.canNavigate && result.hasWebsite)
                  const SizedBox(width: RD.sm),
                if (result.hasWebsite)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openWebsite(context),
                      icon: const Icon(Icons.open_in_new_rounded, color: RD.green),
                      label: const Text('More info',
                          style: TextStyle(color: RD.green)),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: RD.lg),
        ],
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: RD.brXl,
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const Center(child: _Badge(icon: Icons.auto_stories_rounded)),
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.label, this.value});
  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if ((value ?? '').trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: RD.green, size: 18),
          const SizedBox(width: RD.sm),
          Text('$label: ', style: RD.caption.copyWith(color: RD.textSecondary)),
          Expanded(child: Text(value!, style: RD.body)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: RD.sectionLabel);
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: RD.sm,
      runSpacing: RD.sm,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: RD.md, vertical: 6),
            decoration: BoxDecoration(
              color: RD.panel,
              borderRadius: BorderRadius.circular(RD.rPill),
              border: Border.all(color: RD.stroke),
            ),
            child: Text(item, style: RD.caption.copyWith(color: RD.textPrimary)),
          ),
      ],
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(color: RD.green)),
          Expanded(child: Text(text, style: RD.body)),
        ],
      ),
    );
  }
}

/// No published/complete story fits this moment yet — fall back to whatever
/// short teaser was already on the player card.
class _Fallback extends StatelessWidget {
  const _Fallback({required this.ctx});

  final TellMeMoreContext ctx;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _Badge(icon: Icons.auto_stories_rounded),
        const SizedBox(height: RD.lg),
        Text(
          ctx.subject ?? 'More on the way',
          textAlign: TextAlign.center,
          style: RD.title.copyWith(fontSize: 20),
        ),
        const SizedBox(height: RD.sm),
        Text(
          "We know what's on the radio right now — the full story isn't "
          "recorded here yet.",
          textAlign: TextAlign.center,
          style: RD.body,
        ),
        if ((ctx.banterText ?? '').isNotEmpty) ...[
          const SizedBox(height: RD.lg),
          GlassPanel(
            child: Text(
              '"${ctx.banterText}"',
              textAlign: TextAlign.center,
              style: RD.body.copyWith(
                fontStyle: FontStyle.italic,
                color: RD.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NoContext extends StatelessWidget {
  const _NoContext();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Badge(icon: Icons.auto_stories_rounded),
        SizedBox(height: RD.lg),
        Text(
          'Coming soon',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, height: 1.2, fontWeight: FontWeight.w700, color: RD.textPrimary),
        ),
        SizedBox(height: RD.sm),
        Text(
          "Tap TELL ME MORE while the radio is showing something to dig "
          "deeper into what it's about.",
          textAlign: TextAlign.center,
          style: RD.body,
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: RD.green.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: RD.green.withValues(alpha: 0.6)),
      ),
      child: Icon(icon, color: RD.green, size: 40),
    );
  }
}
