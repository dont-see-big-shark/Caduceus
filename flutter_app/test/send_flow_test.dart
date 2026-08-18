/// The whole send path, driven through the real widgets.
///
/// Everything below the UI is real — [Workspace], [HermesGateway], the JSON-RPC
/// framing, the streaming renderer — with only the socket replaced. The bugs
/// this is here to catch ("I sent a message and nothing happened") live in the
/// seams between those pieces, which unit tests on either side both pass.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/console_view.dart';
import 'package:caduceus/widgets/panel_frame.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

class _Socket implements GatewayTransport {
  final _in = StreamController<String>.broadcast();
  final sent = <Map<String, dynamic>>[];
  var closed = false;

  @override
  Stream<String> get inbound => _in.stream;

  @override
  void send(String data) => sent.add(jsonDecode(data) as Map<String, dynamic>);

  @override
  Future<void> close() async {
    closed = true;
    if (!_in.isClosed) await _in.close();
  }

  Map<String, dynamic>? lastOf(String method) {
    for (final f in sent.reversed) {
      if (f['method'] == method) return f;
    }
    return null;
  }

  void reply(String method, Object result) {
    final frame = lastOf(method)!;
    _in.add(
      jsonEncode({'jsonrpc': '2.0', 'id': frame['id'], 'result': result}),
    );
  }

  /// Server pushes all arrive wrapped in the `"event"` envelope.
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
  testWidgets('a sent message streams back into the transcript', (
    tester,
  ) async {
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    final workspace = Workspace(gateway);
    addTearDown(() async {
      workspace.dispose();
      await gateway.dispose();
    });

    // Open a persisted session. The gateway hands back a *different* live
    // handle, which is what every later frame is addressed with.
    final opening = workspace.open('20260101_aaa');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live99',
      'resumed': '20260101_aaa',
      'running': false,
      'status': 'idle',
      'info': {'model': 'test-model'},
      'messages': [
        {'role': 'user', 'text': 'earlier question'},
      ],
    });
    final console = await opening;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('earlier question'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ping');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();

    final submit = socket.lastOf('prompt.submit');
    expect(submit, isNotNull, reason: 'the prompt must reach the wire');
    expect(
      submit!['params']['session_id'],
      'live99',
      reason: 'addressed with the live handle, not the persisted id',
    );
    expect(submit['params']['text'], 'ping');
    socket.reply('prompt.submit', {'status': 'streaming'});

    // Reasoning first: this inserts a pane *above* the transcript, which used
    // to be enough to unhook the renderer for the rest of the turn.
    socket.event('reasoning.delta', 'live99', {'text': 'thinking hard'});
    await tester.pump();
    socket.event('message.start', 'live99', const {});
    for (final token in ['Hello', ', ', 'world', '.\n\n']) {
      socket.event('message.delta', 'live99', {'text': token});
      await tester.pump(const Duration(milliseconds: 20));
    }
    socket.event('message.complete', 'live99', const {});
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Hello, world.'),
      findsOneWidget,
      reason: 'the answer must actually render',
    );
    expect(console.streaming, isFalse);
    expect(console.deltaCount, 4);
  });

  testWidgets('typing @ asks the server and inserts the reference', (
    tester,
  ) async {
    // Path completion has to be a round trip: the caret is in *this* app but
    // the paths belong to the session's working directory on the gateway.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    final workspace = Workspace(gateway);
    addTearDown(() async {
      workspace.dispose();
      await gateway.dispose();
    });

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      // The picker opens from the model chip, which only shows once the
      // session says what it is running.
      'info': {'model': 'test-model'},
      'messages': <Object>[],
    });
    final console = await opening;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'look at @READ');
    await tester.pump(const Duration(milliseconds: 150));

    final ask = socket.lastOf('complete.path');
    expect(ask, isNotNull, reason: '@ must query the server');
    expect(ask!['params']['word'], '@READ');
    expect(ask['params']['session_id'], 'live1');

    socket.reply('complete.path', {
      'items': [
        {'text': '@README.md', 'display': 'README.md', 'meta': '2.1 KB'},
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('README.md'), findsOneWidget);

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();

    // Only the token under the caret is replaced — the rest of the sentence
    // has to survive.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'look at @README.md ',
    );
  });

  testWidgets('a blocking clarify is answered, not ignored', (tester) async {
    // The server parks the agent thread on these. Ignoring one stalls the turn
    // until the timeout, which looks identical to a dead connection — so this
    // asserts the answer actually reaches the wire with the request's own id.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    final workspace = Workspace(gateway);
    addTearDown(() async {
      workspace.dispose();
      await gateway.dispose();
    });

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': <Object>[],
    });
    final console = await opening;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();

    socket.event('clarify.request', 'live1', {
      'request_id': 'req42',
      'question': 'Which environment?',
      'choices': ['staging', 'production'],
    });
    await tester.pumpAndSettle();

    expect(find.text('The agent is asking'), findsOneWidget);
    expect(find.text('Which environment?'), findsOneWidget);

    await tester.tap(find.text('staging'));
    await tester.pumpAndSettle();

    final answer = socket.lastOf('clarify.respond');
    expect(answer, isNotNull, reason: 'the answer must reach the server');
    expect(
      answer!['params']['request_id'],
      'req42',
      reason: 'correlated by request id, not session id',
    );
    expect(answer['params']['answer'], 'staging');

    socket.reply('clarify.respond', {'status': 'ok'});
    await tester.pumpAndSettle();
    expect(console.prompts, isEmpty, reason: 'the banner must clear');
  });

  testWidgets('a secret request is masked and never echoed', (tester) async {
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    final workspace = Workspace(gateway);
    addTearDown(() async {
      workspace.dispose();
      await gateway.dispose();
    });

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': <Object>[],
    });
    final console = await opening;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();

    socket.event('secret.request', 'live1', {
      'request_id': 'req7',
      'prompt': 'GitHub token',
      'env_var': 'GITHUB_TOKEN',
    });
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.obscureText, isTrue, reason: 'a secret must not be echoed');
    expect(
      field.autocorrect,
      isFalse,
      reason: 'a credential must not enter the suggestion store',
    );

    await tester.enterText(find.byType(TextField).first, 'ghp_example');
    await tester.tap(find.text('Answer'));
    await tester.pumpAndSettle();

    expect(socket.lastOf('secret.respond')!['params']['value'], 'ghp_example');
    socket.reply('secret.respond', {'status': 'ok'});
    await tester.pumpAndSettle();
    // And it must not have leaked into the visible transcript.
    expect(console.markdown.text, isNot(contains('ghp_example')));
  });

  testWidgets('find searches inside the conversation', (tester) async {
    // The workspace's Cmd-F filters the session *list*. Searching within one
    // transcript is a different question that had no answer at all.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    addTearDown(gateway.dispose);
    final workspace = Workspace(gateway);
    addTearDown(workspace.dispose);

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': [
        {'role': 'user', 'text': 'how do I configure the proxy'},
        {'role': 'assistant', 'text': 'Set HTTPS_PROXY in the environment.'},
        {'role': 'user', 'text': 'and the timeout'},
      ],
    });
    final console = await opening;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find in conversation…'));
    await tester.pumpAndSettle();

    // The dialog's field, not the console composer behind it — `.first` in
    // tree order is the composer.
    // The Find dialog is the shared glass card now, not a flat AlertDialog.
    final field = find.descendant(
      of: find.byType(Panel),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'proxy');
    await tester.pumpAndSettle();

    // Case-insensitive, and both the question and the answer match.
    expect(find.textContaining('configure the proxy'), findsWidgets);
    expect(find.textContaining('HTTPS_PROXY'), findsWidgets);
    expect(find.text('2 matches'), findsOneWidget);

    await tester.enterText(field, 'nothing here');
    await tester.pumpAndSettle();
    expect(find.text('0 matches'), findsOneWidget);
  });

  testWidgets('undo rebuilds the transcript instead of leaving it stale', (
    tester,
  ) async {
    // session.undo drops messages server-side and emits nothing about it. A
    // console that keeps rendering them shows a conversation the agent can no
    // longer see, which is worse than showing nothing.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    addTearDown(gateway.dispose);
    final workspace = Workspace(gateway);
    addTearDown(workspace.dispose);

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': [
        {'role': 'user', 'text': 'first question'},
        {'role': 'assistant', 'text': 'first answer'},
      ],
    });
    final console = await opening;
    expect(console.markdown.text, contains('first answer'));

    final undone = workspace.undo('s1');
    await tester.pump();
    socket.reply('session.undo', {'removed': 2});
    await tester.pump();

    // The reload is a fresh resume, and the server now returns less.
    socket.reply('session.resume', {
      'session_id': 'live2',
      'resumed': 's1',
      'running': false,
      'messages': <Object>[],
    });
    expect(await undone, 2);
    await tester.pump();

    expect(
      console.markdown.text,
      isNot(contains('first answer')),
      reason: 'the removed exchange must be gone from the transcript',
    );
    expect(
      console.liveId,
      'live2',
      reason: 'the re-resume mints a new handle and events must follow it',
    );
  });

  testWidgets('the transcript copies as raw Markdown', (tester) async {
    // Rendered text loses the code fences and headings, which is most of what
    // makes a transcript useful somewhere else.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    addTearDown(gateway.dispose);
    final workspace = Workspace(gateway);
    addTearDown(workspace.dispose);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': <Object>[],
    });
    final console = await opening;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();

    socket.event('message.delta', 'live1', {
      'text': '# Heading\n\n```dart\nvoid main() {}\n```\n\n',
    });
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy transcript'));
    await tester.pumpAndSettle();

    expect(copied, contains('# Heading'));
    expect(
      copied,
      contains('```dart'),
      reason: 'the fence must survive — this is Markdown, not rendered text',
    );
  });

  testWidgets('a provider key is masked and goes straight to the server', (
    tester,
  ) async {
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    addTearDown(gateway.dispose);
    final workspace = Workspace(gateway);
    addTearDown(workspace.dispose);

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      // The picker opens from the model chip, which only appears once
      // the session says what it is running.
      'info': {'model': 'test-model'},
      'messages': <Object>[],
    });
    final console = await opening;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The model is a chip beside the field now, not an icon in the header.
    await tester.tap(find.text('test-model'));
    // Two pumps: the dialog mounts on the first, and its initState issues the
    // request on the second. Replying before it goes out finds no call.
    await tester.pump();
    await tester.pump();
    socket.reply('model.options', {
      'current_model': 'test-model',
      'providers': [
        {
          'slug': 'openai',
          'name': 'OpenAI',
          'authenticated': false,
          'models': <String>[],
        },
      ],
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect…'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.obscureText, isTrue, reason: 'an API key must not be echoed');
    expect(field.enableSuggestions, isFalse);

    await tester.enterText(find.byType(TextField).last, 'sk-example');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = socket.lastOf('model.save_key');
    expect(saved, isNotNull);
    expect(saved!['params'], {'slug': 'openai', 'api_key': 'sk-example'});
    // And it must not have reached the transcript.
    expect(console.markdown.text, isNot(contains('sk-example')));

    socket.reply('model.save_key', {'ok': true});
    await tester.pumpAndSettle();
  });

  testWidgets('resuming mid-turn shows the question being answered', (
    tester,
  ) async {
    // session.resume carries the accepted prompt and the answer so far.
    // Ignoring it left the transcript ending at the previous exchange, with
    // new deltas appending under no question at all.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    addTearDown(gateway.dispose);
    // Disposed in the body, not a teardown: a streaming console runs a 1 Hz
    // timer for the elapsed counter, and this turn never completes. The
    // binding checks for pending timers before teardowns run.
    final workspace = Workspace(gateway);

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': true,
      'messages': [
        {'role': 'user', 'text': 'earlier question'},
      ],
      'inflight': {
        'user': 'what is in the config',
        'assistant': 'So far it contains',
        'streaming': true,
      },
      'queued': {'user': 'and the lockfile'},
    });
    final console = await opening;

    final text = console.markdown.text;
    expect(text, contains('earlier question'), reason: 'history still loads');
    expect(
      text,
      contains('what is in the config'),
      reason: 'the question being answered must be visible',
    );
    expect(
      text,
      contains('So far it contains'),
      reason: 'the partial answer must not be lost',
    );
    // Not in the transcript: it has not been answered, and writing it after
    // the partial answer would split that answer when the next delta lands.
    expect(text, isNot(contains('and the lockfile')));
    expect(
      console.queuedPrompt,
      'and the lockfile',
      reason: 'a queued prompt is invisible everywhere else',
    );

    expect(console.streaming, isTrue);
    expect(
      console.answerStarted,
      isTrue,
      reason: 'answer text already arrived, so this is not still thinking',
    );

    // A delta now continues the partial answer rather than starting a new one.
    socket.event('message.delta', 'live1', {'text': ' three keys.'});
    await tester.pump();
    expect(
      console.markdown.text,
      contains('So far it contains three keys.'),
      reason:
          'the delta continues the partial answer, it does not restart '
          'one below it',
    );

    workspace.dispose();
  });

  testWidgets('a multi-select clarify answers with checkboxes', (tester) async {
    // The server sends multi_select for renderers that can do better than a
    // text box. The answer still goes back comma-separated, which is the wire
    // shape the tool side parses.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    addTearDown(gateway.dispose);
    final workspace = Workspace(gateway);
    addTearDown(workspace.dispose);

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': <Object>[],
    });
    final console = await opening;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();

    socket.event('clarify.request', 'live1', {
      'request_id': 'c1',
      'question': 'Which targets?',
      'choices': ['macos', 'ios', 'web'],
      'multi_select': true,
    });
    await tester.pumpAndSettle();

    // Nothing selected yet: answering would send an empty answer to an agent
    // that is blocked waiting for one.
    final answer = find.widgetWithText(FilledButton, 'Answer');
    expect(tester.widget<FilledButton>(answer).onPressed, isNull);

    await tester.tap(find.widgetWithText(FilterChip, 'web'));
    await tester.tap(find.widgetWithText(FilterChip, 'macos'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(answer);
    await tester.pump();

    final sent = socket.lastOf('clarify.respond');
    expect(sent, isNotNull);
    // Reply, or the call's 30-second timeout timer outlives the test.
    socket.reply('clarify.respond', {'ok': true});
    await tester.pumpAndSettle();
    expect(sent!['params']['request_id'], 'c1');
    // Server order, not click order.
    expect(sent['params']['answer'], 'macos, web');
  });

  testWidgets('an expired prompt withdraws its banner', (tester) async {
    // The server gives up after its timeout and says so. Leaving the banner up
    // invites an answer that can no longer be delivered.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    addTearDown(gateway.dispose);
    final workspace = Workspace(gateway);
    addTearDown(workspace.dispose);

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': <Object>[],
    });
    final console = await opening;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();

    socket.event('sudo.request', 'live1', {
      'request_id': 'req1',
      'prompt': 'password for deploy',
    });
    await tester.pumpAndSettle();
    expect(console.prompts, hasLength(1));

    socket.event('sudo.expire', 'live1', {'request_id': 'req1'});
    await tester.pumpAndSettle();
    expect(
      console.prompts,
      isEmpty,
      reason: 'an expired request must stop asking',
    );
  });

  testWidgets('a terminal read is answered at once, not left to time out', (
    tester,
  ) async {
    // The server blocks the read_terminal tool for 30 s waiting on this.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    addTearDown(gateway.dispose);
    final workspace = Workspace(gateway);
    addTearDown(workspace.dispose);

    socket.event('terminal.read.request', 'live1', {'request_id': 'tr1'});
    await tester.pump();
    await tester.pump();

    final answer = socket.lastOf('terminal.read.respond');
    expect(answer, isNotNull, reason: 'the agent must not be left waiting');
    expect(answer!['params']['request_id'], 'tr1');
    // The tool hands this string to the agent verbatim, so it has to be JSON
    // and it has to explain itself.
    final text = jsonDecode(answer['params']['text'] as String) as Map;
    expect(text['lines'], isEmpty);
    expect(text['note'], contains('no in-app terminal'));

    socket.reply('terminal.read.respond', {'status': 'ok'});
    await tester.pump();
  });

  testWidgets('a reply landing after dispose does not crash the app', (
    tester,
  ) async {
    // A hung server method still answers eventually. If the user closed the
    // workspace meanwhile, the handler notifies a disposed ChangeNotifier —
    // which throws. Seen for real against a server whose session.list stopped
    // responding for 30 s.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    // Torn down outside the fake-async zone: awaiting a socket close inside it
    // parks forever, because the close event needs time that only pump()
    // advances.
    addTearDown(gateway.dispose);
    final workspace = Workspace(gateway);

    // Not awaited: the point is what happens to the *handler* when the reply
    // lands after dispose, and flutter_test fails the test on any unhandled
    // exception from it.
    unawaited(workspace.refreshSessions());
    await tester.pump();

    workspace.dispose();
    socket.reply('session.list', {'sessions': []});
    await tester.pump(const Duration(milliseconds: 50));

    // Reaching here without an exception is the assertion.
  });

  testWidgets('a send that fails while disconnected surfaces an error', (
    tester,
  ) async {
    // Not a GatewayRpcException — this is the path that used to escape every
    // catch clause, leaving the console stuck at "streaming" with no message.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
      maxReconnectAttempts: 0,
    );
    await gateway.connect();
    final workspace = Workspace(gateway);
    addTearDown(() async {
      workspace.dispose();
      await gateway.dispose();
    });

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 's1',
      'resumed': 's1',
      'running': false,
      'messages': <Object>[],
    });
    final console = await opening;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await socket.close();
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ping');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(
      console.lastError,
      isNotNull,
      reason: 'the user has to be told the send did not happen',
    );
    expect(
      console.streaming,
      isFalse,
      reason: 'a stuck streaming flag silently turns later sends into steers',
    );
    expect(find.textContaining(console.lastError!), findsOneWidget);
  });
}
