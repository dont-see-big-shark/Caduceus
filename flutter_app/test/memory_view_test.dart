/// `Workspace.memoryView` — how the bridge assembles the view.
///
/// Two claims worth pinning, both about not lying: a connected backend whose
/// read fails must appear in the unreachable banner rather than masquerading
/// as a stale snapshot, and an already-open tab is asked directly instead of
/// the pool paying a second handshake (and, on OpenClaw, a second pairing).
library;

import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/memory_ledger.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBackend implements AgentBackend {
  _FakeBackend({
    this.id = 'hermes',
    this.displayName = 'Hermes',
    this.memoryThrows,
    List<MemoryEntry>? entries,
  }) : _entries = entries ?? [];

  @override
  final String id;
  @override
  final String displayName;
  final Object? memoryThrows;
  final List<MemoryEntry> _entries;

  @override
  bool supports(Capability capability) => true;

  @override
  Future<List<MemoryEntry>> memory() async {
    final error = memoryThrows;
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

MemoryEntry _entry(String backend, String native, String text) => MemoryEntry(
  id: '$backend:$native',
  kind: MemoryKind.fact,
  title: 'Coffee',
  text: text,
  origin: MemoryOrigin(backendId: backend, nativeId: native),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'a connected backend that fails to read is unreachable, not stale',
    () async {
      final backend = _FakeBackend(memoryThrows: StateError('boom'));
      // The ledger holds a snapshot, so the view is not empty — but the chip
      // must not be the whole story.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'memory.snapshots.v1': jsonEncode([
          MemorySnapshot(
            backendId: 'hermes',
            entries: [_entry('hermes', 'memory:1', 'Likes black coffee.')],
            readAt: DateTime.now(),
          ).toJson(),
        ]),
      });

      final view = await Workspace.forBackend(backend).memoryView();

      expect(view.unreachable.containsKey('hermes'), isTrue);
      expect(view.unreachable['hermes'], isNotEmpty);
      // The cached copy is still shown, labelled with its age — the failure is
      // reported, not hidden by pretending the snapshot is current.
      expect(view.sources.containsKey('hermes'), isTrue);
      expect(view.sources['hermes'], isNotNull);
    },
  );

  test(
    'an already-open tab is asked directly; the pool does not reopen it',
    () async {
      final hermes = _FakeBackend(
        id: 'hermes',
        displayName: 'Hermes',
        entries: [_entry('hermes', 'memory:1', 'Likes black coffee.')],
      );
      final openclaw = _FakeBackend(
        id: 'openclaw',
        displayName: 'OpenClaw',
        entries: [
          _entry('openclaw', 'MEMORY.md#coffee', 'Likes black coffee.'),
        ],
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

      final view = await Workspace.forBackend(hermes).memoryView(
        reachOut: true,
        peers: MemoryPeers(
          backends: {openclaw.id: openclaw},
          openConnectionIds: const {'openclaw-saved'},
        ),
      );

      expect(view.liveBackendIds, containsAll({'hermes', 'openclaw'}));
      // Nothing was tried and failed: the tab answered, and the saved server
      // behind it was excluded from the pool.
      expect(view.unreachable, isEmpty);
    },
  );
}
