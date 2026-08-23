import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/models/discovery_category.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/presentation/forest_discovery_saved_screen.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/services/forest_discovery_ai_service.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/services/forest_discovery_submit_service.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/services/nearest_trail_finder.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/ocala_forest_providers.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

enum _Step { subtype, photo, identifying, suggestion, notes, saving }

/// The core DISCOVER flow (spec §3–§6): pick a subtype (if the group has
/// any) → take/pick a photo → AI suggests an identification (never a fact,
/// spec §4) → the visitor accepts/edits/rejects it → optional notes → save
/// with GPS + date/time captured via the EXISTING GPS system.
class ForestDiscoverCaptureScreen extends ConsumerStatefulWidget {
  const ForestDiscoverCaptureScreen({super.key, required this.group});
  final DiscoveryGroup group;

  @override
  ConsumerState<ForestDiscoverCaptureScreen> createState() =>
      _ForestDiscoverCaptureScreenState();
}

class _ForestDiscoverCaptureScreenState extends ConsumerState<ForestDiscoverCaptureScreen> {
  late _Step _step = widget.group.subtypes.isEmpty ? _Step.photo : _Step.subtype;
  String? _subtype;
  Uint8List? _photoBytes;
  String _mimeType = 'image/jpeg';
  DiscoveryIdentification? _aiResult;
  String? _confirmedIdentification;
  String _userConfirmation = 'unknown';
  final _notesController = TextEditingController();
  final _editController = TextEditingController();
  bool _editing = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    _editController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() => _error = null);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, imageQuality: 85, maxWidth: 1600);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final mime = file.mimeType ??
          (file.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      setState(() {
        _photoBytes = bytes;
        _mimeType = mime;
        _step = _Step.identifying;
      });
      await _runIdentify();
    } catch (e) {
      setState(() => _error = "Couldn't access the camera/photos: $e");
    }
  }

  Future<void> _runIdentify() async {
    final bytes = _photoBytes;
    if (bytes == null) return;
    final ai = ref.read(forestDiscoveryAiServiceProvider);
    final result = await ai.identify(
      imageBase64: base64Encode(bytes),
      mimeType: _mimeType,
      category: widget.group.id,
      subtype: _subtype,
    );
    if (!mounted) return;
    setState(() {
      _aiResult = result;
      _step = _Step.suggestion;
    });
  }

  Future<void> _save() async {
    final bytes = _photoBytes;
    if (bytes == null) return;
    final fix = ref.read(gpsControllerProvider).location;
    if (fix == null) {
      setState(() => _error = 'Waiting for a GPS fix — try again in a moment.');
      return;
    }
    setState(() {
      _step = _Step.saving;
      _error = null;
    });
    final forest = ref.read(ocalaForestBoundaryProvider).value;
    final trails = ref.read(forestTrailsProvider).value ?? const <ForestTrail>[];
    final trailId = nearestTrailId(fix.latitude, fix.longitude, trails);
    final submitService = ref.read(forestDiscoverySubmitServiceProvider);
    final id = await submitService.submit(DiscoverySubmission(
      photoBytes: bytes,
      mimeType: _mimeType,
      category: widget.group.id,
      subtype: _subtype,
      identification: _confirmedIdentification,
      scientificName: _userConfirmation == 'accepted' ? _aiResult?.scientificName : null,
      userConfirmation: _userConfirmation,
      latitude: fix.latitude,
      longitude: fix.longitude,
      forestId: forest?.id,
      trailId: trailId,
      userNotes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      aiIdentification: _aiResult?.identification,
      aiScientificName: _aiResult?.scientificName,
      aiConfidence: _aiResult?.confidence,
      aiExplanation: _aiResult?.explanation,
      aiCaveats: _aiResult?.caveats,
    ));
    if (!mounted) return;
    if (id == null) {
      setState(() {
        _step = _Step.notes;
        _error = "Couldn't save this discovery — check your connection and try again.";
      });
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ForestDiscoverySavedScreen(
        discoveryId: id,
        displayName: (_confirmedIdentification?.trim().isNotEmpty ?? false)
            ? _confirmedIdentification!.trim()
            : 'Unidentified discovery',
        group: widget.group,
        photoBytes: bytes,
        observedAt: DateTime.now(),
        aiIdentification: _aiResult?.identification,
        aiScientificName: _aiResult?.scientificName,
        category: widget.group.id,
        aiExplanation: _aiResult?.explanation,
        userNotes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            RadioSubPageBar(title: '${widget.group.emoji} ${widget.group.label}'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: RD.lg),
                child: Text(_error!, style: RD.body.copyWith(color: RD.live)),
              ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case _Step.subtype:
        return _subtypeStep();
      case _Step.photo:
        return _photoStep();
      case _Step.identifying:
        return const Center(child: CircularProgressIndicator());
      case _Step.suggestion:
        return _suggestionStep();
      case _Step.notes:
        return _notesStep();
      case _Step.saving:
        return const Center(child: CircularProgressIndicator());
    }
  }

  Widget _subtypeStep() {
    return ListView(
      padding: const EdgeInsets.all(RD.lg),
      children: [
        Text('What did you find?', style: RD.title.copyWith(color: Colors.white)),
        const SizedBox(height: RD.md),
        for (final s in widget.group.subtypes) ...[
          GlassPanel(
            onTap: () => setState(() {
              _subtype = s;
              _step = _Step.photo;
            }),
            child: Row(
              children: [
                Expanded(child: Text(s, style: RD.cardTitle.copyWith(color: Colors.white))),
                const Icon(Icons.chevron_right_rounded, color: RD.textFaint),
              ],
            ),
          ),
          const SizedBox(height: RD.sm),
        ],
      ],
    );
  }

  Widget _photoStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_rounded, size: 56, color: RD.green),
            const SizedBox(height: RD.lg),
            Text(
              'Take a picture of what you discovered.',
              textAlign: TextAlign.center,
              style: RD.title.copyWith(color: Colors.white),
            ),
            const SizedBox(height: RD.xl),
            ElevatedButton.icon(
              onPressed: () => _pickPhoto(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Take Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: RD.green,
                foregroundColor: RD.onGreen,
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
            const SizedBox(height: RD.sm),
            OutlinedButton.icon(
              onPressed: () => _pickPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, color: Colors.white),
              label: const Text('Choose From Gallery', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionStep() {
    final ai = _aiResult;
    return ListView(
      padding: const EdgeInsets.all(RD.lg),
      children: [
        if (_photoBytes != null)
          ClipRRect(
            borderRadius: RD.brLg,
            child: Image.memory(_photoBytes!, height: 220, width: double.infinity, fit: BoxFit.cover),
          ),
        const SizedBox(height: RD.lg),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ai == null || !ai.hasSuggestion) ...[
                Text("I'm not able to identify this one.",
                    style: RD.cardTitle.copyWith(color: Colors.white)),
                if ((ai?.caveats ?? '').isNotEmpty) ...[
                  const SizedBox(height: RD.xs),
                  Text(ai!.caveats, style: RD.body),
                ],
              ] else ...[
                Text('I think you discovered a ${ai.identification}.',
                    style: RD.cardTitle.copyWith(color: Colors.white)),
                const SizedBox(height: RD.xs),
                Text('Confidence: ${_confidenceLabel(ai.confidence)}',
                    style: RD.caption.copyWith(color: RD.green)),
                if (ai.explanation.isNotEmpty) ...[
                  const SizedBox(height: RD.sm),
                  Text(ai.explanation, style: RD.body),
                ],
                if (ai.caveats.isNotEmpty) ...[
                  const SizedBox(height: RD.sm),
                  Text(ai.caveats, style: RD.caption.copyWith(color: RD.amber)),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: RD.lg),
        if (!_editing) ...[
          if (ai?.hasSuggestion ?? false)
            ElevatedButton(
              onPressed: () => setState(() {
                _confirmedIdentification = ai!.identification;
                _userConfirmation = 'accepted';
                _step = _Step.notes;
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: RD.green,
                foregroundColor: RD.onGreen,
                minimumSize: const Size(double.infinity, 52),
              ),
              child: const Text("YES, THAT'S IT"),
            ),
          const SizedBox(height: RD.sm),
          OutlinedButton(
            onPressed: () => setState(() => _editing = true),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            child: const Text('SELECT ANOTHER IDENTIFICATION',
                style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: RD.sm),
          OutlinedButton(
            onPressed: () => setState(() {
              _confirmedIdentification = null;
              _userConfirmation = 'unknown';
              _step = _Step.notes;
            }),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            child: const Text('NOT SURE / SUBMIT AS UNKNOWN',
                style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: RD.sm),
          TextButton(
            onPressed: () => setState(() {
              _photoBytes = null;
              _aiResult = null;
              _step = _Step.photo;
            }),
            child: const Text('TRY ANOTHER PHOTO'),
          ),
        ] else ...[
          TextField(
            controller: _editController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'What is it?',
              labelStyle: TextStyle(color: RD.textSecondary),
            ),
          ),
          const SizedBox(height: RD.sm),
          ElevatedButton(
            onPressed: _editController.text.trim().isEmpty
                ? null
                : () => setState(() {
                      _confirmedIdentification = _editController.text.trim();
                      _userConfirmation = 'edited';
                      _step = _Step.notes;
                    }),
            style: ElevatedButton.styleFrom(
              backgroundColor: RD.green,
              foregroundColor: RD.onGreen,
              minimumSize: const Size(double.infinity, 52),
            ),
            child: const Text('CONTINUE'),
          ),
        ],
      ],
    );
  }

  String _confidenceLabel(String c) {
    switch (c) {
      case 'high':
        return 'High';
      case 'medium':
        return 'Medium';
      default:
        return 'Low';
    }
  }

  Widget _notesStep() {
    return ListView(
      padding: const EdgeInsets.all(RD.lg),
      children: [
        Text('Add a note? (optional)', style: RD.title.copyWith(color: Colors.white)),
        const SizedBox(height: RD.md),
        TextField(
          controller: _notesController,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Anything you want to remember about this discovery…',
            hintStyle: TextStyle(color: RD.textFaint),
          ),
        ),
        const SizedBox(height: RD.lg),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: RD.green,
            foregroundColor: RD.onGreen,
            minimumSize: const Size(double.infinity, 52),
          ),
          child: const Text('SAVE DISCOVERY'),
        ),
      ],
    );
  }
}
