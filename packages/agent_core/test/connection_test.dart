import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  group('AgentConnection', () {
    // Loop over every status so a newly added AgentStatus value forces this
    // test to be revisited rather than silently defaulting to false.
    for (final status in AgentStatus.values) {
      test('flags for ${status.name}', () {
        final connection = AgentConnection(status);
        expect(connection.isConnected, status == AgentStatus.connected);
        expect(
          connection.isSettling,
          status == AgentStatus.connecting ||
              status == AgentStatus.reconnecting,
        );
        expect(
          connection.needsApproval,
          status == AgentStatus.awaitingApproval,
        );
      });
    }
  });
}
