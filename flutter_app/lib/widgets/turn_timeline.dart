import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../workspace.dart';
import 'inline_prompt.dart';
import 'tool_call_tile.dart';

/// What the agent did this turn, in the order it did it.
///
/// Reasoning and tool calls used to render in two separate panes, which threw
/// the ordering away: a turn that thought, ran a command, then thought again
/// about the output appeared as one reasoning blob next to one tool list. The
/// sequence is most of what makes a long turn legible — "it is still thinking
/// about what the command printed" and "it has been stuck for a minute" look
/// the same without it.
/// **Requires a scrollable ancestor.** It sizes to its content on purpose —
/// it lives inside the transcript's list, in the turn it belongs to — so
/// placing it in a fixed-height box overflows as soon as a turn has more than
/// a few lines of reasoning.
class TurnTimeline extends StatefulWidget {
  const TurnTimeline({
    required this.console,
    required this.turn,
    required this.isCurrent,
    this.onAnswerPrompt,
    this.onStop,
    super.key,
  });

  final SessionConsole console;

  /// The one turn this renders. Each turn draws under its own question, so a
  /// conversation reads top to bottom — ask, think, run, answer, ask again.
  /// A single widget holding every turn put the previous turn's reasoning
  /// inside the newest turn's block and left history with no thinking at all.
  final Turn turn;

  /// Only the current turn shows live chrome — the tool being prepared, the
  /// status line. A finished turn is a record.
  final bool isCurrent;

  /// Answers a blocking question asked in this turn.
  final Future<bool> Function(AgentPrompt prompt, String value)? onAnswerPrompt;

  /// Abandons the running turn — the only other way out of a blocked one.
  final VoidCallback? onStop;

  @override
  State<TurnTimeline> createState() => _TurnTimelineState();
}

class _TurnTimelineState extends State<TurnTimeline> {
  /// Which thinking segments the user has opened or closed by hand. Their
  /// choice outranks the automatic one from then on.
  final Map<int, bool> _expanded = {};

  static String _elapsed(Duration d) => d.inMinutes < 1
      ? '${d.inSeconds}s'
      : '${d.inMinutes}m ${d.inSeconds % 60}s';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final console = widget.console;
    final entries = widget.turn.entries;
    final showsPreparing = widget.isCurrent && console.generatingTool != null;
    if (entries.isEmpty && !showsPreparing) return const SizedBox.shrink();

    return RepaintBoundary(
      child: Material(
        key: ValueKey('turn-${widget.turn.anchorBlock}'),
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        // No cap and no scroll view of its own: this sits inside the
        // transcript's list, in the turn it belongs to. A capped pane there
        // would be a second scrollable inside a scrollable — the trap this
        // codebase already removed twice — and would also mean the reasoning
        // could not scroll away with the turn that produced it.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++)
                Reveal(
                  index: i,
                  revealed: widget.turn.revealed,
                  child: switch (entries[i]) {
                    ThinkingSegment(:final open) => _segment(
                      theme,
                      entries[i] as ThinkingSegment,
                      i,
                      // Open while it is still being written, so the words
                      // moving are visible; folded once it is finished, so a
                      // long turn does not become a wall of reasoning.
                      _expanded[i] ?? open,
                    ),
                    ToolEntry(:final toolId) => _tool(console, toolId),
                    PromptEntry(:final prompt) => InlinePrompt(
                      prompt: prompt,
                      // Answerable only while it is still pending. A question
                      // the server has already given up on, or that was
                      // answered, stays visible as a record but stops offering
                      // buttons that can no longer land.
                      onAnswer:
                          console.prompts.contains(prompt) &&
                              widget.onAnswerPrompt != null
                          ? (value) => widget.onAnswerPrompt!(prompt, value)
                          : null,
                      // Offered only while this question is actually blocking
                      // something: stopping a finished turn does nothing.
                      onStop:
                          console.prompts.contains(prompt) && widget.isCurrent
                          ? widget.onStop
                          : null,
                    ),
                  },
                ),
              if (showsPreparing)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'preparing ${console.generatingTool}…',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tool(SessionConsole console, String toolId) {
    final call = console.tools[toolId];
    if (call == null) return const SizedBox.shrink();
    return ToolCallTile(call: call);
  }

  Widget _segment(
    ThemeData theme,
    ThinkingSegment segment,
    int index,
    bool expanded,
  ) {
    final label = segment.open
        ? 'Thinking ${_elapsed(segment.elapsed)}'
        : segment.durationKnown
        ? 'Thought for ${_elapsed(segment.elapsed)}'
        // Restored from the transcript: the server keeps what was
        // thought, not how long it took, and inventing "0s" would state a
        // duration nobody measured.
        : 'Thought';
    final preview = segment.preview;

    return InkWell(
      onTap: () => setState(() => _expanded[index] = !expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (segment.open)
                  const _ThinkingPulse(key: ValueKey('thinking-pulse'))
                else
                  Icon(
                    Icons.psychology_outlined,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
                const SizedBox(width: 8),
                if (segment.open)
                  _ShimmerText(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                // The server's explanation of the wait, beside the clock that
                // is counting it. This is the channel that says a provider is
                // overloaded or has not sent a first byte — the difference
                // between "it is working" and "it is stuck".
                if (segment.open && widget.console.statusLine.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.console.statusLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
            // Collapsed, this tail is the only sign anything is happening, so
            // it stays outside the disclosure.
            if (!expanded && preview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 2),
                child: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            if (expanded && segment.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 4),
                child: _SegmentBody(
                  text: segment.text.toString(),
                  follow: segment.open,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reasoning text that stays pinned to the newest line while it is still being
/// written, and stops moving under the user once it is not.
class _SegmentBody extends StatefulWidget {
  const _SegmentBody({required this.text, required this.follow, this.style});

  final String text;
  final bool follow;
  final TextStyle? style;

  @override
  State<_SegmentBody> createState() => _SegmentBodyState();
}

class _SegmentBodyState extends State<_SegmentBody> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_SegmentBody old) {
    super.didUpdateWidget(old);
    if (!widget.follow || widget.text == old.text) return;
    // After the frame: the new text has not been laid out yet, so
    // maxScrollExtent still describes the old content.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A capped, independently scrollable pane inside the timeline's own
    // scroll view is a trap on a touch screen: a drag that lands on the
    // reasoning scrolls the reasoning instead of the conversation, and there
    // is no cursor to tell you which one you are about to move. With a mouse
    // it is fine and saves a lot of scrolling, so the cap stays there.
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    if (touch) {
      return SelectableText(widget.text, style: widget.style);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: SingleChildScrollView(
        controller: _scroll,
        child: SelectableText(widget.text, style: widget.style),
      ),
    );
  }
}

/// A slow breathing dot, in place of a spinner.
///
/// A spinner reads as "loading, briefly". Thinking is not brief and is not
/// loading — it can run for minutes — and a spinner at that duration reads as
/// a hang. Something that breathes reads as alive.
class _ThinkingPulse extends StatefulWidget {
  const _ThinkingPulse({super.key});

  @override
  State<_ThinkingPulse> createState() => _ThinkingPulseState();
}

class _ThinkingPulseState extends State<_ThinkingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  /// Stops at full opacity, not wherever the fade happened to be: a dot left
  /// resting at .35 reads as disabled rather than as a dot that has stopped
  /// pulsing. The `Semantics` label carries the meaning either way.
  void _sync() {
    if (!mounted) return;
    final wanted = ambientAllowed(context);
    if (wanted == _c.isAnimating) return;
    if (wanted) {
      _c.repeat(reverse: true);
    } else {
      _c
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.primary;
    // Labelled: a dot whose only meaning is that it is moving says nothing to
    // a screen reader, and nothing to anyone who cannot see the motion.
    return Semantics(
      label: 'thinking',
      child: SizedBox(
        width: 12,
        height: 12,
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _c,
              curve: Curves.easeInOut,
            ).drive(Tween(begin: 0.35, end: 1.0)),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// A highlight travelling across the label while a turn is still thinking.
///
/// The elapsed counter already ticks, but a number changing once a second is
/// easy to miss on a phone held at arm's length. Motion across the text is
/// not.
class _ShimmerText extends StatefulWidget {
  const _ShimmerText(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<_ShimmerText>
    with SingleTickerProviderStateMixin {
  /// How wide the bright band is, in Alignment units — 1 is half the label.
  static const _band = 0.6;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  /// Ambient motion is always the user's to switch off, and this loop is the
  /// same kind as the aurora and the rim light: it says "still working" and
  /// nothing that is only said by it. The elapsed counter next to it carries
  /// the same information without moving.
  void _sync() {
    if (!mounted) return;
    final wanted = ambientAllowed(context);
    if (wanted == _c.isAnimating) return;
    if (wanted) {
      _c.repeat();
    } else {
      // Rest with the band fully off the left edge, so a stopped shimmer is
      // a plain label rather than one with a brass stripe frozen across it.
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style?.color ?? context.ink.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          // Fully off one edge to fully off the other: the band's own width
          // has to clear the label at both ends, or the highlight is already
          // a quarter of the way across on the first frame and pops in.
          final x = _c.value * (2 + _band * 2) - (1 + _band);
          return LinearGradient(
            begin: Alignment(x - _band, 0),
            end: Alignment(x + _band, 0),
            colors: [base, Palette.brass, base],
          ).createShader(bounds);
        },
        child: child,
      ),
      child: Text(widget.text, style: widget.style),
    );
  }
}
