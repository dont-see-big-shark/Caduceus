import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  group('AgentToolCall.failed', () {
    test('true when error is set', () {
      const call = AgentToolCall(name: 'bash', error: 'boom');
      expect(call.failed, isTrue);
    });

    test('true when exitCode is non-zero', () {
      const call = AgentToolCall(name: 'bash', exitCode: 1);
      expect(call.failed, isTrue);
    });

    test('false when exitCode is 0 with no error', () {
      const call = AgentToolCall(name: 'bash', exitCode: 0);
      expect(call.failed, isFalse);
    });

    test('false when neither error nor exitCode is set', () {
      const call = AgentToolCall(name: 'bash');
      expect(call.failed, isFalse);
    });
  });

  group('AgentToolCall.query', () {
    test('extracts a non-blank string query', () {
      const call = AgentToolCall(name: 'web_search', args: {'query': 'cats'});
      expect(call.query, 'cats');
    });

    test('trims the extracted query', () {
      const call = AgentToolCall(
        name: 'web_search',
        args: {'query': '  cats  '},
      );
      expect(call.query, 'cats');
    });

    test('null for a blank query', () {
      const call = AgentToolCall(name: 'web_search', args: {'query': '   '});
      expect(call.query, isNull);
    });

    test('null for a missing query key', () {
      const call = AgentToolCall(name: 'web_search', args: {'other': 'x'});
      expect(call.query, isNull);
    });

    test('null when args is not set at all', () {
      const call = AgentToolCall(name: 'web_search');
      expect(call.query, isNull);
    });

    test('null for a non-String query value', () {
      const call = AgentToolCall(name: 'web_search', args: {'query': 42});
      expect(call.query, isNull);
    });
  });

  group('AgentToolCall.completed', () {
    test('keeps name and context, marks done, applies new fields', () {
      const call = AgentToolCall(name: 'bash', context: 'ls -la');
      final done = call.completed(
        durationSeconds: 1.5,
        output: 'file1\nfile2',
        exitCode: 0,
      );
      expect(done.name, 'bash');
      expect(done.context, 'ls -la');
      expect(done.done, isTrue);
      expect(done.durationSeconds, 1.5);
      expect(done.output, 'file1\nfile2');
      expect(done.exitCode, 0);
    });
  });
}
