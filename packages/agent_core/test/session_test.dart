import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  group('AgentSession.label', () {
    test('title wins when present', () {
      const session = AgentSession(
        id: 'id-1',
        title: 'Real title',
        preview: 'first message',
      );
      expect(session.label, 'Real title');
    });

    test('blank title falls back to preview', () {
      const session = AgentSession(
        id: 'id-1',
        title: '   ',
        preview: 'first message',
      );
      expect(session.label, 'first message');
    });

    test('blank title and preview fall back to id', () {
      const session = AgentSession(id: 'id-1', title: '', preview: '  ');
      expect(session.label, 'id-1');
    });
  });

  group('AgentSession.copyWith', () {
    test('id is never overridable and untouched fields persist', () {
      const original = AgentSession(
        id: 'id-1',
        title: 'title',
        preview: 'preview',
        messageCount: 3,
        running: true,
      );
      final copy = original.copyWith(messageCount: 4);
      // id has no copyWith parameter at all — it must survive unchanged.
      expect(copy.id, 'id-1');
      expect(copy.messageCount, 4);
      expect(copy.title, 'title');
      expect(copy.preview, 'preview');
      expect(copy.running, true);
    });
  });

  group('SessionHandle.withCursor', () {
    test('keeps sessionId/wireId and swaps the cursor', () {
      const handle = SessionHandle(
        sessionId: 'session-1',
        wireId: 'wire-1',
        cursor: 'old',
      );
      final next = handle.withCursor('new');
      expect(next.sessionId, 'session-1');
      expect(next.wireId, 'wire-1');
      expect(next.cursor, 'new');
    });
  });
}
