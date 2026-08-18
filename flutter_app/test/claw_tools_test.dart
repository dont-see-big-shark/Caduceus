/// A tool call, as OpenClaw actually reports one.
///
/// Every frame here is a real `session.tool` payload, captured from a live
/// gateway running `date`. The adapter declared `Capability.toolCalls` and
/// mapped none of them, so the turn timeline stayed empty while the agent
/// worked — the capability said yes and nothing appeared.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/claw_mapping.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = 'exec-1785990415284667692-173';

void main() {
  test('start names the tool and what this call is about', () {
    final e =
        clawToolEvent('s1', const {
              'phase': 'start',
              'name': 'exec',
              'toolCallId': _id,
              'args': {'command': 'date'},
            })!
            as ToolStarted;

    expect(e.toolId, _id);
    expect(e.call.name, 'exec');
    expect(e.call.args?['command'], 'date');
  });

  test('the gateway sends each phase three times; two are its own UI rows', () {
    // Tagged `tool:` and `command:`, they are rows in the gateway's activity
    // list rather than the call. Taking all three renders it three times.
    for (final itemId in const ['tool:$_id', 'command:$_id']) {
      expect(
        clawToolEvent('s1', {
          'itemId': itemId,
          'phase': 'start',
          'name': 'exec',
          'toolCallId': _id,
        }),
        isNull,
      );
    }
  });

  test('delta carries output; update repeats it and is dropped', () {
    final delta = clawToolEvent('s1', const {
      'phase': 'delta',
      'name': 'exec',
      'toolCallId': _id,
      'output': 'Thu Aug  6 12:26:55 CST 2026',
    });
    expect((delta! as ToolProgress).text, contains('12:26:55'));

    // `update` carries the same bytes as a partialResult. Forwarding both
    // prints the tool's output twice.
    expect(
      clawToolEvent('s1', const {
        'phase': 'update',
        'name': 'exec',
        'toolCallId': _id,
        'partialResult': {
          'content': [
            {'type': 'text', 'text': 'Thu Aug  6 12:26:55 CST 2026'},
          ],
        },
      }),
      isNull,
    );
  });

  test('result reads the output, the exit code and how long it took', () {
    final e =
        clawToolEvent('s1', const {
              'phase': 'result',
              'name': 'exec',
              'toolCallId': _id,
              'meta': 'date',
              'isError': false,
              'result': {
                'content': [
                  {'type': 'text', 'text': 'Thu Aug  6 12:26:55 CST 2026'},
                ],
                'details': {
                  'status': 'completed',
                  'exitCode': 0,
                  'durationMs': 26,
                  'aggregated': 'Thu Aug  6 12:26:55 CST 2026',
                },
              },
            })!
            as ToolFinished;

    expect(e.call.done, isTrue);
    expect(e.call.output, 'Thu Aug  6 12:26:55 CST 2026');
    expect(e.call.exitCode, 0);
    expect(e.call.durationSeconds, closeTo(0.026, 0.0001));
    expect(e.call.context, 'date', reason: 'the row says what it ran');
    expect(e.call.failed, isFalse);
  });

  test('a failure is taken from the gateway, not inferred', () {
    // A tool that is not a process has no exit code to read a failure from,
    // so `isError` is the fact and `exitReason` is the reason.
    final e =
        clawToolEvent('s1', const {
              'phase': 'result',
              'name': 'read_file',
              'toolCallId': _id,
              'isError': true,
              'result': {
                'details': {'exitReason': 'no such file'},
              },
            })!
            as ToolFinished;

    expect(e.call.failed, isTrue);
    expect(e.call.error, 'no such file');
  });

  test('output falls back to the gateway flattening, never to the array', () {
    final e =
        clawToolEvent('s1', const {
              'phase': 'result',
              'name': 'exec',
              'toolCallId': _id,
              'result': {
                'content': [
                  {'type': 'image', 'source': 'data:image/png;base64,AAA'},
                ],
                'details': {'aggregated': 'two files'},
              },
            })!
            as ToolFinished;

    expect(e.call.output, 'two files');
    expect(e.call.output, isNot(contains('base64')));
  });

  test('a running tool shows what it has printed so far', () {
    final console = SessionConsole(persistedId: 's1');
    console.handle(
      clawToolEvent('s1', const {
        'phase': 'start',
        'name': 'exec',
        'toolCallId': _id,
        'meta': 'npm test',
      })!,
    );
    console.handle(
      clawToolEvent('s1', const {
        'phase': 'delta',
        'name': 'exec',
        'toolCallId': _id,
        'output': 'running 12 tests\n',
      })!,
    );
    console.handle(
      clawToolEvent('s1', const {
        'phase': 'delta',
        'name': 'exec',
        'toolCallId': _id,
        'output': 'all passed\n',
      })!,
    );

    // For the calls worth watching the wait *is* when somebody is watching,
    // so an empty row until it finishes shows nothing for exactly as long as
    // it matters.
    expect(console.tools[_id]?.output, 'running 12 tests\nall passed\n');
    expect(console.tools[_id]?.done, isFalse);
    console.dispose();
  });

  test('progress for a finished tool does not reopen it', () {
    final console = SessionConsole(persistedId: 's1');
    console.handle(
      clawToolEvent('s1', const {
        'phase': 'result',
        'name': 'exec',
        'toolCallId': _id,
        'result': {
          'details': {'aggregated': 'done', 'exitCode': 0},
        },
      })!,
    );
    console.handle(
      clawToolEvent('s1', const {
        'phase': 'delta',
        'name': 'exec',
        'toolCallId': _id,
        'output': 'late',
      })!,
    );

    expect(console.tools[_id]?.done, isTrue);
    expect(console.tools[_id]?.output, 'done');
    console.dispose();
  });
}
