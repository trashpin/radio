import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_audio_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/models/discovery_category.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/presentation/forest_discovery_map_screen.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/services/forest_discovery_ai_service.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/services/forest_discovery_submit_service.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/widgets/forest_audio_bar.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// 🎉 DISCOVERY SAVED (spec §6/§7) — renders from what the capture flow
/// already collected in memory rather than re-reading the row back (the
/// base table has no anon/authenticated SELECT policy by design, see
/// migration 0051).
class ForestDiscoverySavedScreen extends ConsumerStatefulWidget {
  const ForestDiscoverySavedScreen({
    super.key,
    required this.discoveryId,
    required this.displayName,
    required this.group,
    required this.photoBytes,
    required this.observedAt,
    required this.category,
    this.aiIdentification,
    this.aiScientificName,
    this.aiExplanation,
    this.userNotes,
  });

  final String discoveryId;
  final String displayName;
  final DiscoveryGroup group;
  final Uint8List photoBytes;
  final DateTime observedAt;
  final String category;
  final String? aiIdentification;
  final String? aiScientificName;
  final String? aiExplanation;
  final String? userNotes;

  @override
  ConsumerState<ForestDiscoverySavedScreen> createState() => _ForestDiscoverySavedScreenState();
}

class _ForestDiscoverySavedScreenState extends ConsumerState<ForestDiscoverySavedScreen> {
  bool _narrating = false;
  String? _narrationText;
  String? _narrationError;

  Future<void> _tellMeAboutIt() async {
    setState(() {
      _narrating = true;
      _narrationError = null;
    });
    final ai = ref.read(forestDiscoveryAiServiceProvider);
    final result = await ai.narrate(
      identification: widget.displayName == 'Unidentified discovery' ? null : widget.displayName,
      scientificName: widget.aiScientificName,
      category: widget.category,
      aiExplanation: widget.aiExplanation,
      userNotes: widget.userNotes,
    );
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _narrating = false;
        _narrationError = "Couldn't generate that right now — try again in a moment.";
      });
      return;
    }
    setState(() {
      _narrating = false;
      _narrationText = result.text;
    });

    // Plays through the dedicated ForestAudioController — never the shared
    // Radio Engine (which would auto-fill silence with music once this
    // one-shot narration finished; see that controller's doc comment).
    await ref.read(forestAudioControllerProvider.notifier).play(
          title: widget.displayName,
          audioUrl: result.hasAudio ? result.audioUrl : null,
          spokenText: result.hasAudio ? null : result.text,
        );
  }

  Future<void> _addNote() async {
    final controller = TextEditingController(text: widget.userNotes ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: RD.panel,
        title: const Text('Add a note', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (note == null || !mounted) return;
    final ok = await ref
        .read(forestDiscoverySubmitServiceProvider)
        .addNote(widget.discoveryId, note);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Note saved.' : "Couldn't save the note — try again."),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(RD.lg),
          children: [
            const SizedBox(height: RD.lg),
            const Center(child: Text('🎉', style: TextStyle(fontSize: 48))),
            const SizedBox(height: RD.sm),
            Text('DISCOVERY SAVED',
                textAlign: TextAlign.center, style: RD.title.copyWith(color: Colors.white)),
            const SizedBox(height: RD.lg),
            ClipRRect(
              borderRadius: RD.brLg,
              child: Image.memory(widget.photoBytes,
                  height: 220, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: RD.md),
            Text(widget.displayName,
                textAlign: TextAlign.center, style: RD.title.copyWith(color: Colors.white)),
            const SizedBox(height: RD.xs),
            Text('${widget.group.emoji} ${widget.group.label}',
                textAlign: TextAlign.center, style: RD.body),
            Text('📍 Ocala National Forest', textAlign: TextAlign.center, style: RD.body),
            Text(_formattedDate(widget.observedAt),
                textAlign: TextAlign.center, style: RD.body),
            const SizedBox(height: RD.lg),
            if (_narrationText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: RD.lg),
                child: GlassPanel(child: Text(_narrationText!, style: RD.body)),
              ),
            if (_narrationError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: RD.sm),
                child: Text(_narrationError!, style: RD.body.copyWith(color: RD.live)),
              ),
            ElevatedButton.icon(
              onPressed: _narrating ? null : _tellMeAboutIt,
              icon: _narrating
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.volume_up_rounded),
              label: const Text('TELL ME ABOUT IT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: RD.green,
                foregroundColor: RD.onGreen,
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
            const SizedBox(height: RD.sm),
            const ForestAudioBar(),
            const SizedBox(height: RD.sm),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ForestDiscoveryMapScreen())),
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              child: const Text('VIEW ON MAP', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: RD.sm),
            OutlinedButton(
              onPressed: _addNote,
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              child: const Text('ADD A NOTE', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: RD.sm),
            TextButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('DONE'),
            ),
          ],
        ),
      ),
    );
  }

  String _formattedDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '📅 ${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
