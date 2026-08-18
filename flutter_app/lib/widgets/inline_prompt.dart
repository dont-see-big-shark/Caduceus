import 'package:flutter/material.dart';
import 'package:agent_core/agent_core.dart';

import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// A question the agent is blocked on, rendered where it was asked.
///
/// Previously a banner above the transcript. That position could not say
/// which exchange the question belonged to once more than one turn was on
/// screen, and it pushed the conversation down rather than being part of it.
class InlinePrompt extends StatefulWidget {
  const InlinePrompt({
    required this.prompt,
    required this.onAnswer,
    this.onStop,
    super.key,
  });

  final AgentPrompt prompt;

  /// Null once the question is no longer answerable.
  final Future<bool> Function(String)? onAnswer;

  /// Abandons the turn instead of answering.
  ///
  /// A blocked agent is *only* released by an answer or `session.interrupt` —
  /// the server says so in as many words — so a question you do not want to
  /// answer is a dead end without this. The header has an interrupt button,
  /// but the user is looking here, and on a phone that button is one small
  /// icon in a crowded row.
  final VoidCallback? onStop;

  @override
  State<InlinePrompt> createState() => InlinePromptState();
}

class InlinePromptState extends State<InlinePrompt> {
  final _answer = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _answer.clear();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _submit([String? value]) async {
    final text = value ?? _answer.text;
    if (text.isEmpty) return;
    final answer = widget.onAnswer;
    if (answer == null) return;
    setState(() => _sending = true);
    await answer(text);
    _answer.clear();
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = widget.prompt;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Palette.azure.withValues(alpha: .06),
        borderRadius: Radii.mediumAll,
        border: Border.all(color: Palette.azure.withValues(alpha: .4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: Palette.azure),
              const SizedBox(width: 6),
              Text(
                switch (prompt.kind) {
                  AgentPromptKind.password => 'The agent needs a sudo password',
                  AgentPromptKind.secret =>
                    'The agent needs a secret${prompt.envVar.isEmpty ? '' : ' (${prompt.envVar})'}',
                  AgentPromptKind.approval => 'The agent wants permission',
                  AgentPromptKind.clarify => 'The agent is asking',
                },
                style: mono(
                  context,
                  size: 12,
                ).copyWith(color: Palette.azure, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              const StatusDot(color: Palette.jade),
            ],
          ),
          const SizedBox(height: 8),
          if (prompt.question.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(prompt.question),
          ],
          if (prompt.isSecret) ...[
            const SizedBox(height: 6),
            Text(
              'Sent straight to your server and stored there. Caduceus does not '
              'keep it, and it never appears in the transcript.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          if (widget.onStop != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _sending ? null : widget.onStop,
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                label: const Text("Don't answer — stop this turn"),
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (prompt.choices.isNotEmpty && prompt.multiSelect)
            // The server sends multi_select specifically for renderers that
            // can do better than a text box; asking someone to retype the
            // options comma-separated when they are already on screen is the
            // fallback, not the feature.
            _MultiSelect(
              choices: prompt.choices,
              enabled: !_sending,
              onSubmit: _submit,
            )
          else if (prompt.choices.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final choice in prompt.choices)
                  FilledButton(
                    // Disabled once the question is no longer answerable —
                    // answered, or expired server-side. The record stays; the
                    // buttons must not pretend they can still land.
                    onPressed: _sending || widget.onAnswer == null
                        ? null
                        : () => _submit(choice),
                    child: Text(choice),
                  ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _answer,
                    autofocus: true,
                    obscureText: prompt.isSecret,
                    enableSuggestions: !prompt.isSecret,
                    autocorrect: !prompt.isSecret,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      hintText: prompt.multiSelect
                          ? 'Comma-separated: ${prompt.choices.join(', ')}'
                          : null,
                    ),
                    onSubmitted: _sending ? null : (v) => _submit(v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending || widget.onAnswer == null
                      ? null
                      : () => _submit(),
                  child: const Text('Answer'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Checkboxes for a `multi_select` clarify.
///
/// The answer goes back comma-separated, which is what the tool side parses;
/// a single selection still arrives as a one-element list, so this is the same
/// wire shape the single-select path uses.

class _MultiSelect extends StatefulWidget {
  const _MultiSelect({
    required this.choices,
    required this.enabled,
    required this.onSubmit,
  });

  final List<String> choices;
  final bool enabled;
  final void Function(String) onSubmit;

  @override
  State<_MultiSelect> createState() => _MultiSelectState();
}

class _MultiSelectState extends State<_MultiSelect> {
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final choice in widget.choices)
            FilterChip(
              label: Text(choice),
              selected: _picked.contains(choice),
              onSelected: widget.enabled
                  ? (on) => setState(
                      () => on ? _picked.add(choice) : _picked.remove(choice),
                    )
                  : null,
            ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Text(
            _picked.isEmpty
                ? 'Select one or more'
                : '${_picked.length} selected',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          FilledButton(
            // Answering nothing is not an answer, and the agent is
            // blocked until this returns.
            onPressed: widget.enabled && _picked.isNotEmpty
                ? () => widget.onSubmit(
                    // Emit in the order the server offered them, not in
                    // the order they were clicked.
                    widget.choices.where(_picked.contains).join(', '),
                  )
                : null,
            child: const Text('Answer'),
          ),
        ],
      ),
    ],
  );
}
