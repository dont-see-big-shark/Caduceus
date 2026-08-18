import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  group('AgentPrompt.isSecret', () {
    test('clarify is not secret', () {
      const prompt = AgentPrompt(id: PromptId('p1'), kind: AgentPromptKind.clarify);
      expect(prompt.isSecret, isFalse);
    });

    test('password is secret', () {
      const prompt = AgentPrompt(id: PromptId('p1'), kind: AgentPromptKind.password);
      expect(prompt.isSecret, isTrue);
    });

    test('secret kind is secret', () {
      const prompt = AgentPrompt(id: PromptId('p1'), kind: AgentPromptKind.secret);
      expect(prompt.isSecret, isTrue);
    });
  });

  group('AgentPrompt equality', () {
    test('equal by (id, kind), so a rebuilt prompt is still findable', () {
      const original = AgentPrompt(
        id: PromptId('p1'),
        kind: AgentPromptKind.clarify,
        question: 'What next?',
      );
      // Rebuilt with a different question — id/kind are what identity keys on.
      const rebuilt = AgentPrompt(
        id: PromptId('p1'),
        kind: AgentPromptKind.clarify,
        question: 'Different wording',
      );
      final prompts = [original];
      expect(prompts.contains(rebuilt), isTrue);
      expect(original, equals(rebuilt));
      expect(original.hashCode, rebuilt.hashCode);
    });

    test('different kind means different identity even with same id', () {
      const clarify = AgentPrompt(id: PromptId('p1'), kind: AgentPromptKind.clarify);
      const secret = AgentPrompt(id: PromptId('p1'), kind: AgentPromptKind.secret);
      expect(clarify, isNot(equals(secret)));
    });
  });

  group('PromptAnswer.toString', () {
    test('secret answers never contain the answer text', () {
      const answer = PromptAnswer('super-secret-value', secret: true);
      final rendered = answer.toString();
      expect(rendered, isNot(contains('super-secret-value')));
      expect(rendered, contains('${'super-secret-value'.length}'));
    });

    test('non-secret answers do contain the answer text', () {
      const answer = PromptAnswer('hello there', secret: false);
      expect(answer.toString(), contains('hello there'));
    });
  });

  group('PromptId', () {
    test('isEmpty/isNotEmpty', () {
      const empty = PromptId('');
      const filled = PromptId('p1');
      expect(empty.isEmpty, isTrue);
      expect(empty.isNotEmpty, isFalse);
      expect(filled.isEmpty, isFalse);
      expect(filled.isNotEmpty, isTrue);
    });
  });
}
