/// `Workspace.skillView` — how the bridge assembles the cross-agent library.
///
/// Same two claims as the memory view, for skills: a connected backend whose
/// read fails is reported, not hidden, and an already-open tab is asked
/// directly instead of the pool paying a second handshake (and, on OpenClaw,
/// a second pairing).
library;

import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBackend implements AgentBackend {
  _FakeBackend({
    this.id = 'hermes',
    this.displayName = 'Hermes',
    this.libraryThrows,
    List<SkillEntry>? entries,
  }) : _entries = entries ?? [];

  @override
  final String id;
  @override
  final String displayName;
  final Object? libraryThrows;
  final List<SkillEntry> _entries;

  @override
  bool supports(Capability capability) => capability == Capability.skills;

  @override
  Future<List<SkillEntry>> skillLibrary() async {
    final error = libraryThrows;
    if (error != null) throw error;
    return List.of(_entries);
  }

  @override
  AgentConnection get connectionState => AgentConnection.disconnected;
  @override
  Stream<AgentConnection> get connection => const Stream.empty();
  @override
  Stream<AgentSession> get sessionUpdates => const Stream.empty();
  @override
  Future<void> connect() async {}
  @override
  Future<void> dispose() async {}

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

SkillEntry _skill(String key, String backend) =>
    SkillEntry(key: key, title: key, backendId: backend, nativeId: key);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'a connected backend that fails to read is unreachable, not absent',
    () async {
      final backend = _FakeBackend(libraryThrows: StateError('boom'));

      final view = await Workspace.forBackend(backend).skillView();

      expect(view.unreachable.containsKey('hermes'), isTrue);
      expect(view.unreachable['hermes'], isNotEmpty);
      // A failed read is not a skill the agent lacks.
      expect(view.liveBackendIds, isEmpty);
      expect(view.isEmpty, isTrue);
    },
  );

  test(
    'an already-open tab is asked directly; the pool does not reopen it',
    () async {
      final hermes = _FakeBackend(
        id: 'hermes',
        entries: [_skill('tavily', 'hermes')],
      );
      final openclaw = _FakeBackend(
        id: 'openclaw',
        displayName: 'OpenClaw',
        entries: [_skill('tavily', 'openclaw')],
      );
      // The OpenClaw server is saved, so without the peers exclusion the pool
      // would reopen it — a second socket, and on OpenClaw a second pairing.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.connections.v1': jsonEncode([
          {
            'id': 'openclaw-saved',
            'label': 'OpenClaw',
            'url': 'wss://fnos.example',
            'backend': 'openclaw',
          },
        ]),
      });

      final view = await Workspace.forBackend(hermes).skillView(
        reachOut: true,
        peers: MemoryPeers(
          backends: {openclaw.id: openclaw},
          openConnectionIds: const {'openclaw-saved'},
        ),
      );

      expect(view.liveBackendIds, containsAll({'hermes', 'openclaw'}));
      // One cluster: both agents carry the same skill.
      expect(view.clusters, hasLength(1));
      expect(view.clusters.single.isShared, isTrue);
      expect(view.unreachable, isEmpty);
    },
  );
}
