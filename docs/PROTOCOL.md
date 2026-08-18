# Hermes protocol notes

Measured against **Hermes Agent v0.19.1 (2026.7.30)**, not from documentation.
Much of what is published about this — including the upstream docs and every
blog post — describes older builds and is wrong for v0.19.1 in ways that matter.

Reproduce with [`bench/protocol_probe/probe_b_plane.py`](../bench/protocol_probe/probe_b_plane.py).

---

## Headline: the control plane is reachable

`rusty4444/hermes-android` carries 312 lines of dead WebSocket code, and
upstream [#32882](https://github.com/NousResearch/hermes-agent/issues/32882) /
[#38412](https://github.com/NousResearch/hermes-agent/issues/38412) report the
channel as unreachable. On v0.19.1 that is no longer true.

A plain third-party WebSocket client — no Electron, no packaged app — completes
the upgrade and a full JSON-RPC round trip:

```
[PASS] /api/ws?token=<session token> — upgrade accepted
[FAIL] /api/ws?token=<wrong>         — HTTP 403 on upgrade
[FAIL] /api/ws  (no credential)      — HTTP 403 on upgrade

session.list      OK    623 bytes
commands.catalog  OK  33570 bytes
agents.list       OK     17 bytes
```

**"Complete agent console" is viable.** This was the single finding that could
have forced the product down to a chat client.

## The two planes

### B plane — control (`hermes serve`, default port 9119)

JSON-RPC over WebSocket at `/api/ws`. **130 registered methods.** The ones the
console needs:

```
session.create  session.list     session.resume   session.branch
session.history session.interrupt session.steer   session.compress
session.undo    session.usage    session.context_breakdown
session.activate session.close   session.delete   session.title
prompt.submit   prompt.background
approval.respond
commands.catalog  agents.list  model.options  config.get/set  cron.manage
```

`approval.respond` is here and nowhere else — approvals are a B-plane-only
capability, which is precisely why clients that speak only the OpenAI-compatible
subset cannot offer them.

On connect the server pushes an unsolicited `gateway.ready` event before any
request. A client must tolerate server-initiated frames arriving at any time,
not just responses correlated by `id`.

### A plane — data (`hermes gateway run` + `api_server`, default port 8642)

OpenAI-compatible surface. Bearer auth via `API_SERVER_KEY`, enforced on every
endpoint; `/health` is the only unauthenticated one.

Verified: server binds, `/health` returns 200, and all of `/v1/models`,
`/v1/capabilities`, `/v1/skills`, `/v1/toolsets`, `/api/sessions`, `/api/jobs`
correctly reject both a missing and a wrong bearer token with
`401 gateway_auth_error`.

**Not verified: a successful authenticated call.** The server loaded a key other
than the one set in the throwaway profile's `.env`, and resolving that would have
meant reading the real profile's secrets. The auth *model* is confirmed; only a
200 on an authed endpoint is outstanding, and no agent run was executed (that
would spend real LLM credits).

## Authentication — this is where the published guidance is stale

`_ws_auth_reason()` in `hermes_cli/web_server.py`:

| bind | mode | credential |
|---|---|---|
| loopback, no auth provider | `loopback` | `?token=<session token>`, constant-time compared |
| public bind | `gated` | `?ticket=<single-use, 30 s TTL>` **or** `?internal=<process credential>` |

Three things follow, all load-bearing for a mobile client:

1. **`--insecure` is a documented no-op.** As of the June 2026 hardening it no
   longer disables authentication. Every guide recommending `--tui --insecure`
   is describing a build that no longer exists.

2. **In gated mode the legacy `?token=` is unconditionally rejected.** A phone
   on the LAN talking to a public-bound Hermes must mint a single-use ticket
   through the dashboard auth layer and open the socket within 30 seconds — and
   re-mint on every reconnect. That is the real cost of remote B-plane access,
   and it is a client-side state machine, not a blocker.

3. **Tunnelling sidesteps all of it.** Over SSH or Tailscale the server still
   binds loopback, so the simple `?token=` path applies. **This is the
   recommended connection model for Caduceus** — it is simpler, strictly more
   secure, and matches how these users already reach their machines.

`_SESSION_TOKEN` is `HERMES_DASHBOARD_SESSION_TOKEN` if set, otherwise
`secrets.token_urlsafe(32)` regenerated per boot. Pinning it is what makes a
client's stored credential survive a server restart.

## Failure modes a client must handle

**All three WS rejection paths look identical from outside.** The handlers call
`ws.close(code=4401|4403)` *before* `accept()`, which Starlette surfaces as a
plain HTTP 403 — the close code never reaches the client. So `403` means any of:
embedded chat disabled, bad credential, or origin/client not allowed.

A client cannot distinguish them from the socket alone. Diagnostics must probe
`GET /api/status` (unauthenticated on loopback, reports `auth_required` and
`auth_providers`) and reason from there. This is exactly why the community sees
undiagnosable "connection refused" reports — and why connection diagnostics are
a real differentiator rather than polish.

## Where Hermes latency actually comes from

Measured by reading v0.19.1 source, not inferred from behaviour.

**The B-plane transport is well engineered. It is not the bottleneck.**

- `tui_gateway/ws.py:281` sets `TCP_NODELAY` on the WebSocket.
- `tui_gateway/ws.py` coalesces per-token frames: `_TOKEN_COALESCE_S = 0.033`
  (~30 fps), buffering `message.delta` / `reasoning.delta` / `thinking.delta`
  and flushing on a timer rather than waking the event loop per token. The
  comment explains why — each wakeup competes with the agent turn for the GIL.
- Non-streaming events (tool, approval, status, completion) flush the buffer
  ahead of themselves, so ordering is preserved.

That is a careful design. A client will not beat Hermes by out-engineering this.

**The A-plane SSE transport is a different story.**

`gateway/platforms/api_server.py` contains **zero** occurrences of
`TCP_NODELAY`, while `tui_gateway/ws.py` has it. This is exactly consistent with
`rusty4444/hermes-android` shipping a server patch named
`0001-tcp-nodelay-sse.patch`: without it, Nagle coalesces small SSE writes and
adds up to ~40 ms of delay per flush, on top of everything else.

**Direct consequence for Caduceus: stream over the B plane, not the A plane.**
The WebSocket path is already nodelay'd and pre-coalesced at 30 fps; the SSE
path is not. This happens to align with the "complete console" decision — B
plane was already required for approvals.

### So why does the official desktop app feel slow?

By elimination, not in the backend. Hermes Desktop is Electron + React +
`@assistant-ui/react` over the same B-plane gateway that is demonstrably well
behaved. The remaining suspects are all in the render layer:

1. The backend caps updates at 30 fps by design. If the renderer needs more
   than 33 ms to process a batch, it falls behind — and the deficit compounds as
   the response grows.
2. React/`react-markdown` transcripts characteristically re-parse the
   accumulated Markdown per update. That is the same quadratic failure this
   project already measured in Flutter (`docs/BENCHMARKS.md`), except DOM
   reconciliation, layout, and paint are considerably more expensive per node
   than a retained scene graph.
3. Electron's Chromium compositor sits on top of all of it.

**This is a hypothesis, not a measurement.** Hermes Desktop is not installed on
this machine, and `@assistant-ui/react`'s rendering path has not been read. What
*is* measured is the elimination: the transport is not at fault.

It is also the good news. The latency lives in precisely the layer Caduceus
replaces — and the fix is the one already built and benchmarked here.

### Why OpenClaw feels smoother

OpenClaw ships **native Swift** apps for iOS, watchOS, and macOS, connecting to
its Gateway over WebSocket as "companion nodes" (port 18789, explicit pairing
approval). No Chromium, no DOM, no JS bridge — platform-native text rendering
against a retained view hierarchy.

The comparison is therefore native-vs-Electron at the render layer, with
comparable transports underneath. That is the same gap Caduceus is aiming at,
approached with Flutter instead of per-platform Swift.

## Event catalogue (recorded from live turns)

Every push is `method: "event"`; the real name is `params.type`. Recorded from a
real tool-using turn against v0.19.0 — **not** guessed.

| event | payload | notes |
|---|---|---|
| `gateway.ready` | `{skin: {...}}` | large static theme blob, sent before any request |
| `session.info` | `{model, provider, approval_mode, tools: {...}}` | full tool inventory; large |
| `message.start` | — | turn begins |
| `reasoning.delta` | `{text}` | **private reasoning — must not be merged into the answer** |
| `thinking.delta` | `{text}` | **the live status line, not reasoning** — see below |
| `message.delta` | `{text}` | the answer |
| `tool.generating` | `{name}` | model committing to a tool; args unknown yet |
| `tool.start` | `{tool_id, name, context}` | `context` is a ready-made label, e.g. `"Running ls ~"` |
| `tool.complete` | `{tool_id, name, args, duration_s, result:{output, exit_code, error}}` | correlate by `tool_id` |
| `reasoning.available` | `{text}` | final reasoning |
| `message.complete` | `{text, usage:{model, input, output, prompt, total}}` | **full final text** — use it to reconcile after a reconnect |
| `session.title` | — | server auto-titles a session |
| `approval.request` | `{command, choices, smart_denied?, allow_permanent?}` | see below |

**These are control-plane names.** The A-plane SSE docs use `tool.started` /
`tool.completed`; the control plane uses `tool.start` / `tool.complete`. Reading
one plane's docs while implementing the other is a reliable way to be wrong.

**Channel separation matters more than it looks.** One live turn produced 13
`reasoning.delta` frames against 1 `message.delta`. Treating all `*.delta`
frames alike buries the reply inside the model's private notes.

## Approvals

`choices` is authoritative and **does not contain "allow"**:

| context | choices |
|---|---|
| normal | `once`, `session`, `always`, `deny` |
| `allow_permanent: false` | `once`, `session`, `deny` |
| `smart_denied` | `once`, `deny` (owner override of a Smart DENY) |

`resolve_gateway_approval` stores the choice string **verbatim without
validating it**, so an invented value silently fails to approve while the UI
reports success. Render the server's `choices`; never hardcode Approve/Deny.

`command` is redacted server-side before emission (credential-shaped values
stripped, issue #48456), so it is safe to display.

**Not observed live.** `smart` approval mode auto-approved both a read (`ls ~`)
and a filesystem write. Forcing a gate needs a genuinely dangerous command or a
global `approval_mode` change on a production server. The shapes above are
transcribed from `_emit_approval_request`, which builds them.

## Session addressing — two ids, and using the wrong one breaks the console

Almost every method takes an explicit `session_id`, resolved through the
`_sess(params, rid)` helper — including ones whose bodies contain no literal
`params.get("session_id")`. Only `session.list` and `session.create` do not.

**`session.resume` is the load-a-session call**, and it mints a *new*
gateway-local handle:

```python
sid = uuid.uuid4().hex[:8]        # methods_session.py
_sessions[sid] = {...}            # the live registry _sess_nowait reads
```

The response carries both ids:

| field | meaning | use for |
|---|---|---|
| `session_id` | gateway-local handle (8 hex) | **every subsequent RPC, and event routing** |
| `resumed` | durable id from `session.list` | display, re-opening later |

`_sess_nowait` is just `_sessions.get(params["session_id"])`, so addressing a
resumed session by its persisted id fails `session not found` (4001).

Measured, same session, same connection:

```
title via persisted id  -> 4001 session not found
title via live handle   -> 4021 title required     ← found; it just wanted a title
```

**Events are emitted against the gateway handle too**, so a client that keys its
routing on the persisted id receives nothing at all for a resumed session.

This one mistake makes `title`, `interrupt`, `steer`, `compress`, `usage`,
`context_breakdown`, `history` and `approval.respond` all appear broken with an
identical, opaque 4001. They are not broken — verified working once addressed
by the handle. An earlier revision of this document claimed
`session.history` / `usage` were unusable in this version; that was wrong, and
this is the correction.

`session.resume` does truncate: a session listed with 234 messages returned 153.

## Consequences for Caduceus

- Build the protocol layer against **both** planes. B plane is not optional and
  not blocked.
- Default connection model: **tunnel to loopback**, `?token=` auth, pinned
  `HERMES_DASHBOARD_SESSION_TOKEN`.
- Support gated/ticket mode later for direct public binds; treat the 30-second
  single-use ticket as a reconnect-path state machine from day one.
- Never present a bare `403`. Probe `/api/status` and name the actual cause.

## Sending while a turn is running

`prompt.submit` takes an optional `queued` flag. Verified against a live
gateway: submitting a second prompt during a turn with `queued: true` answers
`{"status": "queued"}` and both turns run to completion in order, versus
`{"status": "streaming"}` for the first.

`session.steer` is a *different* operation — it redirects the turn in flight.
It also succeeds against an idle session and does nothing at all, which makes
it a dangerous fallback: a client that silently steers whenever it believes a
turn is running will drop the user's message with neither a reply nor an error
whenever that belief is wrong. Queue by default; steer only on request.

## Keepalive

Neither plane sends application-level heartbeats, and nothing in the JSON-RPC
layer detects a half-open socket: `send` succeeds into a dead connection and
the reply simply never arrives. Caduceus sets a 20 s WebSocket ping interval
(`IOWebSocketChannel.connect(pingInterval:)`), which makes `dart:io` close the
socket when a pong is missed, and treats an RPC timeout as evidence the
transport is dead rather than merely slow.

Measured on the reference deployment (reverse proxy, path-prefixed mount): an
idle socket survived 30/60/90/120/180 s probes, each answering in ~200 ms. So
the proxy there is not the aggressive idle-reaper the keepalive guards against
— but a client with no dead-peer detection at all is wrong regardless of one
deployment's timeouts.

## Attachments from a remote client

- `image.attach` and `pdf.attach` take a *path the gateway can open*. From
  another machine that is useless.
- `image.attach_bytes` takes `content_base64` + `filename`/`ext`.
- `file.attach` takes `data_url` (`data:<mime>;base64,…`), materialises the
  file under `<session cwd>/.hermes/desktop-attachments/`, and returns
  `ref_text` — an `@file:` reference to paste into the prompt.

**The session needs a usable working directory first.** A session created
through `session.create` with no `cwd` sat at `/` on the reference server, and
`file.attach` failed with `[Errno 13] Permission denied: '/.hermes'`. After
`session.cwd.set` to a writable directory the same call succeeded and returned
`@file:.hermes/desktop-attachments/<name>`.

## Other methods a full console needs

Confirmed live, with shapes taken from `tui_gateway/methods_*.py`:

| Method | Notes |
| --- | --- |
| `complete.path` | `word` (with its leading `@`) + `session_id`; returns `items[{text, display, meta}]`. Resolves against the session cwd — a local file picker cannot substitute. |
| `rollback.list` / `.diff` / `.restore` | Filesystem checkpoints. `list` returns `{enabled, checkpoints[{hash, timestamp, message}]}`; `diff` truncates at 4 KB; a full `restore` is refused (4009) while a turn runs. |
| `process.list` / `process.kill` | Background processes. The entry's `session_id` is the *process registry's* id, not the conversation's — never route events on it. `output_tail` is a 4 KB tail added for desktop clients. |
| `session.undo` | Refused (4009) while running; returns `{removed: n}`. |
| `session.cwd.set` | Refused while running; returns `{cwd, branch, project, lazy}`. |
| `tools.list` | Toolsets with `enabled` flags, including MCP servers. |
| `session.status` | A pre-rendered text block, not structured fields. |

## Deliberately not wrapped

The gateway registers ~130 methods. These are the ones Caduceus does **not**
expose, with the reason, so the gap is a decision rather than an oversight.

| Methods | Why not |
| --- | --- |
| `billing.charge`, `billing.auto_reload`, `billing.step_up`, `subscription.upgrade` / `.change` / `.resume` | They move money. A client that can spend on the user's behalf is a different product with a different consent model. |
| `voice.record`, `voice.toggle`, `voice.tts` | The microphone is on the *server*. A remote client that can start it is a surveillance feature, not a convenience. |
| `wake.start` / `.stop` / `.status` / `.pause` / `.resume` | Not present on the reference server — `wake.status` answers `unknown method (-32601)` on 0.19.x. Wrapping methods that only exist in a newer local checkout is how unverified surface ships. |
| `tools.configure` | Writes the *global* CLI config, not session state. Toolsets are shown read-only instead — see `lib/server_panel.dart`. |
| `cli.exec`, `shell.exec`, `process.kill` (unscoped) | `process.kill` is wrapped because it is session-scoped and the panel shows what it will kill. Arbitrary command execution from a chat client is not something this UI can make safe. |

## Blocking prompts — ignoring these hangs the agent

`clarify.request`, `sudo.request` and `secret.request` are not notifications.
The server's `_block` helper emits one and **parks the agent thread** on a
`threading.Event` until an answer arrives — 300 s for sudo and secret, and
unbounded for a clarify whose timeout is disabled, released only by an answer
or `session.interrupt`.

A client that renders deltas but ignores these looks correct right up until the
agent asks something, at which point the turn simply stops. That is
indistinguishable from a dead connection, and it is the same user-visible
symptom as the send bug this project already fixed once.

They are answered with `clarify.respond` / `sudo.respond` / `secret.respond`,
keyed on `request_id` from the payload — **not** the session id. The answer
field differs per method: `answer`, `password`, `value`. All three accept a
late answer (`allow_expired`) and return `{"status": "expired"}` rather than an
error, so a slow user does not produce a spurious failure.

`clarify.request` may carry `choices` and `multi_select`; `secret.request`
carries `env_var`, the environment variable the server will store the value
under.

When the server gives up it emits `<kind>.expire` with the same `request_id` —
`clarify.expire`, `sudo.expire`, `secret.expire`, `terminal.read.expire`. A
client that ignores those leaves a banner up offering an answer that can no
longer be delivered.

`terminal.read.request` is the fourth member of the family, blocking for 30 s.
It asks for the *client's* in-app terminal buffer, which a remote GUI does not
have — and should not fake, since a terminal on the user's laptop is not the
machine the agent is working on. Caduceus answers immediately with an empty
buffer and a note saying so, because the alternative is not "no answer" but
"the same empty answer, 30 seconds later".

## Reasoning arrives on three channels, not one

| Event | Shape | Notes |
| --- | --- | --- |
| `reasoning.delta` | incremental `text` | The common case. |
| `thinking.delta` | a status string | **Not reasoning.** See "The channel that is not reasoning". |
| `reasoning.available` | the whole trace in one `text` | Emitted with the full preview. Some models send this *instead of* the deltas. |

A client that handles only the delta channels renders a block-only model as
having done no thinking at all. One that appends all three doubles the trace
on models that send both — a live run against the reference server produced 13
`reasoning.delta` frames *and* one `reasoning.available` restating them.

### The channel that is not reasoning

`thinking.delta` looks like a reasoning channel and is not one. `server.py`
bridges it from `thinking_callback`, and `run_agent.py` says what that callback
is for:

> Long provider waits (slow/overloaded backend, no first byte, reasoning model
> thinking for minutes) used to leave the user staring at a generic
> "cogitating..." spinner with no hint of what the agent was waiting on. […]
> TUI / Desktop: the same callback is bridged to the `thinking.delta` event,
> which both render as the live spinner/status line.

Observed payload on the reference server: `{"text": "◉_◉ cogitating..."}`.

Reading it as a status line is safe rather than merely plausible:
`thinking_callback` has exactly one caller in `run_agent.py` —
`_emit_wait_notice`. Reasoning travels a separate path entirely
(`reasoning_callback` → `_fire_reasoning_delta` → `reasoning.delta`, plus
`reasoning.available`), so no model can deliver its reasoning through this
channel alone. Checked because splitting the two would otherwise have risked
showing nothing at all for such a model.

This client treated it as reasoning for months. Two costs: the model's thoughts
were interleaved with a spinner label, and the one channel that explains *why*
a 57-second wait is 57 seconds long was discarded. Read it as a status line and
show it beside the elapsed clock.

### Reasoning arrives in bursts as often as it streams

Timed against the reference server, same model, two questions:

| Question | Reasoning frames | Span | Silence before the first frame |
| --- | ---: | ---: | ---: |
| A short word problem | 91 | 892 ms | 20.3 s |
| "why is the sky blue" + an estimate | 1,760 | 119 s | 29.7 s |

A client cannot assume either shape. The long silence before the first frame is
why the elapsed clock and the status line matter, and the 892 ms burst is why a
repaint cadence tuned for counters makes a trace look like it appeared all at
once — 250 ms gives that burst three repaints.
Caduceus takes the block only when the turn produced no streamed reasoning.

`message.start` is emitted before the agent loop runs (`server.py`, just above
`def run()`), so it precedes reasoning and tool events on the normal prompt
path. It is not safe to *rely* on that ordering: `session.resume` on a running
turn drops a client in mid-stream, where the first frame seen is whatever
comes next.

## `session.info` is not just the model

`_session_info` returns model, provider, `reasoning_effort`, `service_tier`,
`fast`, `yolo`, `approval_mode`, `tools`, `skills`, `cwd`, `branch`,
`project`, `personality`, `running`, `title` and `stored_session_id`, plus
`config_warning` when `_probe_config_health` finds something wrong.

Two of those are not cosmetic. `yolo` and `approval_mode: auto` mean the
session will run tools without stopping to ask — a client that reads only
`model` gives no indication that approval prompts are never coming.
`config_warning` is the server's own verdict on its configuration; dropping it
leaves the user to infer it from behaviour.

## `session.resume` carries the turn in progress

Beyond `messages`, a resume of a running session returns:

| Key | Contents |
| --- | --- |
| `inflight` | `{user, assistant, streaming, started_at, updated_at}` — the prompt being answered and the answer text so far |
| `queued` | `{user}` — a prompt the server accepted but has not started |
| `session_key`, `started_at`, `status` | session identity and lifecycle |

A client that reads only `messages` shows the transcript ending at the
*previous* exchange while the agent is mid-answer, and then appends arriving
deltas underneath no question at all. The server source is explicit about the
queued case: without carrying it, "the accepted prompt disappears until it
finally drains".

The queued prompt should not go in the transcript. It has not been answered,
and text written after the partial answer means the next delta lands below it
— splitting one answer into two halves with an unrelated line between them.
Caduceus shows it above the composer instead.

## Blocking prompts: three shapes, one of them empty

| Event | Payload beyond `request_id` |
| --- | --- |
| `clarify.request` | `question`, `choices`, and `multi_select` **only when true** |
| `secret.request` | `prompt`, `env_var` |
| `sudo.request` | *nothing* — `_block("sudo.request", sid, {})` |

A client that renders the request's own text and nothing else shows an
unlabelled password field for sudo. The label has to come from the client,
keyed on the event type.

`multi_select` is described in the server source as a hint that "renderers
with checkbox support can honor"; a single answer still parses as a
one-element list on the tool side, so the answer is comma-separated either
way.

`approval.request` only defaults `choices` when `smart_denied` or
`allow_permanent` is present. It can arrive with no `choices` at all, and a
client that renders exactly what it was given then shows an approval with no
buttons on a turn that is blocked waiting for one. Falling back to
`["once", "deny"]` is the conservative pair: it never grants a permanent
allow the server did not offer.

## Tool events are conditional, and their result is not always JSON

`tool.start` is emitted only when `_tool_progress_enabled(sid)` or the tool is
one the UI needs lifecycle events for. `tool.complete` has the same guard plus
an inline-diff escape. A client that builds its timeline from `tool.start`
alone therefore loses tool calls entirely on a server with tool progress
turned off — not just on a reconnect landing mid-tool. Caduceus appends an
entry from `tool.complete` when it never saw the start.

`result` is `json.loads(result)` with a fallback to the raw string when that
fails. Reading only the mapping shape shows no output at all for every tool
that returns plain text. When there is no output field, `summary` is the
server's own one-line rendering and is the right thing to display.

| Key | Present |
| --- | --- |
| `tool_id`, `name` | always |
| `context` | `tool.start`, a rendered argument summary |
| `args_text` | `tool.start`, verbose sessions only |
| `duration_s` | `tool.complete`, when the start time was recorded |
| `result` | `tool.complete` — object **or** string |
| `summary`, `result_text`, `inline_diff`, `todos` | `tool.complete`, situational |

## Methods that never return

Three methods hang indefinitely on the reference server (0.19.x) while the
socket stays healthy:

| Method | Behaviour |
| --- | --- |
| `usage.bars` | No reply, ever. |
| `setup.status` | No reply. |
| `session.active_list` | No reply — and appears to leave a lock held: after calling it, `session.list` began timing out too while `agents.list`, `session.create` and unknown-method dispatch all kept answering in under 300 ms. Recovering needed a gateway restart. |

The practical consequence for a client is that "this call timed out" is not
evidence the connection is dead. See the liveness probe in
`gateway_client.dart`.

## `learning.frames` is more than an animation

It exists to pre-render the TUI's `/journey` overlay and most of its payload is
a character grid sized in `cols`/`rows`. But the same response also carries the
structured data the grid was rendered *from* — `buckets` (per-day, each with
its nodes, category and `#RRGGBB` colour), `categories`, `summary`, `axis` and
`count`. Ask for the smallest legal grid, discard it, and build a native view
from the rest. Nodes are then addressable through `learning.detail` / `.edit` /
`.delete`.

### Shape corrections found while wrapping

- `skills.manage {action: 'list'}` returns `skills` as a **map** of name →
  description on 0.19.x, not the list every neighbouring method uses. Both
  shapes are accepted.
- `agents.list` returns `{processes: [...]}` — the *process registry*, not a
  roster of agent definitions. The name is misleading.
- `process.list` entries call their own id `session_id`. It is not the
  conversation's session id and must never be used for event routing.
