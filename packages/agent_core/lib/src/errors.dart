/// What goes wrong, in terms a UI can act on.
library;

/// Why a backend call failed.
///
/// Deliberately small. The point of the enum is that each case implies a
/// *different thing for the user to do*: fix a credential, wait, get someone
/// to approve a device, or nothing at all. A code that does not change what
/// the user should do does not belong here — it belongs in [AgentException.
/// detail], which is shown and never switched on.
enum AgentFailure {
  /// The connection is not up. Retrying after it comes back will work.
  disconnected,

  /// The credential was wrong or missing. Only a new credential fixes it.
  unauthorized,

  /// Authenticated, but this device is not approved. Only a human elsewhere
  /// fixes it — and this is emphatically *not* [unauthorized], because
  /// prompting for another token would send the user hunting for a problem
  /// that does not exist.
  notPaired,

  /// The server understood and refused: no permission, wrong scope.
  forbidden,

  /// The session or resource is gone.
  notFound,

  /// The server said no in a way that is worth retrying — rate limit,
  /// overload. [AgentException.retryAfter] says when, if it said.
  transient,

  /// The call did not come back in time.
  timeout,

  /// The backend does not do this. Should be unreachable through a
  /// capability-gated UI; it exists so that "unreachable" is enforced rather
  /// than assumed.
  unsupported,

  /// Everything else.
  unknown,
}

/// A failure from a backend, already classified.
///
/// Adapters translate their protocol's error vocabulary into this — Hermes'
/// numeric JSON-RPC codes and OpenClaw's string codes both land here — so the
/// UI never sees a wire code and never grows a `switch` over one backend's
/// spelling.
class AgentException implements Exception {
  AgentException(
    this.failure, {
    this.detail = '',
    this.code = '',
    this.retryAfter,
    this.cause,
  });

  final AgentFailure failure;

  /// Shown to the user. The server's own words where they are worth reading.
  final String detail;

  /// The backend's raw code, for logs and bug reports. Never switched on
  /// outside the adapter that produced it.
  final String code;

  /// How long to wait before retrying, when the server said.
  final Duration? retryAfter;

  final Object? cause;

  /// Worth trying again without the user changing anything.
  bool get retryable =>
      failure == AgentFailure.transient ||
      failure == AgentFailure.timeout ||
      failure == AgentFailure.disconnected;

  /// Waiting is the only thing that helps, and the wait is on a human.
  bool get needsApproval => failure == AgentFailure.notPaired;

  @override
  String toString() => 'AgentException(${failure.name}'
      '${code.isEmpty ? '' : ' $code'}'
      '${detail.isEmpty ? '' : ': $detail'})';
}
