import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/narration/models/destination_narration.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';
import 'package:explorer_os_mobile/features/radio/services/tell_me_more_mapping.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// "Tell Me More" — the listener taps TELL ME MORE on the Radio screen and
/// lands here with the [tellMeMoreContext] the engine already captured about
/// what the DJ was just talking about (see [TellMeMoreContext]). This screen
/// looks up the best published narration for that destination + moment
/// ([tellMeMoreNarrationProvider]) and shows the full script; when nothing
/// published fits yet, it falls back to the DJ's one-liner.
class TellMeMoreScreen extends ConsumerWidget {
  const TellMeMoreScreen({super.key, this.tellMeMoreContext});

  final TellMeMoreContext? tellMeMoreContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = tellMeMoreContext;
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
                        : _NarrationLookup(ctx: ctx),
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

class _NarrationLookup extends ConsumerWidget {
  const _NarrationLookup({required this.ctx});

  final TellMeMoreContext ctx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tellMeMoreNarrationProvider(ctx));
    return async.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: RD.green)),
      error: (_, _) => _Fallback(ctx: ctx),
      data: (narration) =>
          narration == null ? _Fallback(ctx: ctx) : _FullStory(narration: narration),
    );
  }
}

/// A published narration exists — show the full script.
class _FullStory extends StatelessWidget {
  const _FullStory({required this.narration});

  final DestinationNarration narration;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: RD.lg),
          _Badge(icon: Icons.auto_stories_rounded),
          const SizedBox(height: RD.lg),
          Text(
            narration.title ?? narration.type?.label ?? 'The full story',
            textAlign: TextAlign.center,
            style: RD.title.copyWith(fontSize: 20),
          ),
          const SizedBox(height: RD.lg),
          GlassPanel(
            child: Text(
              narration.script ?? '',
              style: RD.body.copyWith(height: 1.5),
            ),
          ),
          const SizedBox(height: RD.lg),
        ],
      ),
    );
  }
}

/// No published narration fits this moment yet — fall back to the DJ's line.
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
          "We know what the DJ was just talking about — the full story "
          "isn't recorded here yet.",
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
          "Tap TELL ME MORE while the DJ is on air to dig deeper into "
          "what they're talking about.",
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
