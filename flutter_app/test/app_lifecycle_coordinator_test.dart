/// App resume behaviour, tested through the coordinator's public interface.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/agent_tabs.dart';
import 'package:caduceus/app_lifecycle_coordinator.dart';
import 'package:caduceus/connection_store.dart';
import 'package:caduceus/design/tokens.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

class _ResumeBackend implements AgentBackend {
  _ResumeBackend(this.id, {required this.aliveOnResume, this.resumeOrder});

  @override
  final String id;

  final bool aliveOnResume;
  final List<String>? resumeOrder;
  final verifies = <String>[];
  final connects = <String>[];
  final sessionReads = <String>[];

  @override
  String get displayName => id;

  @override
  Future<void> connect() async {
    connects.add(id);
    resumeOrder?.add('connect $id');
  }

  @override
  Future<bool> verifyConnection() async {
    verifies.add(id);
    resumeOrder?.add('verify $id');
    return aliveOnResume;
  }

  @override
  Future<void> dispose() async {}

  @override
  AgentConnection get connectionState => AgentConnection.disconnected;

  @override
  Stream<AgentConnection> get connection => const Stream.empty();

  @override
  Stream<AgentSession> get sessionUpdates => const Stream.empty();

  @override
  Future<List<AgentSession>> sessions({int limit = 50}) async {
    sessionReads.add(id);
    resumeOrder?.add('sessions $id');
    return const [];
  }

  @override
  bool supports(Capability capability) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

SavedConnection _connection(String id) =>
    SavedConnection(id: id, label: id, url: 'wss://$id.test');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ambient motion', () {
    setUp(() => Materials.ambientPaused.value = false);

    test('inactive pauses decoration without scheduling recovery', () async {
      final coordinator = AppLifecycleCoordinator(AgentTabs());
      addTearDown(coordinator.dispose);

      await coordinator.handleLifecycleChange(AppLifecycleState.inactive);
      expect(Materials.ambientPaused.value, isTrue);

      await coordinator.handleLifecycleChange(AppLifecycleState.resumed);
      expect(Materials.ambientPaused.value, isFalse);
    });

    test(
      'leaving the foreground restores the previous setting on return',
      () async {
        final coordinator = AppLifecycleCoordinator(AgentTabs());
        addTearDown(coordinator.dispose);

        await coordinator.handleLifecycleChange(AppLifecycleState.hidden);
        expect(Materials.ambientPaused.value, isTrue);

        await coordinator.handleLifecycleChange(AppLifecycleState.resumed);
        expect(Materials.ambientPaused.value, isFalse);
      },
    );

    test('dispose restores motion it paused', () async {
      final coordinator = AppLifecycleCoordinator(AgentTabs());

      await coordinator.handleLifecycleChange(AppLifecycleState.paused);
      expect(Materials.ambientPaused.value, isTrue);

      coordinator.dispose();
      expect(Materials.ambientPaused.value, isFalse);
    });
  });

  group('connection recovery', () {
    test('the active tab is recovered before background tabs', () async {
      final resumeOrder = <String>[];
      final first = _ResumeBackend(
        'first',
        aliveOnResume: true,
        resumeOrder: resumeOrder,
      );
      final second = _ResumeBackend(
        'second',
        aliveOnResume: true,
        resumeOrder: resumeOrder,
      );
      final tabs = AgentTabs();
      addTearDown(tabs.dispose);

      await tabs.adopt(
        connection: _connection('first'),
        workspace: Workspace.forBackend(first),
        backend: first,
      );
      await tabs.adopt(
        connection: _connection('second'),
        workspace: Workspace.forBackend(second),
        backend: second,
      );
      tabs.setActive(0);

      final coordinator = AppLifecycleCoordinator(tabs);
      addTearDown(coordinator.dispose);
      await coordinator.handleLifecycleChange(AppLifecycleState.hidden);
      await coordinator.handleLifecycleChange(AppLifecycleState.resumed);

      expect(resumeOrder, [
        'verify first',
        'sessions first',
        'verify second',
        'sessions second',
      ]);
      expect(first.verifies, ['first']);
      expect(second.verifies, ['second']);
      expect(first.verifies.length + second.verifies.length, 2);
      expect(first.sessionReads, ['first']);
      expect(second.sessionReads, ['second']);
    });

    test('a live connection is refreshed without being replaced', () async {
      final backend = _ResumeBackend('active', aliveOnResume: true);
      final tabs = AgentTabs();
      addTearDown(tabs.dispose);
      await tabs.adopt(
        connection: _connection('active'),
        workspace: Workspace.forBackend(backend),
        backend: backend,
      );

      final coordinator = AppLifecycleCoordinator(tabs);
      addTearDown(coordinator.dispose);
      await coordinator.handleLifecycleChange(AppLifecycleState.hidden);
      await coordinator.handleLifecycleChange(AppLifecycleState.resumed);

      expect(backend.verifies, ['active']);
      expect(backend.connects, isEmpty);
      expect(backend.sessionReads, ['active']);
    });

    test('a dead connection is verified, reconnected and reconciled', () async {
      final backend = _ResumeBackend('active', aliveOnResume: false);
      final tabs = AgentTabs();
      addTearDown(tabs.dispose);
      await tabs.adopt(
        connection: _connection('active'),
        workspace: Workspace.forBackend(backend),
        backend: backend,
      );

      final coordinator = AppLifecycleCoordinator(tabs);
      addTearDown(coordinator.dispose);
      await coordinator.handleLifecycleChange(AppLifecycleState.paused);
      await coordinator.handleLifecycleChange(AppLifecycleState.resumed);

      expect(backend.verifies, ['active']);
      expect(backend.connects, ['active']);
      expect(backend.sessionReads, ['active']);
    });
  });
}
