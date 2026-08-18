/// Model-switch markers are not something the user said.
///
/// Found on the simulator: a real conversation opened with a brass question
/// bubble reading "[System: The active model for this chat has changed to
/// gemini-3-flash-agent via provider antigravity-local. From this point
/// forward, use this runtime metadata …]". The server stores that marker with
/// `role: "user"` on purpose — strict OpenAI-compatible providers reject a
/// system message that is not first — so a client reading only `role` puts
/// words in the user's mouth.
library;

import 'package:caduceus/widgets/message_bubble.dart';
import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/hermes_mapping.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

const _marker =
    '[System: The active model for this chat has changed to gemini-3-flash '
    'via provider antigravity-local. From this point forward, use this '
    'runtime metadata when answering questions about what model/provider is '
    'active.]';

/// A stored row in the wire's vocabulary, mapped through the app's own
/// adapter. The mapping is where a marker stops being a user message, so a
/// fixture that skipped it would test the console against a shape the console
/// never actually receives.
AgentMessage _stored(Map<String, dynamic> json) =>
    agentMessageFromHermes(SessionMessage.fromJson(json));

void main() {
  test('a model-switch marker is not a user turn', () {
    final m = SessionMessage.fromJson({
      'role': 'user',
      'text': _marker,
      'display_kind': 'model_switch',
    });

    expect(m.isSystemNote, isTrue);
    expect(m.isUser, isFalse, reason: 'the user did not type this');
  });

  test('an untyped marker is still recognised', () {
    // The case that actually shipped. The server only migrates *auto-continue*
    // rows by sniffing the prefix, so a model marker written before it started
    // stamping `display_kind` arrives with the field empty — which is exactly
    // what a real session on the live server returned.
    final m = SessionMessage.fromJson({'role': 'user', 'text': _marker});

    expect(m.isSystemNote, isTrue);
    expect(m.isUser, isFalse);
  });

  test('an auto-continue note is not a user turn either', () {
    // The server's own comment: without typing, the raw recovery note "would
    // paint as a user bubble forever".
    final m = SessionMessage.fromJson({
      'role': 'user',
      'text': 'continue',
      'display_kind': 'auto_continue',
    });

    expect(m.isSystemNote, isTrue);
  });

  test('an ordinary user message is unaffected', () {
    final m = SessionMessage.fromJson({
      'role': 'user',
      'text': 'what is the weather in Wanning',
    });

    expect(m.isSystemNote, isFalse);
    expect(m.isUser, isTrue);
  });

  test('the marker renders as an aside, not a question bubble', () {
    final console = SessionConsole(persistedId: 's1');
    console.loadHistory([
      _stored({
        'role': 'user',
        'text': _marker,
        'display_kind': 'model_switch',
      }),
      _stored({'role': 'user', 'text': 'and now?'}),
    ]);

    final blocks = console.markdown.text.split('\n\n')
      ..removeWhere((b) => b.trim().isEmpty);

    expect(
      isUserBlock(blocks.first),
      isFalse,
      reason: 'the marker must not become a question bubble',
    );
    expect(
      isUserBlock(blocks[1]),
      isTrue,
      reason: 'and the real question after it still is one',
    );

    // The half addressed to the model is dropped; the fact is kept.
    expect(blocks.first, contains('gemini-3-flash'));
    expect(blocks.first, isNot(contains('From this point forward')));
    expect(blocks.first, isNot(contains('[System:')));
  });

  test('a marker missing its closing bracket is still cleaned up', () {
    // Exactly what the live server returned: the row came back without its
    // final "]", so a strip that required both brackets left "[System:" on
    // screen. Each delimiter has to be removed on its own evidence.
    final console = SessionConsole(persistedId: 's1');
    console.loadHistory([
      _stored({
        'role': 'user',
        'text': _marker.substring(0, _marker.length - 1),
        'display_kind': 'model_switch',
      }),
    ]);

    expect(console.markdown.text, isNot(contains('[System:')));
    expect(console.markdown.text, isNot(contains('System:')));
    expect(console.markdown.text, contains('gemini-3-flash'));
  });
}
