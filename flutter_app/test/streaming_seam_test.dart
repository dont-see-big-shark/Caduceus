/// The seam between the two spikes: control-plane events in, incrementally
/// rendered Markdown out.
///
/// Both halves are already tested in isolation. What is untested until here is
/// that they fit — specifically that `GatewayEvent.deltaText` extracts the same
/// field Hermes actually populates, and that feeding those deltas to the
/// splitter settles blocks rather than growing one unbounded tail.
///
/// The envelopes below are the real shape emitted by `_event_frame` in
/// `tui_gateway/server.py`, verified against a live v0.19.1 gateway — not
/// invented for the test.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

/// Builds the frame Hermes puts on the wire for one streamed token.
String deltaFrame(String text, {String sessionId = 's-1'}) => jsonEncode({
  'jsonrpc': '2.0',
  'method': 'event',
  'params': {
    'type': 'message.delta',
    'session_id': sessionId,
    'payload': {'text': text},
  },
});

GatewayEvent? parseEvent(String raw) {
  final frame = GatewayFrame.parse(raw);
  return frame is GatewayNotification
      ? GatewayEvent.fromNotification(frame)
      : null;
}

void main() {
  test('a wire-format delta frame yields renderable text', () {
    final event = parseEvent(deltaFrame('Hello'))!;
    expect(event.type, 'message.delta');
    expect(event.sessionId, 's-1');
    expect(event.isStreamingDelta, isTrue);
    expect(event.answerText, 'Hello');
    expect(event.reasoningText, isNull);
  });

  test('reasoning is a separate channel from the answer', () {
    final reasoning = parseEvent(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {
          'type': 'reasoning.delta',
          'session_id': 's-1',
          'payload': {'text': 'thinking out loud'},
        },
      }),
    )!;
    // Live run: 13 reasoning frames to 1 answer frame. Merging them would bury
    // the reply inside the model's private notes.
    expect(reasoning.answerText, isNull);
    expect(reasoning.reasoningText, 'thinking out loud');
    expect(reasoning.isReasoningDelta, isTrue);
  });

  test('non-delta events expose no delta text', () {
    final ready = parseEvent(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {
          'type': 'gateway.ready',
          'session_id': 's-1',
          'payload': {'skin': 'default'},
        },
      }),
    )!;
    expect(ready.answerText, isNull);
    expect(ready.isStreamingDelta, isFalse);
  });

  test('approval requests are recognised — control-plane only capability', () {
    final approval = parseEvent(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {
          'type': 'approval.request',
          'session_id': 's-1',
          'payload': {'request_id': 'req-7', 'tool': 'shell'},
        },
      }),
    )!;
    expect(approval.isApprovalRequest, isTrue);
    expect(approval.payload['request_id'], 'req-7');
  });

  test('streamed deltas settle into blocks instead of one growing tail', () {
    final controller = StreamingMarkdownController();

    const response = '''
Here is the change.

```dart
void main() => print('hi');
```

That should do it.
''';

    // Chunked the way a model emits, not line by line.
    for (var i = 0; i < response.length; i += 4) {
      final chunk = response.substring(i, (i + 4).clamp(0, response.length));
      final event = parseEvent(deltaFrame(chunk))!;
      controller.append(event.answerText!);
    }

    expect(controller.text, response);
    // Prose, fence, prose — the fence must be one block, not split at the
    // blank line inside it.
    expect(controller.settledBlockCount, greaterThanOrEqualTo(2));

    controller.dispose();
  });

  test('per-frame parse work stays bounded as the response grows', () {
    // The property the framework recommendation rests on. If the tail grew with
    // the response, the renderer would be quadratic again.
    final controller = StreamingMarkdownController();
    final splitter = IncrementalSplitter();

    var maxTail = 0;
    for (var para = 0; para < 60; para++) {
      final text = 'Paragraph $para with enough words to be realistic.\n\n';
      controller.append(text);
      splitter.append(text);
      if (splitter.tail.length > maxTail) maxTail = splitter.tail.length;
    }

    expect(controller.text.length, greaterThan(2500));
    expect(
      maxTail,
      lessThan(200),
      reason: 'tail must stay bounded by block size, not response length',
    );

    controller.dispose();
  });

  test('an oversized single block is the known exception', () {
    // A long table has no blank lines, so it is one block and the tail grows
    // with it. StreamingMarkdownView throttles rather than dropping frames;
    // this documents that the splitter genuinely cannot help here.
    final splitter = IncrementalSplitter();
    final table = StringBuffer('| a | b |\n|---|---|\n');
    for (var i = 0; i < 200; i++) {
      table.writeln('| row $i | value $i |');
    }
    splitter.append(table.toString());

    expect(splitter.blockCount, 0);
    expect(splitter.tail.length, greaterThan(2000));
  });
}
