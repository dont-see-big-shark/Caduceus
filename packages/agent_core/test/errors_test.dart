import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  group('AgentException.retryable', () {
    // Loop over every failure so a newly added AgentFailure value forces this
    // test to be revisited rather than silently defaulting to false.
    for (final failure in AgentFailure.values) {
      test('for ${failure.name}', () {
        final exception = AgentException(failure);
        final expected = failure == AgentFailure.transient ||
            failure == AgentFailure.timeout ||
            failure == AgentFailure.disconnected;
        expect(exception.retryable, expected);
      });
    }
  });

  group('AgentException.needsApproval', () {
    for (final failure in AgentFailure.values) {
      test('for ${failure.name}', () {
        final exception = AgentException(failure);
        expect(exception.needsApproval, failure == AgentFailure.notPaired);
      });
    }
  });
}
