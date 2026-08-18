# Supporting more than one agent

Caduceus talks to Hermes Agent. This is the plan for it to talk to OpenClaw,
Pi, and whatever comes next, without becoming a lowest-common-denominator
client for all of them.

Written against **measured** coupling in this repo and the **published**
OpenClaw gateway protocol (v4). Everything below marked ⚠ is a genuine
unknown, not a detail left for later — those are the things to settle before
writing the code they affect.

---

## 1. Where we actually are

The coupling is much better than the import count suggests. 18 of 39 files in
`flutter_app/lib` import `hermes_protocol`, but they do not import the same
things, and the difference is the whole design.

| Group | Files | What they use | Verdict |
|---|---|---|---|
| **Core** | `workspace.dart` (1644 lines) | 33 gateway methods, 7 event types, `HermesConsole`, `GatewayEvent` | This is the only real coupling |
| **Feature panels** | `agents`, `processes`, `checkpoints`, `journey`, `jobs`, `projects`, `server` | `HermesGateway` and nothing else — each makes its own bespoke RPCs | Not core. Capability-gated |
| **Views** | `session_row`, `session_drawer`, `workspace_screen`, `inline_prompt`, `turn_timeline`, `console_view` | `SessionSummary`, `BlockingPrompt` only — pure data | Needs neutral models, no transport |
| **Connect** | `connect_screen` | `HermesEndpoint`, `HermesGateway` construction | Needs a backend registry |
| **Models** | `model_sheet.dart` | `ModelInventory` only | Needs a neutral model type |

So: **one file to abstract, eight to gate, seven to re-type.** Not a rewrite.

(That table is measured, and one row of it was wrong on the first pass: a
symbol grep said `model_sheet.dart` imported nothing it used, and deleting the
import broke the build on `ModelInventory`. Counting imports is not the same as
counting coupling, which is the reason this section exists at all.)

`packages/hermes_protocol` is 4208 lines across 9 files and already has a clean
seam — `GatewayTransport` (109 lines) is an interface the tests already fake.
That is the layer OpenClaw slots in beside, not inside.

---

## 2. What OpenClaw actually is

Verified from the published protocol docs, not assumed.

- WebSocket, default `ws://127.0.0.1:18789`, JSON text frames, **protocol v4**,
  200+ RPC methods.
- **Not JSON-RPC 2.0.** Its own envelope:
  - request `{type:"req", id, method, params, traceparent?}`
  - response `{type:"res", id, ok:true, payload}` / `{type:"res", id, ok:false, error}`
  - event `{type:"event", event, payload, seq, stateVersion}`
- **Challenge-response handshake.** Server pushes `connect.challenge`
  `{nonce, ts}`; client sends `connect` with `device.nonce` / `device.signedAt`;
  server answers `hello-ok` with `protocol`, `auth.scopes`, `policy.maxPayload`.
- Errors are **string codes** with `retryable` and `retryAfterMs`; authz
  failures are `FORBIDDEN` + `details.code:"MISSING_SCOPE"`.
- Streaming: `agent` events carry **`deltaText`**, and `message` is the
  **cumulative snapshot**.
- Sessions: `sessions.create`, `sessions.send`, `sessions.subscribe` /
  `sessions.unsubscribe`, `sessions.messages.subscribe`, `chat.send`,
  `chat.abort`, `sessions.abort`.
- **Idempotency keys required** on side-effecting methods.
- 30 s RPC timeout; silence past `tickIntervalMs * 2` closes with code `4000`;
  25 MB payload cap, 6 MB for images.
- Approvals exist: `exec.approval.resolve` resolves a pending tool execution
  with allow/deny.
- `@openclaw/gateway-protocol` publishes `protocol.schema.json` — a
  machine-readable contract we should generate Dart types from rather than
  hand-writing.

### The handshake, established against a live gateway

None of this is in the published docs. It was derived by connecting to a real
server and reading its rejections until they stopped, and it is now implemented
and pinned in `packages/openclaw_protocol`.

- The WebSocket is at the **root path**. `/health` is the only HTTP endpoint;
  everything else answers 404 while the same URL upgrades to a socket. Note
  that `curl` must be forced to HTTP/1.1 — HTTP/2 has no `Upgrade`, so an
  upgrade probe over h2 looks like a 404 and sends you hunting for a path that
  was never wrong.
- `client.mode` is a closed set: **`cli`, `ui`, `node`**. Not `operator`, not
  `desktop`, not `web`.
- `role` is a *separate* closed set: **`operator`, `node`**. Sending a mode as
  a role answers `invalid role`.
- `client.id` is also closed. `cli`, `gateway-client` and `test` are accepted.
- `device.id` = **hex SHA-256 of the raw 32-byte Ed25519 public key**. Anything
  else — including a truncated hash — answers
  `DEVICE_AUTH_DEVICE_ID_MISMATCH`.
- `device.publicKey` and `device.signature` are **unpadded base64url**.
- The signature covers
  `v3|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce|platform|deviceFamily`,
  compared byte for byte. Empty fields keep their pipes; `platform` and
  `deviceFamily` are lowercased and nothing else is.
- **The token is inside the signed payload** (field 8). A client that picks its
  credential after signing sends a good signature over the wrong string, and
  the gateway reports it as a *device identity* problem — which is a
  thoroughly misleading place to begin debugging.

### The four questions, answered

These were marked ⚠ for months because the published `@openclaw/gateway-protocol`
package is a `0.0.0` placeholder and the docs do not cover them. They are now
answered from the gateway that is actually installed — openclaw **2026.7.1-2**,
whose `dist/` ships the TypeBox schemas and whose `docs/gateway/protocol.md` is
the real reference. All four are **yes**:

1. **History.** `chat.history` exists, and is *display-normalised* for UI
   clients: the gateway strips inline directive tags and leaked tool-call XML,
   drops silent-token rows, and replaces an oversized message with a
   placeholder. So a client gets the readable transcript rather than the raw
   one, which is what a transcript view wants. `chat.message.get` fetches one
   entry in full when a row was truncated.
2. **Tool-call events.** The `session.tool` family, alongside
   `session.message` (transcript) and `session.operation` (compaction).
3. **Model selection per session.** `sessions.patch` carries per-session
   `model`, `thinkingLevel`, `fastMode`, `reasoning` and more, and reports the
   canonical model it resolved to.
4. **Reasoning deltas.** Not a separate channel: reasoning is a per-session
   *override* and a content part, not a second stream beside the answer.

Two more things fell out of the same reading, and both matter more than the
answers did.

**`sessions.subscribe` does not deliver messages.** It toggles session-*index*
events — rows appearing, titles changing. A transcript arrives only on
`sessions.messages.subscribe`. A client that calls the first and not the second
connects, lists, sends a prompt, and then waits forever for a reply on a
channel it never opened. This is the single worst failure shape in the whole
protocol, because it is indistinguishable from a hung agent, and no test
against a fake socket can find it.

**A session's identity is its `key`.** Replies also carry a `sessionId`, which
is the transcript file's id. Keying anything on that gets a well-formed request
rejected as a session that does not exist.

### What this cost, and the lesson

Five parameter-level bugs, all of them in code that passed its tests:
`sessions.send` wanted `key`/`message` and was sent `sessionId`/`text`;
`sessions.abort` was `chat.abort`; `sessions.create` was sent a `cwd` and an
idempotency key it does not accept; `exec.approval.resolve` was sent a
`requestId`; and there is no `sessions.recent` at all.

The schemas are declared `additionalProperties: false`, so none of these would
have been loosely tolerated — each fails the whole request. And a fake-socket
test cannot catch any of them, because it asserts what the client *sent*, never
what a server would have *accepted*.

The lesson is narrower than "test against a real server", which was already
known and is blocked on pairing. It is this: **a protocol client's contract is
the server's schema, and if the schema is readable at all, reading it beats
inferring it** — including inferring it from a server's error messages, which
is how the handshake was won and which stops working the moment a request is
well-formed enough to be accepted for the wrong reasons.

---

## 2b. What only a live gateway could teach

The schemas answered what a request must look like. They do not describe
runtime shapes, and everything below was wrong until a real frame arrived.

**The turn never ended.** A reply streamed correctly and then hung until the
client's own timeout — indistinguishable, on screen, from an agent that has
stopped responding. There is no `chat.done` and no `final: true`: a turn ends
with an event named `chat` carrying `state: "final"` and a `stopReason`
beside it. The same event with `state: "delta"` is what carries `deltaText`.

**A message's content is an array of typed parts, not a string.** `text`,
`thinking` and `textSignature` travel side by side, and the gateway's own
schema types the whole thing `unknown`. Read as a string it renders as the
Dart source of the array, signature blobs and all.

**A tool call arrives three times per phase.** Once as the tool, and twice
more as rows for the gateway's own activity list, tagged `itemId: tool:…` and
`itemId: command:…`. A client that takes all three renders every call three
times. `update` and `delta` also carry the same bytes, so forwarding both
prints a tool's output twice.

**A stored transcript records a tool call as two rows** — the assistant asking
for it, then a `toolResult` — and `toolResult` is not a role any client would
guess. Fall through to the unrecognised-role path and a command's raw output
renders as an italic aside from the server, which is a claim about who said it.

**`sessions.list` reports no message count and no title.** A count of zero is a
wrong answer rather than a missing one, and a row's identity is a routing
address that identifies nothing to a reader. `includeDerivedTitles` and
`includeLastMessage` are what make a sidebar readable; they cost a file read
per session, which is why they travel with the limit that bounds them.

**Session labels are unique per gateway**, and reusing one answers
`INVALID_REQUEST: label already in use` — a create that reads like a client
bug and is a naming collision.

**Asking for no scopes pairs a device that can do nothing.** The approval is
spent by the time the first `sessions.list` comes back `FORBIDDEN`.

### The general shape of it

Every one of these is a *runtime* fact, and the schema — which was decisive for
the request side — says nothing about any of them. So the rule from §2 needs
its other half:

> Read the schema for what you send. Watch the wire for what you get.

Neither substitutes for the other. A fake socket asserts what the client sent
and can never catch a wrong parameter name; a live gateway shows the shapes
arriving and never tells you which of the fields you sent were ignored.

---

## 3. The six differences that shape the design

Naming differences are trivial. These are not.

| # | Hermes | OpenClaw | Consequence |
|---|---|---|---|
| 1 | Pushes every event for every session | Explicit `sessions.subscribe` per session | The interface needs a real subscribe lifecycle; Hermes implements it as a no-op |
| 2 | No ordering exposed | `seq` + `stateVersion` on every event | Carry an **opaque resume cursor**; only the adapter knows what it means |
| 3 | No idempotency | Required on mutations | `send()` takes a **client-generated id**, always — Hermes ignores it |
| 4 | Delta only | Delta **and** cumulative snapshot | Model on **delta**, with optional snapshot reconciliation. Delta→snapshot is trivial; snapshot→delta needs diffing |
| 5 | Token in the URL | Challenge-response, device identity | Auth lives **behind** the backend, not in an endpoint value type |
| 6 | Checkpoints, cron, journey, projects | Channels, multi-chat-app bridging | A universal interface would force each backend to stub the other's seven features |

Difference 6 is the one that decides the architecture.

---

## 4. The principle: a narrow core, and capabilities beside it

The tempting design is one big `AgentBackend` with 40 methods. It is wrong:
every backend would implement seven features it does not have by throwing
`UnimplementedError`, and the UI would offer buttons that fail.

This codebase already has the rule, from the attachment sheet:

> **a menu item that fails is worse than one that is absent.**

So:

- **The core is what every agent must do**: connect, list sessions, open one,
  send a message, stream a reply, stop a turn, answer a blocking question.
  Seventeen members as it stands. A backend that cannot do these is not an
  agent client. (It began as "roughly 12"; the subsection below explains what
  grew and against which test.)
- **Everything else is a capability**, declared by the backend and *asked for*
  by the UI. Checkpoints, cron, projects, browser control, channels.
  Not supported → the surface is not built. No stubs, no dead buttons.

```dart
if (backend.supports(Capability.checkpoints)) ... // else the menu item is absent
```

This is the same shape as `MediaCapture.hasCamera` already in the app: macOS
has no camera, so the tile is not there.

### The core did not stay at twelve, and that is worth explaining

This section originally said "roughly 12 methods". The seam is now 17 core
members plus 15 gated ones. Nothing was smuggled in — every addition passed
the same two tests, and writing them down is more useful than pretending the
number held:

1. **Both backends can serve it**, with a *neutral* shape that does not
   describe one in the other's vocabulary. `AgentJob.schedule` is free text
   precisely because OpenClaw's schedule is a tagged union of four kinds and
   Hermes' is a cron string; forcing either into the other's model would lose
   what that server can actually express.
2. **The shape does not lie about either.** This is the test that keeps
   producing *pairs* of capabilities rather than one: `serverConfig` /
   `serverMaintenance`, `cron` / `cronEditing`, `memoryRead` / `memoryWrite`.
   In each case OpenClaw serves the read at `operator.read` and the write at
   `operator.admin`, so a single capability would have offered a button that
   could only be refused.

The rule the growth respects is not a method count. It is that **a backend
never implements something by throwing**, and the UI never offers a surface
its backend cannot serve. A seam of 32 honest members is better than one of 12
with `UnimplementedError` behind half the panels — which is what the original
alternative actually was, since those panels existed either way and simply
held a `HermesGateway` directly instead.

The count to watch is not the seam's; it is the number of capabilities that
gate a *single control* rather than a whole surface. That number is still
zero, and it is the one that must stay there.

---

## 5. The layers

```
┌───────────────────────────────────────────────────────────┐
│  UI            console_view, drawer, settings, panels     │
│                knows: domain models + Capability          │
├───────────────────────────────────────────────────────────┤
│  Workspace     session list, active console, turn assembly│
│                knows: AgentBackend. No protocol at all.   │
├───────────────────────────────────────────────────────────┤
│  AgentBackend  ← the seam. 17 core + 15 gated methods     │
├──────────────┬──────────────┬─────────────────────────────┤
│ HermesBackend│ClawBackend   │ PiBackend …                 │
│ (adapter)    │(adapter)     │                             │
├──────────────┼──────────────┼─────────────────────────────┤
│hermes_protocol│openclaw_protocol│ …                        │
│ JSON-RPC 2.0 │ type:req/res │                             │
└──────────────┴──────────────┴─────────────────────────────┘
```

New packages, mirroring the existing one:

```
packages/agent_core/        domain models + AgentBackend + Capability
packages/hermes_protocol/   unchanged wire client (already exists)
packages/openclaw_protocol/ new wire client, types generated from schema
flutter_app/lib/backends/   HermesBackend, ClawBackend — the adapters
```

`agent_core` depends on nothing but `meta`. The protocol packages do not know
about `agent_core`; the **adapters** map between them. That keeps the wire
clients independently testable and stops domain concepts leaking into either
protocol.

---

## 6. The core interface

**This is now built** — `packages/agent_core/lib/src/backend.dart` is the real
thing and the sketch below is what it grew from. Two adapters implement it, and
the differences between what is sketched here and what shipped are worth
knowing, because each was found by writing the second adapter rather than by
thinking harder about the first:

  * `respond(PromptId, PromptAnswer)` kept its signature, but only because both
    adapters remember what they raised. Hermes needs to know which of three
    `*.respond` methods a question belongs to and answers approvals against the
    session id; OpenClaw needs an idempotency key. Neither is knowable from an
    id and an answer, and pushing that back onto callers would have leaked both
    protocols into the UI.
  * `PromptAnswer` exists rather than a bare `String` so that an answer which
    must not be logged is *distinguishable* at the point something is about to
    log it. Its `toString` reports a length and never the value.
  * A `connectionState` getter sits beside the `connection` stream, and the
    stream replays its current value. A late subscriber staring at a blank
    status is a bug both adapters would otherwise have had.
  * `TextReset` joined the event hierarchy for reconciliation, and a snapshot
    that merely *extends* what was accumulated is deliberately not a
    disagreement — it arrived ahead of the delta completing it.

The original sketch follows. Every choice in it is forced by a row in §3.

```dart
/// What every agent backend must do.
abstract interface class AgentBackend {
  /// Connect and authenticate. Whatever that means here — a token in a URL,
  /// a challenge-response handshake, an OAuth dance — stays inside.
  Future<void> connect();
  Future<void> dispose();

  Stream<ConnectionState> get connection;

  /// Ordered by last activity, newest first.
  Future<List<AgentSession>> sessions({int limit});

  /// Opens a session and begins receiving its events.
  ///
  /// Returns a handle because the durable id and the live id are not the same
  /// thing on either backend — Hermes returns a gateway handle plus a stored
  /// id; OpenClaw subscribes per session. Callers hold the handle.
  Future<SessionHandle> open(String sessionId);
  Future<SessionHandle> create({String? title, String? cwd});

  /// Stops delivery for one session. A no-op where the server pushes
  /// everything regardless (Hermes); a real `sessions.unsubscribe` on
  /// OpenClaw, which otherwise keeps streaming a conversation nobody is
  /// looking at.
  Future<void> release(SessionHandle handle);

  /// Prior messages. Null capability means a resumed session starts blank,
  /// and the UI must say so rather than looking empty.
  Future<List<AgentMessage>> history(SessionHandle handle);

  /// [clientId] is the idempotency key. Generated by the caller, always, even
  /// where the backend ignores it — a key invented inside the adapter cannot
  /// survive the retry it exists for.
  Future<void> send(
    SessionHandle handle,
    String text, {
    required String clientId,
    List<Attachment> attachments,
  });

  Future<void> interrupt(SessionHandle handle);

  /// Approvals, clarifications, secrets — anything that blocks a turn.
  Future<void> respond(PromptId id, PromptAnswer answer);

  /// Everything the server says, already normalised.
  Stream<AgentEvent> events(SessionHandle handle);

  bool supports(Capability capability);
}
```

### The event model

One sealed hierarchy, delta-shaped (difference 4):

```dart
sealed class AgentEvent {
  /// Opaque. Hermes has nothing to put here; OpenClaw puts seq/stateVersion.
  /// The adapter is the only thing that may interpret it.
  final ResumeCursor? cursor;
}

final class TurnStarted    extends AgentEvent {}
final class TextDelta      extends AgentEvent { final String text; }
final class ReasoningDelta extends AgentEvent { final String text; }
final class ToolStarted    extends AgentEvent { final ToolCall call; }
final class ToolProgress   extends AgentEvent { … }
final class ToolFinished   extends AgentEvent { final ToolResult result; }
final class PromptRaised   extends AgentEvent { final BlockingPrompt prompt; }
final class PromptExpired  extends AgentEvent { final PromptId id; }
final class TurnFinished   extends AgentEvent { final FinishReason reason; }
final class SessionChanged extends AgentEvent { final AgentSession session; }
final class BackendNotice  extends AgentEvent { final String text; }
```

`BackendNotice` is deliberate: every backend will have events the domain has
no concept for, and the choice is between dropping them silently and showing
them as what they are. Hermes' `model_switch` markers already live in this
grey zone.

**Snapshot reconciliation.** OpenClaw sends both `deltaText` and a cumulative
`message`. The adapter emits deltas and, on each snapshot, checks that its
accumulated text matches. On divergence it emits a `TextReset` rather than
guessing — a transcript that silently drifts from the server's is worse than a
visible correction.

### Capabilities

```dart
enum Capability {
  history, reasoningStream, toolCalls, approvals,
  modelSwitching, modelProviders, sessionBranching, checkpoints,
  transcriptUndo, usageReporting, subagents, learning, cron,
  backgroundProcesses, projects, skills, fileAttach, imageAttach,
  cwdControl, channels,
}
```

`modelProviders` is the one worth explaining: it is *not* a stronger
`modelSwitching`. They are different surfaces. A backend can offer a flat
catalog of models it already has credentials for without offering anywhere to
put an API key, and gating the provider dialog on the plain capability asked
such a backend about keys it has no concept of. When a capability starts
meaning "and also the richer version of that", it is two capabilities.

Each of the seven feature panels becomes gated on one of these.
`journey_panel` is Hermes-only and will simply not exist on OpenClaw — which is
correct, and is why it must not be in the core interface.

---

## 7. Concept mapping

| Domain | Hermes | OpenClaw | Note |
|---|---|---|---|
| connect | token in WS URL | `connect.challenge` → `connect` → `hello-ok` | device key persisted per saved server |
| sessions | `session.list` | `sessions.list` | keyed on `key`, not the `sessionId` also in the row |
| open | `session.resume` → handle + durable id | `sessions.subscribe` **and** `sessions.messages.subscribe` | only the second delivers a transcript |
| create | `session.create` | `sessions.create` | `label`, no `cwd`, no idempotency key |
| send | `prompt.submit` | `sessions.send {key, message}` | `chat.send` is what it dispatches to internally |
| stop | `session.interrupt` | `sessions.abort {key}` | |
| text stream | `message.delta` | `session.message` + `deltaText` | `replace:true` marks a correction |
| reasoning | `reasoning.delta`, `thinking.delta` | a `sessions.patch` override, not a channel | the thinking pane has nothing to stream |
| tools | `tool.start/generating/complete` | the `session.tool` event family | |
| approvals | `approval.request` / `approval.respond` | `exec.approval.resolve {id, decision}` | maps cleanly |
| history | `session.history` | `chat.history {sessionKey}` | display-normalised by the gateway |
| branch | `session.branch` | `sessions.create {parentSessionKey, fork}` | |
| errors | JSON-RPC numeric codes | string code + `retryable` + `retryAfterMs` | domain error type should carry retryability — Hermes just won't set it |

---

## 8. Migration, in order of risk

Each phase leaves the app working and shippable. No phase is a flag day.

**Phase 0 — free wins. ✅ done.** `Turn`, `ToolCall`, `ThinkingSegment`,
`WebResult`, `TurnEntry`, `PromptEntry` and `Skill` now live in
`lib/domain/transcript.dart` (200 lines out of `workspace.dart`'s 1644, leaving
1451). `workspace.dart` re-exports them so no other file changed, and all 265
tests pass untouched — which is the same acceptance criterion phase 2 uses.

Doing it early paid for itself immediately by finding the leak below.

### What phase 0 found

**`BlockingPrompt` is a protocol type inside a conversation model.**
`PromptEntry.prompt` is a `hermes_protocol` class, so the otherwise-neutral
transcript library has to import the Hermes wire package. Everything else in
there is clean.

This is not cosmetic. A blocking question is a concept *every* agent has —
OpenClaw resolves them with `exec.approval.resolve` — so it needs a domain
type, and `inline_prompt.dart` and `turn_timeline.dart` are already built on
the Hermes shape. Designing `AgentPrompt` is therefore the **first** task of
phase 1, not a detail discovered during it.

The lesson generalises, and it is why phase 0 exists at all: an import list
tells you which files are coupled, and only moving the code tells you *how*.

**Phase 1 — `agent_core`. ✅ done.** The package holds the domain models,
`AgentBackend`, and the capability enum, and depends on nothing but `meta`.
It has grown since: 17 core plus 15 gated members, 26 capabilities, 92 tests.
What is allowed to grow, and what is not, is in *The core did not stay at
twelve* above.

`PromptEntry`'s leak — the thing phase 0 found — is closed: `inline_prompt`,
`turn_timeline` and `console_view` are typed on `AgentPrompt`, and
`domain/transcript.dart` now imports no wire package at all. All 265 app tests
passed unmodified through it, which was the acceptance criterion.

`ToolCall` and `WebResult` moved into the package under neutral names with a
typedef left behind. The type changed packages; the concept did not, and a
rename across twenty call sites would have buried the one change that mattered
under a hundred that did not.

**Phase 2 — `HermesBackend`. Adapter and console done; the last call sites in
progress.** `SessionConsole.handle` takes an `AgentEvent` and switches over the
sealed hierarchy; Hermes' vocabulary stops at `Workspace._dispatch`, which maps
before routing. `workspace.dart` got *shorter* doing it, which is the tell that
the switch replaced the old body rather than being bolted in front of it — the
console holds one `AgentSession` where it held seven mirrored fields.

Both questions this phase was blocked on were answered against the original
plan, and both are better for it:

  * `session.info`'s posture fields went into the domain, not into a
    Hermes-side tail. "Will this agent stop and ask before doing something
    destructive" is the most important thing a user can know about a session,
    and any backend with a policy engine has it. `AgentSession` carries
    `approvalMode`, `unattended` and `warning`; each adapter *derives*
    `unattended` from its own settings, so the UI gets one honest boolean
    rather than a rule it would re-implement per backend. Deliberately not
    `yolo` — that is Hermes' word for the thing.
  * The approvals leak closed too. `SessionConsole.approvals` is a list of
    `AgentPrompt` with `kind == approval`, and `AgentPrompt` gained `subject`
    (what the question is about — the tool) and `escalated` (this was already
    refused once and the user is overriding). A bool rather than a message, so
    the wording stays in the widget.

The acceptance criterion held: exactly one assertion left the suite in the
whole conversion, and it was `expect(console.yolo, isTrue)` — a test of the
wire's vocabulary rather than of behaviour. Everything else that changed in
`test/` is a fixture rewritten to go through the app's own adapter, which is
the path a real frame takes.

Two findings worth keeping:

  * `session.title` arrives as its own event and had been falling through to
    `BackendNotice`, silently dropping server-pushed titles.
  * `TextReset` originally emptied the renderer and re-appended, because the
    streaming controller can only be appended to or emptied. That let one
    divergent snapshot take an hour of conversation with it — worse than the
    drift it was fixing. It now rebuilds from where the turn's answer began.

**Phase 3 — capability gating. ✅ done.** The console menu and the ⌘K palette
are built by filtering one table of entries against the backend's `supports`,
rather than by a wall of `if`s — so a new surface is one row here and one line
in a backend, and forgetting the second shows up as a missing item rather than
a button that throws. Projects and Scheduled jobs lose their toolbar buttons
*and* their keyboard shortcuts on a backend without them; a key that opens a
panel nothing can fill is the same broken promise as a button that does.

Hermes declares everything, so nothing changed on screen — which is exactly
why it was worth doing now, while there is still only one backend to get the
gates wrong with.

Five capabilities were added to serve it (undo, usage, subagents, learning). Each gates a whole surface, which is the rule §9 sets against the
forty-capability future.

**Phase 4 — `openclaw_protocol`. ✅ handshake done, blocked on a credential.**
The package exists: challenge-response connect, Ed25519 device identity, the
v3 signed payload, request routing, typed errors that distinguish a missing
gateway token from an unpaired device, and events carrying `seq`/`stateVersion`.
20 tests, and it reproduces the live server's behaviour exactly.

Generating types from `protocol.schema.json` turned out not to be an option:
the published `@openclaw/gateway-protocol` package is a `0.0.0` placeholder
with two files. The contract came from the server's own validation errors and
from the TypeScript source instead.

The auth handshake is fully solved. The token from `~/.openclaw/openclaw.json`
(`gateway.remote.token`) is correct — presenting it moves the connection past
`AUTH_TOKEN_MISMATCH` to the *next* gate. Two more fields were found the same
way, by the server's own rejections:

  * `deviceFamily` is field 11 of the signed payload and lives on `client`,
    not `device` — the schema rejects it on `device` with "unexpected
    property", which is the only way to learn where it goes. Omitting it when
    the gateway has one recorded produces *"device identity changed"*, which
    reads like a key problem and is not.
  * `auth` carries one of `token`, `deviceToken`, or `bootstrapToken`, and the
    reference client folds whichever is presented into the signature
    (`signatureToken`). The client models all three.

**Now blocked on device pairing, which is a deliberate human gate.** A fresh
key gets `NOT_PAIRED / PAIRING_REQUIRED: device is not approved yet` — it files
a pending request an operator must approve. A stale on-disk identity gets
`device identity changed and must be re-approved`. A bootstrap/setup token
(tried the app's `deepLinkKey`) gets `AUTH_BOOTSTRAP_TOKEN_INVALID: scan a
fresh setup code`. All three are the security boundary working as designed:
a new client is paired by an operator approving it or by scanning a
short-lived code, and neither can be manufactured client-side.

This is the shape any OpenClaw client hits, so it belongs in the backend
design: **connection is a two-step story — handshake, then pairing** — and the
UI needs a "waiting to be approved" state that Hermes (token-in-URL) never
required. `ClawRpcException.needsPairing` already carries it.

~~The four ⚠ questions stay open until a paired credential exists, because
every method that would answer them is behind the handshake.~~ Wrong, and
usefully so: the *methods* are behind the handshake, but the *contract* is not.
It ships with the gateway. See §2 — reading the installed schemas answered all
four and found five parameter bugs besides.

**Phase 5 — `ClawBackend`. Adapter done (18 tests); the connect screen is not.**
It declared two capabilities against Hermes' nineteen, and four of those falses
were *unknowns* rather than known absences — declaring an unknown as supported
is the one mistake this design exists to prevent. Reading the gateway's schemas
turned all four into yes, and the discipline paid: nothing had to be un-built
when the answers arrived, because nothing had been built on a guess. It now
declares six.

Writing it before a paired credential existed turned out to be the right
order. Everything the adapter has to be correct about is shape rather than
data, and it is what forced three parts of the interface into their final form:
`respond()` answerable from an id alone, `release()` as a real lifecycle method
rather than Hermes' no-op, and `AgentStatus.awaitingApproval` existing at all.

Backend selection on `connect_screen` waits on phase 2 finishing. A picker that
leads to a console which cannot render is precisely the failure the capability
rule exists to prevent.

**Phase 6 — Pi and others.** By here the interface has been tested against two
genuinely different protocols, which is the first point at which it is worth
trusting.

---

## 9. Risks

**The abstraction gets shaped by Hermes.** It is the only backend during
phases 1–3, so every ambiguity resolves in its favour. Mitigation: §3's six
differences are written down *now*, before any code, precisely because they
are the places Hermes' shape is not general. Phase 4 before Phase 5 exists so
the wire is understood before the adapter is designed around it.

**Capability sprawl.** Fifteen capabilities today, forty in a year, and every
screen becomes a thicket of `if (supports(...))`. Mitigation: a capability may
only be added when it gates a *whole surface* — a panel, a menu item, a
settings group. Never a single button inside a shared screen.

**Two-id confusion multiplies.** Hermes already has a live handle and a
durable id; OpenClaw adds subscription state. Mitigation: `SessionHandle` is
an opaque type owned by the adapter. The UI never constructs one and never
reads inside it.

**~~History may not exist on OpenClaw.~~ Settled: it does.** `chat.history`,
already display-normalised. The contingency this risk was written for — a local
transcript cache, a much larger piece of work — is not needed. Worth keeping as
a record of a risk that was named early, held a capability at `false` rather
than being guessed at, and cost nothing when the answer arrived.

---

## 10. What is left to settle

1. ~~Answer the four ⚠ questions.~~ Done — from the installed gateway's own
   schemas, not from docs and not by observation. See §2.
2. ~~Decide the history question.~~ Done: `chat.history` exists.
3. ~~**Device pairing.**~~ Done — the app device is approved on the gateway,
   and was later upgraded (in `devices/paired.json`) with `operator.admin`
   so the memory write path could be verified live. The pairing gate itself
   remains the same human step for any *new* device.
4. ~~**Verify the corrected client against the live gateway.**~~ Done for the
   memory path: `tool/live_memory_hermes.dart` and
   `tool/live_memory_write_verify.dart` drove both adapters against real
   servers (see MEMORY_BRIDGE.md). The broader statement still holds for
   surfaces outside the bridge — "matches the schema" and "works" are two
   claims, and only the memory path has closed the gap.
5. Confirm Pi's protocol is a third *genuinely different* shape and not a
   third JSON-RPC-over-WS, since that determines whether the interface has
   been tested against real variation or the same thing twice.
