/// Choosing an agent, and what happens when it will not let you in yet.
///
/// Two failures this covers, and neither shows up as an exception. A saved
/// server written before there was more than one backend must keep working —
/// it has no `backend` field at all, and reading that as "unknown" would strand
/// every existing connection. And a device that authenticated correctly but is
/// not yet approved must not be reported as a failure: nothing is wrong,
/// retrying will not help, and only the device id moves it forward.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/connection_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a saved server remembers its agent', () {
    test('a record written before the field existed reads its URL', () {
      // Not all of them are Hermes: this app connected to an OpenClaw gateway
      // before the picker did, so one such record exists and treating every
      // old row as Hermes would send it down the wrong wire.
      final hermes = SavedConnection.fromJson(const {
        'id': '1',
        'label': 'old',
        'url': 'https://h:30190/proxy-path',
      });
      final claw = SavedConnection.fromJson(const {
        'id': '2',
        'label': 'nas',
        'url': 'wss://nas.example.ts.net/',
      });

      expect(hermes.backendId, SavedConnection.hermes);
      expect(claw.isOpenClaw, isTrue);
      // Hermes' own field asks for https and reads a bare host as https, so
      // that is the side a scheme-less URL falls on.
      expect(SavedConnection.backendForUrl('h:30190'), SavedConnection.hermes);
    });

    test('a recorded backend outranks the guess', () {
      // The inference is for legacy rows only. Once a connection has been used
      // through the picker the answer is written down, and a URL that looks
      // like the other backend must not override it.
      final saved = SavedConnection.fromJson(const {
        'id': '3',
        'url': 'wss://looks-like-openclaw/',
        'backend': SavedConnection.hermes,
      });

      expect(saved.backendId, SavedConnection.hermes);
    });

    test('a row can say which agent it will reach', () {
      // Shown because a guessed backend should be visible before the row is
      // pressed rather than after it fails.
      expect(
        SavedConnection.fromJson(const {
          'id': '4',
          'url': 'wss://nas/',
        }).backendLabel,
        'OpenClaw',
      );
      expect(
        SavedConnection.fromJson(const {
          'id': '5',
          'url': 'https://h/',
        }).backendLabel,
        'Hermes',
      );
    });

    test('an OpenClaw record round-trips through storage', () {
      final saved = SavedConnection.fromJson(
        const SavedConnection(
          id: '2',
          label: 'nas',
          url: 'wss://nas/',
          backendId: SavedConnection.openclaw,
        ).toJson(),
      );

      expect(saved.isOpenClaw, isTrue);
      expect(saved.url, 'wss://nas/');
    });

    test('the id matches what a backend calls itself', () {
      // Not decoration: the stored string is compared against AgentBackend.id
      // when a connection is reopened, and a drift between them would send
      // every OpenClaw server down the Hermes path.
      expect(SavedConnection.hermes, 'hermes');
      expect(SavedConnection.openclaw, 'openclaw');
    });
  });

  group('awaiting approval is a state, not a failure', () {
    test('it is neither connected nor settling nor fatal', () {
      const waiting = AgentConnection(AgentStatus.awaitingApproval);

      expect(waiting.needsApproval, isTrue);
      expect(waiting.isConnected, isFalse);
      // Not settling: a progress spinner promises something is happening, and
      // nothing is until a human acts somewhere else.
      expect(waiting.isSettling, isFalse);
      expect(waiting.status, isNot(AgentStatus.fatal));
    });

    test('the failure that means it is classified apart from a bad token', () {
      final notPaired = AgentException(AgentFailure.notPaired);
      final unauthorized = AgentException(AgentFailure.unauthorized);

      expect(notPaired.needsApproval, isTrue);
      // Emphatically not retryable: retrying is exactly the wrong advice, and
      // prompting for another credential sends the user after a fault that
      // does not exist.
      expect(notPaired.retryable, isFalse);
      expect(unauthorized.needsApproval, isFalse);
    });
  });
}
