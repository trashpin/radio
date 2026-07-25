import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/discovery/models/discovery_category.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/media/data/media_repository.dart';
import 'package:explorer_os_mobile/features/narration/data/narration_repository.dart';
import 'package:explorer_os_mobile/features/narration/services/narration_script_composer.dart';

/// Full species page: hero image, natural-history detail, and narration.
///
/// Narration prefers a linked audio file (`media.species_id`, resolved by
/// [MediaRepository]); when none exists yet it reads the narration text aloud
/// with on-device text-to-speech — so tapping a plant/animal always shows the
/// picture and can speak about it.
class SpeciesDetailScreen extends ConsumerStatefulWidget {
  const SpeciesDetailScreen({
    super.key,
    required this.species,
    required this.category,
    this.autoPlay = false,
  });

  final Species species;
  final DiscoveryCategory category;
  final bool autoPlay;

  @override
  ConsumerState<SpeciesDetailScreen> createState() =>
      _SpeciesDetailScreenState();
}

class _SpeciesDetailScreenState extends ConsumerState<SpeciesDetailScreen> {
  static const Color _bg = Color(0xFF0B120E);
  static const Color _card = Color(0xFF161E19);
  static const Color _accent = Color(0xFFEE7B2E);
  static const Color _textPrimary = Color(0xFFF3F6F2);
  static const Color _textSecondary = Color(0xFF8E9A93);

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _playing = false);
    });
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toggleNarration());
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _player.dispose();
    super.dispose();
  }

  /// Best script to read aloud: a stored, human-edited narration script if one
  /// exists, else a freshly composed tour-guide script from the record's data.
  String _scriptFor(String? storedScript) {
    if (storedScript != null && storedScript.trim().isNotEmpty) {
      return storedScript;
    }
    return const NarrationScriptComposer().composeForSpecies(widget.species);
  }

  Future<void> _toggleNarration() async {
    if (_playing) {
      await _tts.stop();
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      // 1. Prefer a pre-generated narration row (instant, no AI at runtime).
      String? url;
      String? storedScript;
      try {
        final n = await ref
            .read(narrationRepositoryProvider)
            .bestForContent(widget.species.id);
        url = n?.hasAudio ?? false ? n!.audioUrl : null;
        storedScript = n?.script;
      } catch (_) {/* narrations table not present yet — fall back */}
      // 2. Else a linked media audio file.
      url ??= await ref
          .read(mediaRepositoryProvider)
          .narrationUrlForSpecies(widget.species.id);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _playing = true;
      });
      if (url != null) {
        // Prefer a real narration audio file when one has been synced.
        _player.playerStateStream.listen((st) {
          if (st.processingState == ProcessingState.completed && mounted) {
            setState(() => _playing = false);
          }
        });
        await _player.setUrl(url);
        await _player.play();
      } else {
        // Fall back to reading the narration text aloud. Rate/pitch are
        // best-effort (not supported on every platform), so don't let them
        // abort speaking.
        try {
          await _tts.setSpeechRate(0.45);
          await _tts.setPitch(1.0);
        } catch (_) {/* optional tuning */}
        await _tts.speak(_scriptFor(storedScript));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _playing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not play narration: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.species;
    final img = s.heroImageUrl;
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: _bg,
            foregroundColor: Colors.white,
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: img != null && img.isNotEmpty
                  ? Image.network(img, fit: BoxFit.cover)
                  : Container(
                      color: widget.category.color.withValues(alpha: 0.3),
                      child: Icon(widget.category.icon,
                          size: 96, color: widget.category.color)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.commonName,
                      style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800)),
                  if (s.scientificName != null)
                    Text(s.scientificName!,
                        style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 15,
                            fontStyle: FontStyle.italic)),
                  const Gap.v(AppSpacing.lg),
                  _NarrationButton(
                    playing: _playing,
                    loading: _loading,
                    onTap: _toggleNarration,
                  ),
                  const Gap.v(AppSpacing.lg),
                  if (s.description != null && s.description!.isNotEmpty)
                    _section('About', s.description!),
                  if (s.funFacts != null && s.funFacts!.isNotEmpty)
                    _section('Fun facts', s.funFacts!),
                  if (s.diet != null && s.diet!.isNotEmpty)
                    _section('Diet', s.diet!),
                  if (s.behavior != null && s.behavior!.isNotEmpty)
                    _section('Behavior', s.behavior!),
                  if (s.conservationStatus != null &&
                      s.conservationStatus!.isNotEmpty)
                    _section('Conservation', s.conservationStatus!),
                  if (s.safetyInfo != null && s.safetyInfo!.isNotEmpty)
                    _section('Safety', s.safetyInfo!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration:
              BoxDecoration(color: _card, borderRadius: AppRadius.lgAll),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: _accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
              const Gap.v(AppSpacing.sm),
              Text(body,
                  style: const TextStyle(
                      color: _textPrimary, fontSize: 15, height: 1.45)),
            ],
          ),
        ),
      );
}

class _NarrationButton extends StatelessWidget {
  const _NarrationButton(
      {required this.playing, required this.loading, required this.onTap});
  final bool playing;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: loading ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFEE7B2E),
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
      ),
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
      label: Text(playing ? 'Stop narration' : 'Play narration',
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
