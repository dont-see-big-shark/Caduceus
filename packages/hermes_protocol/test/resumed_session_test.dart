/// `session.resume` returns two different ids, and using the wrong one breaks
/// most of the console.
///
/// `methods_session.py` mints `sid = uuid.uuid4().hex[:8]` on resume and
/// registers the session in the live `_sessions` map under *that*. Addressing
/// it with the persisted id fails `session not found` (4001); addressing it
/// with the gateway handle works. Verified live: `title` via the persisted id
/// returned 4001, via the handle returned 4021 ("title required") — a
/// different error, proving the session was found.
library;

import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:test/test.dart';

/// The real shape, transcribed from a live v0.19.x resume.
Map<String, dynamic> resumeResponse({
  String liveId = '0447086c',
  String persistedId = 'desk-1780531014036-b6702461',
}) =>
    {
      'session_id': liveId,
      'resumed': persistedId,
      'message_count': 2,
      'messages': [
        {'role': 'user', 'text': 'hello'},
        {'role': 'assistant', 'text': 'hi', 'reasoning': 'thinking'},
      ],
      'info': {'model': 'glm-5-2-260617'},
      'running': false,
      'status': 'idle',
    };

void main() {
  test('the live handle comes from session_id, not resumed', () {
    final r = ResumedSession.fromJson(resumeResponse());
    // Getting this backwards breaks title, interrupt, steer, compress,
    // approval.respond, and event routing — all with an opaque 4001.
    expect(r.liveId, '0447086c');
    expect(r.persistedId, 'desk-1780531014036-b6702461');
    expect(r.liveId, isNot(r.persistedId));
  });

  test('a freshly created session has no separate handle', () {
    // session.create registers under the id it returns, so both agree.
    final r = ResumedSession.fromJson({
      'session_id': 'abc12345',
      'messages': const [],
    });
    expect(r.liveId, 'abc12345');
    expect(r.persistedId, 'abc12345');
  });

  test('transcript and metadata survive parsing', () {
    final r = ResumedSession.fromJson(resumeResponse());
    expect(r.messages, hasLength(2));
    expect(r.messages.first.isUser, isTrue);
    expect(r.messages.last.reasoning, 'thinking');
    expect(r.model, 'glm-5-2-260617');
    expect(r.running, isFalse);
  });

  test('events must be routed by the live handle', () {
    // The gateway emits against its own sid, so a client keyed on the
    // persisted id receives nothing for a resumed session.
    final event = GatewayEvent(
      type: 'message.delta',
      sessionId: '0447086c',
      payload: const {'text': 'hi'},
    );
    final r = ResumedSession.fromJson(resumeResponse());
    expect(event.sessionId, r.liveId);
    expect(event.sessionId, isNot(r.persistedId));
  });
}
