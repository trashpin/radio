import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_home/presentation/discover_ask_results_screen.dart';
import 'package:explorer_os_mobile/features/discover_home/services/discover_intent_parser.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';

/// The greeting's natural-language answer box — spec: "the user should be
/// able to answer naturally" via text and, "if the existing audio/voice
/// infrastructure supports it," voice. This app has no speech-to-text
/// package today, so the mic button is present (the spec's own interface
/// requirement) but explains itself rather than silently doing nothing —
/// wiring it up later only means implementing [_startVoiceInput], not
/// rebuilding this widget or the intent pipeline behind it.
class DiscoverAskInput extends ConsumerStatefulWidget {
  const DiscoverAskInput({super.key});

  @override
  ConsumerState<DiscoverAskInput> createState() => _DiscoverAskInputState();
}

class _DiscoverAskInputState extends ConsumerState<DiscoverAskInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final intent = ref.read(discoverIntentParserProvider).parse(text);
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiscoverAskResultsScreen(query: text, intent: intent),
      ),
    );
    _controller.clear();
  }

  void _startVoiceInput() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice answers are coming soon — type it in for now.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: RD.sm, vertical: 2),
      decoration: BoxDecoration(
        color: RD.panel,
        borderRadius: BorderRadius.circular(RD.rPill),
        border: Border.all(color: RD.stroke),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.mic_none_rounded, color: RD.textSecondary),
            tooltip: 'Answer with your voice',
            onPressed: _startVoiceInput,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              style: RD.body.copyWith(color: RD.textPrimary),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Tell me what you\'re in the mood for…',
                hintStyle: TextStyle(color: RD.textFaint),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded, color: RD.green),
            tooltip: 'Send',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
