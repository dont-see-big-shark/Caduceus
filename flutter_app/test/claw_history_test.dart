/// Reading a stored OpenClaw transcript.
///
/// A message's `content` is an array of typed parts, not a string, and the
/// gateway's own schema types it as unknown — so this shape is only visible on
/// a real transcript. It was: the first run against a live gateway put the
/// whole Dart rendering of that array on screen, signature blobs and all.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/claw_mapping.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a content-part array reads as text, not as its own source', () {
    // Exactly the shape a live gateway returned.
    final rows = [
      {
        'role': 'assistant',
        'content': [
          {
            'type': 'text',
            'text': 'Hello from the other side!',
            'textSignature': {'v': 1, 'id': 'msg_0217'},
          },
        ],
      },
    ];

    final messages = clawMessagesFromHistory(rows);

    expect(messages.single.text, 'Hello from the other side!');
    expect(
      messages.single.text,
      isNot(contains('textSignature')),
      reason: 'the signature is not something the agent said',
    );
    expect(messages.single.role, MessageRole.assistant);
  });

  test('thinking parts go to reasoning, not into the answer', () {
    final rows = [
      {
        'role': 'assistant',
        'content': [
          {'type': 'thinking', 'thinking': 'checking whether that file exists'},
          {'type': 'text', 'text': 'HEARTBEAT_OK'},
        ],
      },
    ];

    final messages = clawMessagesFromHistory(rows);

    // The same separation every other backend gets: a model's private notes
    // are not the reply, and concatenating them buries the reply inside them.
    expect(messages.single.text, 'HEARTBEAT_OK');
    expect(messages.single.reasoning, contains('checking whether'));
  });

  test('an image part is converted to markdown image, not dropped', () {
    final rows = [
      {
        'role': 'assistant',
        'content': [
          {'type': 'image', 'source': 'data:image/png;base64,AAA'},
          {'type': 'text', 'text': 'here it is'},
        ],
      },
    ];

    final msg = clawMessagesFromHistory(rows).single;
    expect(msg.text, contains('![image](data:image/png;base64,AAA)'));
    expect(msg.text, contains('here it is'));
  });

  test('a plain-text row still reads', () {
    // The gateway substitutes a placeholder string for an oversized message.
    final rows = [
      {'role': 'user', 'text': '[chat.history omitted: message too large]'},
    ];

    final message = clawMessagesFromHistory(rows).single;
    expect(message.text, contains('omitted'));
    expect(message.role, MessageRole.user);
    expect(message.reasoning, isNull);
  });

  group('a tool call in a stored transcript', () {
    // The two halves as a live gateway records them: the assistant asking for
    // the tool, then a `toolResult` row carrying what it printed.
    const call = {
      'role': 'assistant',
      'content': [
        {
          'type': 'toolCall',
          'id': 'exec-173',
          'name': 'exec',
          'arguments': {'command': 'date'},
        },
      ],
    };
    const result = {
      'role': 'toolResult',
      'toolCallId': 'exec-173',
      'toolName': 'exec',
      'isError': false,
      'content': [
        {'type': 'text', 'text': 'Thu Aug  6 12:26:55 CST 2026'},
      ],
    };

    test('the result is not an aside from the server', () {
      final message = clawMessagesFromHistory([result]).single;

      // `toolResult` is not a role this client knew, and an unknown role lands
      // on the system path — which rendered a command's raw output as an
      // italic note, a claim about who said it and a wrong one.
      expect(message.role, MessageRole.tool);
      expect(message.role, isNot(MessageRole.system));
      expect(message.toolCallId, 'exec-173');
      expect(message.toolCall?.output, contains('12:26:55'));
    });

    test('the call carries what it is about, not just the tool name', () {
      final message = clawMessagesFromHistory([call]).single;

      expect(message.toolCall?.name, 'exec');
      // A stored row has no `meta`, so the subject comes from the argument
      // that reads like one. "exec" alone says a tool ran, not what it did.
      expect(message.toolCall?.context, 'date');
      expect(message.toolCallId, 'exec-173');
      expect(message.isEmpty, isFalse, reason: 'the row *is* the call');
    });

    test('both halves reach the transcript as one tool entry', () {
      final console = SessionConsole(persistedId: 's1');
      console.loadHistory(
        clawMessagesFromHistory([
          {'role': 'user', 'content': 'what is the date'},
          call,
          result,
          {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'It is 6 August.'},
            ],
          },
        ]),
      );

      expect(console.tools['exec-173']?.name, 'exec');
      expect(console.tools['exec-173']?.done, isTrue);
      expect(console.tools['exec-173']?.output, contains('12:26:55'));
      expect(console.tools['exec-173']?.failed, isFalse);

      final entries = console.turns.expand((t) => t.entries).toList();
      expect(entries.whereType<ToolEntry>(), hasLength(1));
      // One entry, not two: the result completes the call rather than
      // arriving as a second row for the same command.
      expect(console.markdown.text, contains('It is 6 August.'));
      expect(
        console.markdown.text,
        isNot(contains('12:26:55')),
        reason:
            'a tool\'s output belongs in its own row, not in the '
            'conversation as something that was said',
      );
      console.dispose();
    });

    test('a failed tool says so', () {
      final message = clawMessagesFromHistory([
        {
          'role': 'toolResult',
          'toolCallId': 'read-9',
          'toolName': 'read_file',
          'isError': true,
          'content': [
            {'type': 'text', 'text': 'no such file'},
          ],
        },
      ]).single;

      expect(message.toolCall?.failed, isTrue);
      expect(message.toolCall?.error, contains('no such file'));
    });
  });
}
