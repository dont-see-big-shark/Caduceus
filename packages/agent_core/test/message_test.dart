import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  group('AgentMessage.isEmpty', () {
    test('true when text and reasoning are both blank', () {
      const message = AgentMessage(
        role: MessageRole.assistant,
        text: '   ',
        reasoning: '  ',
      );
      expect(message.isEmpty, isTrue);
    });

    test('true when reasoning is null and text is blank', () {
      const message = AgentMessage(role: MessageRole.assistant, text: '');
      expect(message.isEmpty, isTrue);
    });

    test('false when text has content', () {
      const message = AgentMessage(role: MessageRole.user, text: 'hi');
      expect(message.isEmpty, isFalse);
    });

    test('false when only reasoning has content', () {
      const message = AgentMessage(
        role: MessageRole.assistant,
        text: '  ',
        reasoning: 'thinking...',
      );
      expect(message.isEmpty, isFalse);
    });
  });
}
