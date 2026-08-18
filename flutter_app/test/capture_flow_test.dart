/// The camera and the microphone, end to end.
///
/// Both were drawn in the prototype's composer and neither existed. A tile and
/// a button are the cheap half; what these pin is the other half — that a
/// photo taken on the phone reaches the session as an image, and that the
/// microphone *types* rather than pretending to send audio the server has no
/// channel for.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/console_view.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

import 'fake_capture.dart';

class _Socket implements GatewayTransport {
  final _in = StreamController<String>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  Stream<String> get inbound => _in.stream;
  @override
  void send(String d) => sent.add(jsonDecode(d) as Map<String, dynamic>);
  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  Map<String, dynamic>? lastOf(String m) {
    for (final f in sent.reversed) {
      if (f['method'] == m) return f;
    }
    return null;
  }

  void reply(String m, Object r) => _in.add(
    jsonEncode({'jsonrpc': '2.0', 'id': lastOf(m)!['id'], 'result': r}),
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

Future<(_Socket, SessionConsole)> _mount(
  WidgetTester tester, {
  FakeMedia? media,
  FakeVoice? voice,
  Size size = const Size(393, 852),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final socket = _Socket();
  final gateway = HermesGateway(
    HermesEndpoint.tunnelled(token: 't', port: 9219),
    connector: (_) async => socket,
  );
  await gateway.connect();
  final workspace = Workspace(gateway);
  final opening = workspace.open('s1');
  await tester.pump();
  socket.reply('session.resume', {
    'session_id': 'live1',
    'resumed': 's1',
    'running': false,
    'info': {'model': 'm'},
    'messages': <Object>[],
  });
  final console = await opening;
  addTearDown(() {
    workspace.dispose();
    unawaited(gateway.dispose());
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConsoleView(
          workspace: workspace,
          console: console,
          media: media ?? FakeMedia(),
          voice: voice ?? FakeVoice(),
        ),
      ),
    ),
  );
  await tester.pump();
  return (socket, console);
}

Future<void> _pickTile(WidgetTester tester, String tile) async {
  await tester.tap(find.byTooltip('Attach something'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(tile));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

String _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

void main() {
  testWidgets('a photo from the camera rides along with the message', (
    tester,
  ) async {
    final media = FakeMedia(result: photoBytes());
    final (socket, _) = await _mount(tester, media: media);

    await _pickTile(tester, 'Photo');

    expect(media.calls, ['photo'], reason: 'the camera, not the library');

    // Nothing has left yet, and that is the point: picking a file is not
    // sending one. Uploading at pick-time meant the composer had to know how
    // a given backend takes a picture — and an attachment could not be taken
    // back, because by the time the chip appeared the server already had it.
    expect(socket.lastOf('image.attach_bytes'), isNull);

    // It is visible: an attachment that leaves no trace is one you cannot
    // tell you made.
    expect(find.text('IMG_0042.jpg'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'what is this');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pump();

    final call = socket.lastOf('image.attach_bytes');
    expect(call, isNotNull, reason: 'the bytes actually left for the server');
    expect(call!['params']['filename'], 'IMG_0042.jpg');

    socket.reply('image.attach_bytes', {'ok': true});
    await tester.pump();

    // And the prompt follows the picture, not the other way round: a message
    // that arrives first is answered without it.
    expect(socket.lastOf('prompt.submit')!['params']['text'], 'what is this');
    socket.reply('prompt.submit', {'ok': true});
    await tester.pump();

    // The chips describe what rode along with *that* message.
    expect(find.text('IMG_0042.jpg'), findsNothing);

    // Ends the turn, so the console's idle ticker stops.
    socket.event('message.complete', 'live1', const {});
    await tester.pump();
  });

  testWidgets('the library and the video tile use their own sources', (
    tester,
  ) async {
    final media = FakeMedia(result: photoBytes());
    await _mount(tester, media: media);

    await _pickTile(tester, 'Library');
    expect(media.calls, ['library'], reason: 'the library, not the camera');
  });

  testWidgets('backing out of the camera attaches nothing', (tester) async {
    // A refusal at the system prompt and a user tapping cancel are the same
    // thing here, and neither is an error worth a message.
    final media = FakeMedia();
    final (socket, _) = await _mount(tester, media: media);

    await _pickTile(tester, 'Photo');

    expect(media.calls, ['photo']);
    expect(socket.lastOf('image.attach_bytes'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a camera that throws says so instead of doing nothing', (
    tester,
  ) async {
    final media = FakeMedia(throws: Exception('no camera on this device'));
    await _mount(tester, media: media);

    await _pickTile(tester, 'Photo');
    await tester.pump();

    expect(find.textContaining('Could not attach'), findsOneWidget);
  });

  testWidgets('dictation types into the field', (tester) async {
    final voice = FakeVoice();
    // The dictation control lives in the desktop composer toolbar.
    await _mount(tester, voice: voice, size: const Size(1280, 800));

    await tester.tap(find.byTooltip('Dictate'));
    await tester.pump();
    expect(voice.starts, 1);

    // Partial results arrive as the whole phrase so far, not as deltas.
    voice.say('what is');
    await tester.pump();
    expect(_field(tester), 'what is');

    voice.say('what is the current model', finished: true);
    await tester.pump();
    expect(_field(tester), 'what is the current model');

    // Closed by the recogniser itself, so the button is back to offering.
    expect(find.byTooltip('Dictate'), findsOneWidget);
  });

  testWidgets('and keeps what was already typed', (tester) async {
    final voice = FakeVoice();
    // The dictation control lives in the desktop composer toolbar.
    await _mount(tester, voice: voice, size: const Size(1280, 800));

    await tester.enterText(find.byType(TextField).first, 'read the log and');
    await tester.tap(find.byTooltip('Dictate'));
    await tester.pump();

    voice.say('tell me what broke');
    await tester.pump();

    expect(_field(tester), 'read the log and tell me what broke');
  });

  testWidgets('tapping again stops it', (tester) async {
    final voice = FakeVoice();
    // The dictation control lives in the desktop composer toolbar.
    await _mount(tester, voice: voice, size: const Size(1280, 800));

    await tester.tap(find.byTooltip('Dictate'));
    await tester.pump();
    expect(find.byTooltip('Stop dictating'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop dictating'));
    await tester.pump();

    expect(voice.stops, 1);
    expect(find.byTooltip('Dictate'), findsOneWidget);
  });

  testWidgets('a refused microphone says so rather than looking broken', (
    tester,
  ) async {
    final voice = FakeVoice(available: false);
    // The dictation control lives in the desktop composer toolbar.
    await _mount(tester, voice: voice, size: const Size(1280, 800));

    await tester.tap(find.byTooltip('Dictate'));
    await tester.pump();

    expect(find.textContaining('not available'), findsOneWidget);
  });
}
