/// A session heading should say what the session is about.
///
/// The persisted id is a timestamp — `20260802_220058_cc4868`. Using it as a
/// heading tells the user when they started, which the ordering already tells
/// them, and tells them nothing about which conversation this is.
library;

import 'dart:async';
import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/hermes_mapping.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

/// The console consumes domain events. These fixtures stay written in Hermes'
/// vocabulary and go through the app's own adapter, which is the path a real
/// frame takes.
AgentEvent _agent(GatewayEvent event) =>
    agentEventFromHermes(event.sessionId ?? '', event)!;

class _Socket implements GatewayTransport {
  final _in = StreamController<String>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  Stream<String> get inbound => _in.stream;
  @override
  void send(String data) => sent.add(jsonDecode(data) as Map<String, dynamic>);
  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  Map<String, dynamic>? lastOf(String method) {
    for (final f in sent.reversed) {
      if (f['method'] == method) return f;
    }
    return null;
  }

  void reply(String method, Object result) => _in.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': lastOf(method)!['id'],
      'result': result,
    }),
  );

  void event(String type, String sessionId, Map<String, dynamic> payload) =>
      _in.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {'type': type, 'session_id': sessionId, 'payload': payload},
        }),
      );
}

void main() {
  test('a titled session shows its title, not its id', () {
    final console = SessionConsole(
      persistedId: '20260802_220058_cc4868',
      liveId: 'live1',
    );
    expect(
      console.displayTitle,
      '20260802_220058_cc4868',
      reason: 'with nothing better, the id at least identifies it',
    );

    console.title = 'Blue Sky Explanation';
    expect(console.displayTitle, 'Blue Sky Explanation');
    console.dispose();
  });

  test('the server pushing a title updates the heading', () {
    final console = SessionConsole(persistedId: '20260802_1', liveId: 'l1');
    var notified = 0;
    console.addListener(() => notified++);

    console.handle(
      _agent(
        GatewayEvent(
          type: 'session.title',
          sessionId: 'l1',
          payload: const {'title': 'Sheep Counting Riddle'},
        ),
      ),
    );

    expect(console.displayTitle, 'Sheep Counting Riddle');
    expect(notified, 1, reason: 'the heading has to repaint');
    console.dispose();
  });

  test('a blank title from the server is ignored', () {
    // Otherwise a stray empty push would blank a heading that was fine.
    final console = SessionConsole(persistedId: '20260802_1', liveId: 'l1');
    console.title = 'Something useful';
    console.handle(
      _agent(
        GatewayEvent(
          type: 'session.title',
          sessionId: 'l1',
          payload: const {'title': '   '},
        ),
      ),
    );
    expect(console.displayTitle, 'Something useful');
    console.dispose();
  });

  testWidgets('a title derived mid-conversation reaches the sidebar too', (
    tester,
  ) async {
    // The header and the list draw the same session. A title arriving while
    // the conversation is happening updated one and not the other, so a new
    // session kept reading "(untitled)" in the very list it was selected from.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    addTearDown(gateway.dispose);
    final workspace = Workspace(gateway);
    addTearDown(workspace.dispose);

    final listing = workspace.refreshSessions();
    await tester.pump();
    socket.reply('session.list', {
      'sessions': [
        {'id': 's1', 'title': '', 'preview': 'first question'},
      ],
    });
    await listing;

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': <Object>[],
    });
    await opening;

    socket.event('session.info', 'live1', {'title': 'Blue Sky Explanation'});
    await tester.pump();

    expect(workspace.consoleFor('s1')?.displayTitle, 'Blue Sky Explanation');
    expect(
      workspace.sessions.single.label,
      'Blue Sky Explanation',
      reason: 'the row the user picked shows what they are now reading',
    );
  });

  testWidgets('a session started elsewhere appears without a refresh', (
    tester,
  ) async {
    // The case the index subscription exists for. A conversation begun on a
    // phone is invisible until the next refresh otherwise, and the per-session
    // event stream can say nothing about a session nobody opened.
    final backend = _IndexBackend();
    final workspace = Workspace.forBackend(backend);
    addTearDown(workspace.dispose);

    expect(workspace.sessions, isEmpty);

    backend.announce(
      const AgentSession(id: 'agent:main:ios-9f2', title: 'from the phone'),
    );
    await tester.pump();

    expect(workspace.sessions.single.label, 'from the phone');

    // The same session again is a merge, not a second row.
    backend.announce(
      const AgentSession(id: 'agent:main:ios-9f2', title: 'renamed'),
    );
    await tester.pump();

    expect(workspace.sessions, hasLength(1));
    expect(workspace.sessions.single.label, 'renamed');
  });

  testWidgets('a row with nothing to show for itself waits', (tester) async {
    // The first frame for a brand-new session names neither a title nor a
    // preview. A row reading as nothing at all is worse than one that arrives
    // a moment later with something in it.
    final backend = _IndexBackend();
    final workspace = Workspace.forBackend(backend);
    addTearDown(workspace.dispose);

    backend.announce(const AgentSession(id: 'agent:main:dashboard:new'));
    await tester.pump();

    expect(workspace.sessions, isEmpty);
  });
}

/// A backend that does nothing but announce sessions.
class _IndexBackend implements AgentBackend {
  final _index = StreamController<AgentSession>.broadcast();

  void announce(AgentSession session) => _index.add(session);

  @override
  Stream<AgentSession> get sessionUpdates => _index.stream;

  @override
  String get id => 'test';
  @override
  String get displayName => 'Test';
  @override
  AgentConnection get connectionState =>
      const AgentConnection(AgentStatus.connected);
  @override
  Stream<AgentConnection> get connection => const Stream.empty();
  @override
  bool supports(Capability capability) => false;

  @override
  Future<void> dispose() async => _index.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not part of this '
    'test — it announces sessions and nothing else.',
  );
}
