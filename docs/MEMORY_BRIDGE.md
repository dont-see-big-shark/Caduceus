# Memory Bridge — one memory, two agents

Hermes and OpenClaw each accumulate knowledge about the same person and never
tell each other. This is the design for making Caduceus the place that knows
everything both of them know, and the place from which either can be taught.

Sibling docs: `ARCHITECTURE.md` (the backend seam).

**Status.** All five phases are built, and all five are now verified against
the live gateways. Phase 1 reads both servers; phases 3 and 5 write to the
real OpenClaw (splice, staleness, persona backup/undo); phase 4 probes the
real Hermes (`learning.add` confirmed absent, `learning.edit` accepted, and
the mapping bug it exposed fixed). The two controls the design promised but
the screen did not offer — the *ruling* (merge / keep separate) and the
*remove* — are now in the panel (§9e), and the view no longer hides a
connected server whose read failed (§9e). Sections are marked so verified and
inferred are never confused: a doc that reads as though unwritten code exists
is worse than no doc.

| | | |
| --- | --- | --- |
| §1–§5 | design | current |
| §6 phase 0–5 | **built** | §9 says where the code is |

| §7 | tests | phase 0–1 written, rest are the contract for later phases |

---

## 1. What this is, and what it deliberately is not

**It is** a ledger. Caduceus holds the canonical copy of what the agents know;
each agent holds a *projection* of it. Every write is initiated by a person,
previewed as a diff, and applied to one side at a time.

**It is not** a synchroniser. There is no background reconciliation, no
last-writer-wins, no automatic merge. That is not caution for its own sake —
§2 shows the two stores cannot support one honestly, and a feature that
claimed to would lose writes silently.

Scope for v1, decided with the user:

- **Long-term memory** — Hermes' learning nodes ↔ OpenClaw's `MEMORY.md`.
- **Persona and identity** — `SOUL.md`, `IDENTITY.md`, `USER.md`.

Explicitly out of scope for v1: transcript hand-off between agents, and
working context (cwd, branch, open files). Both are real features; neither is
this one.

---

## 2. The two stores, and why sync is the wrong word

Read from each gateway's own contract, not inferred.

### Hermes — `learning.*`

| | |
| --- | --- |
| Unit | a **node**: `{id, label, meta, style}` where `style ∈ {skill, memory}` |
| Organised by | date bucket, with a category palette |
| List | `learning.frames` |
| Read one | `learning.detail {id}` |
| Update one | `learning.edit {id, content}` |
| Delete one | `learning.delete {id}` — skills archive, memories do not |
| **Create** | **no method exists** |
| Change detection | **none** — a node carries no mtime, no version, no etag |

### OpenClaw — `agents.files.*`

| | |
| --- | --- |
| Unit | a **whole named file** in the agent workspace |
| Files | `MEMORY.md`, `USER.md`, `SOUL.md`, `IDENTITY.md`, `AGENTS.md`, `TOOLS.md`, `HEARTBEAT.md`, `BOOTSTRAP.md` |
| List | `agents.files.list {agentId}` → `{name, path, missing, size, updatedAtMs}` — `operator.read` |
| Read | `agents.files.get {agentId, name}` — `operator.read` |
| Write | `agents.files.set {agentId, name, content}` — **`operator.admin`** |
| Granularity | whole-file replace only |
| Change detection | `updatedAtMs` + `size` |

### The three facts that decide the architecture

1. **Hermes cannot be given a memory it does not have.** There is no
   `learning.add`. Anything learned on OpenClaw can be *shown* next to Hermes'
   memory but cannot be written into it. A design that promised two-way sync
   would fail at its first step in that direction.

2. **Only one side can detect a conflict.** OpenClaw reports `updatedAtMs`;
   a Hermes node reports nothing. Last-writer-wins needs two clocks and there
   is one. So the person is the merge resolver, and the UI must make that
   cheap rather than pretending it is automatic.

3. **A write to OpenClaw replaces the entire file.** `agents.files.set` takes
   `content`, not a patch. The file is also one a human edits by hand and the
   agent edits with its own tools. Whole-file replace from a stale read
   destroys both.

Fact 3 is the one that would have caused real data loss, and §4 is the answer
to it.

---

## 3. The model

One type for both memory and identity. An identity document *is* an entry
whose text happens to be a whole file — unifying them means one diff pipeline,
one preview screen, one set of safety tests, rather than two of each.

```dart
enum MemoryKind { fact, preference, project, skill, persona }

/// Where an entry came from, kept for the life of the entry.
class MemoryOrigin {
  final String backendId;   // 'hermes' | 'openclaw' | 'caduceus'
  final String nativeId;    // a learning node id, or 'MEMORY.md#<slug>'
}

class MemoryEntry {
  final String id;          // ledger id — stable across round trips
  final MemoryKind kind;
  final String title;       // a heading, or the file name for persona docs
  final String text;
  final Set<String> tags;
  final DateTime? updatedAt;
  final MemoryOrigin origin;
}
```

`origin` is why a memory pushed from Hermes to OpenClaw and read back is
recognised rather than duplicated. Dropping it is how a bridge turns one fact
into four over a month.

### Changes are explicit, and their outcomes are per-change

```dart
enum MemoryOp { add, update, remove }
class MemoryChange { final MemoryOp op; final MemoryEntry entry; }

class MemoryChangeOutcome {
  final MemoryChange change;
  final bool applied;
  final String reason;   // why not, in the backend's terms
}
```

A batch does not fail as a batch. Hermes will refuse every `add` and accept
the `update`s in the same push, and the screen must be able to say exactly
that. A backend also declares which operations it can perform at all:

```dart
Set<MemoryOp> get supportedMemoryOps;
```

so the UI never offers "push this new memory to Hermes" in the first place —
the same rule the attachment sheet has followed since the beginning: *a menu
item that fails is worse than one that is absent.*

### The seam

```dart
Future<List<MemoryEntry>> memory();                          // Capability.memoryRead
Future<MemoryWriteResult> applyMemory(List<MemoryChange> c);  // Capability.memoryWrite
Set<MemoryOp> get supportedMemoryOps;
```

Two capabilities, not one, for the reason `serverConfig` and
`serverMaintenance` are two: reading memory is `operator.read` on OpenClaw and
writing it is `operator.admin`.

---

## 4. The safety rules

These are the design. Everything else is plumbing.

### R1 — The app never writes outside its own markers

`MEMORY.md` belongs to the user and the agent. Caduceus owns one block in it:

```markdown
<!-- caduceus:begin -->
... entries the ledger manages ...
<!-- caduceus:end -->
```

A write is: `get` the file, splice the new block between the markers, `set`
the whole thing back. If the markers are absent, the block is **appended**;
nothing existing is touched. **Invariant: every byte outside the markers is
identical before and after.** This is directly testable and is the first test
written.

### R2 — Never delete what the app did not create

A `remove` only applies to an entry whose `origin` the ledger recorded. A line
a human typed into `MEMORY.md` is never removed by this feature, even if it
looks like a duplicate of a ledger entry.

### R3 — Optimistic concurrency where the server offers it

`agents.files.list` gives `updatedAtMs`. Read it when loading, re-read it
immediately before writing, and refuse the write if it moved — the agent may
have written its own memory in between. Surfaced as "this changed on the
server since you loaded it", with a re-diff, never as a silent overwrite.

Hermes offers no such marker, so a Hermes write cannot be guarded this way.
That asymmetry is stated in the UI rather than hidden.

### R4 — Nothing happens in the background

No sync on connect, no sync on a timer, no sync on send. A person opens the
bridge, reads a diff, and applies it. v1 has no other trigger. This is
revisitable once the failure modes are understood in practice; it is not
revisitable before.

### R5 — Admin is granted but not exercised

The device now holds `operator.admin`, which authorises far more than writing
a memory file. The memory path must only ever emit `agents.files.get`,
`agents.files.list` and `agents.files.set`. This is an assertion in the test
suite, not a convention: the fake transport records every method sent, and the
test fails if the set contains anything else.

---

## 5. Mapping, per backend

### OpenClaw

- **Read**: `agents.files.get` on `MEMORY.md` → split into entries on `##`
  headings. Each heading becomes `title`, the body becomes `text`, and
  `nativeId` is `MEMORY.md#<slugified heading>`. Content outside the app's
  markers is read as entries too — read is not restricted to the block, only
  write is.
- **Persona**: `SOUL.md`, `IDENTITY.md`, `USER.md` each map to one entry of
  kind `persona` whose text is the whole file.
- **Write**: R1's splice, guarded by R3.
- **Ops**: `{add, update, remove}` — all three, since the app owns its block.

### Hermes

- **Read**: `learning.frames` → nodes. `style: 'skill'` → `MemoryKind.skill`,
  `style: 'memory'` → `MemoryKind.fact`. `fullLabel` is the text, never
  `label` — the latter is pre-truncated for a terminal column.
- **Write**: `learning.edit` for `update`, `learning.delete` for `remove`.
- **Ops**: `{update, remove}`. `add` is absent from the set, and every
  attempted `add` returns an outcome explaining that this server has no method
  for it.
- Hermes has no persona documents; those entries are simply not offered.

---

## 6. Phases, each shippable

| Phase | What | Ships value alone? |
| --- | --- | --- |
| **0** ✅ | Domain types + the invariant tests below | — |
| **1** ✅ | Read both, one unified list, grouped by kind — verified live | **Yes** — "everything both agents know about me, in one place" is the feature even with no writes |
| **2** ✅ | The ledger: snapshots per backend, cross-backend clustering, rulings | Yes — the two-agent view exists only because of it |
| **3** ✅ | Write to OpenClaw: marker splice + optimistic concurrency + diff preview — verified live | Yes |
| **4** ✅ | Write to Hermes: update/remove, with `add` visibly unavailable — verified live | Yes |
| **5** ✅ | Persona documents — verified live | Yes |

Phase 1 is deliberately first and deliberately write-free. If the unified view
turns out not to be useful, nothing downstream should be built.

---

## 7. The tests, written first

Each is a claim about behaviour that would otherwise be discovered in
production, on real memory.

**Splice safety (R1)**
1. Writing into a file with no markers appends a block and leaves every
   existing byte identical.
2. Writing into a file with markers replaces only what is between them.
3. A file whose markers are in the middle keeps both the text above and the
   text below, byte for byte.
4. Markers that appear inside a fenced code block are not treated as markers.
5. A file with an opening marker and no closing one is treated as unmarked and
   appended to, rather than truncated from the opener to EOF.

**Concurrency (R3)**
6. A write whose `updatedAtMs` moved between load and write is refused, and
   the refusal names the file.
7. The refusal does not emit `agents.files.set` at all.

**Per-change outcomes**
8. A batch of one `add` and one `update` against Hermes applies the update and
   reports the add as unsupported — the batch does not fail.
9. `supportedMemoryOps` for Hermes excludes `add`; for OpenClaw includes it.

**Provenance (dedup)**
10. An entry read from Hermes, pushed to OpenClaw, and read back from OpenClaw
    resolves to one ledger entry, not two.

**Scope discipline (R5)**
11. A full read-diff-write cycle emits only `agents.files.{list,get,set}` and
    nothing else, even though the device holds admin.

**Capability gating**
12. `memoryWrite` is false for an OpenClaw device without `operator.admin`,
    and the push button is therefore absent.
13. `memoryRead` is true for a read-scoped device.

---

## 8. What phase 1 found on a live gateway

Read through the real adapter against a live gateway, not a fake:

```
state: connected        memoryRead: true        memoryWrite: false
1 entry:  [persona] SOUL.md   updated=2026-07-24 15:10:19
```

- **`MEMORY.md` does not exist yet.** A fresh workspace has never written one;
  `agents.files.get` answers `missing: true` with an empty string rather than
  erroring. That is a state to show, so the panel says "has not written
  anything down yet" instead of rendering an empty list that reads as a failed
  load.
- **`agents.files.list` does not carry content.** Every file needs its own
  `get`; the four go out concurrently and each catches for itself.
- **`size` is bytes, `content` is UTF-16.** They disagree by design — the live
  `USER.md` was `size: 537` for 535 characters. Change detection uses
  `updatedAtMs` and nothing else.
- **Every workspace document exists from first boot, holding a template.**
  Showing `- **Name:**` as "what the agent knows about you" is worse than
  showing nothing: it looks like knowledge and is a form. `USER.md` and
  `IDENTITY.md` were correctly filtered; only `SOUL.md` came through.

**A known limitation, stated rather than hidden:** the template test looks for
unfilled fields and italic instructions, so it cannot tell a *shipped*
prose document from a written one. `SOUL.md` ships as prose, so the one entry
above is the default persona rather than something learned. It is still the
honest answer to "what does this agent currently believe about itself" — but a
later phase should compare against the known shipped text and label it.

## 9. What is built, and where

Phase 0 and phase 1. Every path below is real code with tests beside it.

```
packages/agent_core/
  lib/src/memory.dart          MemoryEntry, MemoryOrigin, MemoryKind,
                               MemoryChange/Op/Outcome/WriteResult  (phase 3+ uses
                               the change types; they exist now so the seam is
                               designed once rather than twice)
  lib/src/memory_block.dart    the delimited-block splice — R1 lives here
  lib/src/capability.dart      Capability.memoryRead / memoryWrite
  lib/src/backend.dart         Future<List<MemoryEntry>> memory()
  test/memory_block_test.dart  37 tests, all of them R1

flutter_app/
  lib/backends/claw_memory.dart   MEMORY.md → entries; the template detector
  lib/backends/claw_backend.dart  memory() + applyMemory (R1–R5), scopes-∩-granted capability check
  lib/backends/hermes_backend.dart memory(): frames body → learning.detail for skills
  lib/memory_panel.dart           the read-only panel
  test/claw_memory_test.dart      15 tests on the parser, no socket
  test/claw_backend_test.dart     73 tests on the adapter, fake socket
  tool/live_memory.dart           reads memory from a real gateway
  tool/live_memory_hermes.dart    reads + probes a real Hermes (frames, add, edit, delete)
  tool/live_memory_write_verify.dart  live OpenClaw write path: splice, R3, persona backup/undo
  tool/live_memory_write_probe.dart   live refusal-path check for a non-admin device
```

### Re-running the live check

Three tools prove the adapter's calls are accepted by a *server* rather than
by a fake that agrees with them, all reusing the paired device seed:

- `tool/live_memory.dart` — reads OpenClaw memory (read-only).
- `tool/live_memory_hermes.dart` — reads Hermes memory and probes
  `learning.add` / `learning.edit` / `learning.delete` without mutating data
  (the edit is a no-op with the node's own current content).
- `tool/live_memory_write_verify.dart` — writes to a real OpenClaw and
  reverses every write: add+remove of a probe memory, persona push+undo, and
  an R3 staleness refusal. Needs a device paired with `operator.admin`.
- `tool/live_memory_write_probe.dart` — connects without admin and shows the
  write is refused with zero RPCs emitted.

```bash
cd flutter_app
export CLAW_URL="wss://<your-gateway>"
export CLAW_TOKEN="$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.openclaw/openclaw.json')))['gateway']['remote']['token'])")"
dart run tool/live_memory.dart
```

It prints the connection state, both memory capabilities, and every entry with
its origin and timestamp. Run it after any change to the adapter's calls.

**One live discovery worth repeating:** OpenClaw's hello reports what the
*device* was approved for, but each RPC is authorized against what the
*session asked for*. The tools request `operator.admin` explicitly when they
need to write; a connection that asks only for `chatScopes` is refused even
on a device that holds admin. `ClawBackend.supports()` answers from the
intersection (asked ∧ granted), so the UI never offers a surface the session
could not actually use.

---

## 8b. Phase 2 — the ledger, and phase 2b — more than one connection

`Workspace` held **one** `AgentBackend`, so "what does Hermes know that
OpenClaw does not" could not be answered from live reads at all. Phase 2
answered it from snapshots instead.

**Then the obvious fix was pointed out and taken: hold more than one.**
`BackendPool` connects every saved server, and the memory view compares them
as they are *now*. That is strictly better than comparing one live read
against a recalled one, and it is what the bridge should have done first.

**The ledger did not become redundant, and saying so would be wrong.** The two
cover different failures and both are needed:

| | live pool | ledger snapshot |
| --- | --- | --- |
| Both servers up | ✅ the answer | stale |
| One switched off, or the laptop is offline | ✗ nothing | ✅ the only answer |
| A device still awaiting approval | ✗ nothing | ✅ what it said last time |
| Cost | a handshake per server, and a pairing check on OpenClaw | free |

Since then the app grew **tabs** (`AgentShell`), so several agents are open at
once because the *user* opened them. `AgentTabs.connectedBackends` hands the
bridge live connections with no handshake to pay and no pairing check — which
is better than the pool for the common case, and the pool remains the way to
reach a server that has no tab open.

So the pool is opt-in — the **Ask every agent** button — and the ledger is what
the panel opens with. A panel that silently paid two handshakes every time it
opened would be a worse product than one that shows yesterday's answer
instantly and offers to refresh it.

Three properties the pool has to have, each with a test:

- **One unreachable server must not cost the others.** A pool that failed as a
  unit would be worse than the single backend it replaces.
- **A failure is reported, never dropped.** "This agent does not have that
  memory" and "this agent could not be asked" are opposite claims about the
  same row, and the panel says which.
- **The connection the workspace already holds is adopted, not reopened.** A
  second socket to the same OpenClaw gateway is a second device pairing,
  needing a second human approval — so the pool takes the live one and closes
  only what it opened itself.

Consequences that shaped the code:

- **Recording is a side effect of reading**, because reading is the only
  moment the app can see a server. `Workspace.memory()` records on the way
  past, best-effort — a ledger that cannot write is a stale cache, which beats
  a panel that will not open.
- **A snapshot replaces, never merges.** A memory the agent deleted has to
  disappear from the ledger too, and merging would keep it forever with no way
  to tell it had gone.
- **Every source names itself and says how old it is.** A three-week-old
  snapshot and a live read are different claims, and a view that hid the
  difference would invite acting on stale memory.
- **The live read wins over that backend's own snapshot**, or the one server
  we can actually see would be shown as it was yesterday.

## 9b. Where it is in the app

Memory is per *agent*, not per session, but it is reached from a session
because that is where the app's action surfaces live:

- **Desktop** — the session header's **…** → **Memory…**
- **Phone** — the top bar's **…** opens the command palette → **Memory — what
  it knows about you…** (searchable; type `memory` or `记忆`)
- **Keyboard** — ⌘K, then the same entry

Both entries are gated on `Capability.memoryRead`, so a backend that cannot
report memory shows neither.

**A bug worth recording, because it is invisible from one side.** The panel
first shipped in the desktop menu only. On desktop it worked; on a phone it
did not exist, because there the palette *is* the whole session menu. The two
surfaces are built from separate lists, and nothing compared them — so
`backend_surfaces_test.dart` now asserts that the set of capabilities gating
the menu and the set gating the palette are equal, in both directions.
Verified by deleting the palette entry again and watching the test name the
missing capability.

That the panel is per-session at all is a compromise. Memory belongs to the
server, and a later phase should reach it from the session list or settings —
somewhere it can be opened without first choosing a conversation it has
nothing to do with.

---

## 9c. Phase 3 and 4 — writing, and how each rule is enforced

The four safety rules are the feature; everything else is plumbing. Where each
one lives, and the test that would catch its removal:

| Rule | Enforced by | Caught by |
| --- | --- | --- |
| R1 splice only | `MemoryBlock.write` in `ClawBackend.applyMemory` | *the text outside the markers survives byte for byte* |
| R2 never touch what we did not write | ops apply to the *parsed block*, so nothing outside it is reachable | *a memory outside the block cannot be removed* |
| R3 refuse a stale write | `updatedAtMs` re-read and compared before the `get` | *a file that moved since the read refuses the whole write* |
| R4 nothing in the background | the panel's preview dialog; no timer, no on-connect hook | — (a UI property) |
| R5 admin held, not exercised | — | *a whole write emits only agents.files.\** |

Verified by breaking them: skipping the R3 guard and replacing the splice with
a whole-file write fails three tests by name.

**Hermes cannot be guarded the way OpenClaw is.** A node carries no mtime,
version or etag, so `applyMemory` there has nothing to compare against and does
not pretend to. `supportedMemoryOps` is `{update, remove}` — there is no
`learning.add` — and the panel's push button is gated on `add` being in that
set, so it never appears for Hermes at all rather than appearing and failing.

**Outcomes are per change, not per batch.** A push of two updates and one new
memory applies the updates and reports the third as impossible. Failing the lot
would make a person re-pick the two that were fine, and a push that silently
half-worked is how someone comes to believe an agent knows something it does
not — so every refusal is shown with its reason.

**One known limit of a heading-delimited block**, pinned by a test rather than
hidden: a bare `##` inside an entry's text is indistinguishable from a new
memory, so it splits on the next read. The renderer and the parser are a pair,
and the round-trip tests exist so a change to either half is deliberate.

---

## 9d. Phase 5 — persona documents, the one destructive operation

`SOUL.md` is prose, not a list. There is no block to splice, so pushing one
**really does overwrite what was there** — which makes it different in kind
from everything else the bridge does, and the design says so everywhere:

- **The wording is replacement, never "teach".** A persona push gets its own
  bar and its own dialog. Folding it into "teach it N memories" would describe
  a destructive act in additive words, which is the kind of thing a person
  agrees to and then regrets.
- **What it destroys is kept.** The previous content goes to the ledger, and
  the undo is offered in the confirmation *and* again in a snackbar
  immediately after. A backup nobody knows about is not an undo.
- **The backup is recorded after a successful write, from the value read
  before it.** The first version recorded first, and a refused push then
  destroyed the only copy of the version the user actually wanted back. Pinned
  by *a refused write leaves the existing backup alone*, verified by restoring
  the bug.
- **Only the three known documents may be written.** `agents.files.set` would
  happily write `AGENTS.md` — the file that tells the agent how to operate —
  so the allowlist is explicit rather than a pattern.
- **Deleting one is refused outright.** Removing `SOUL.md` is not forgetting a
  memory; it is breaking the agent.
- **Staleness is checked per file.** Persona documents move independently of
  `MEMORY.md`, so one stamp for the workspace would let a stale `SOUL.md`
  through on the strength of an unchanged memory file.
- **Local refusals cost no round trip.** A delete or a disallowed name is
  settled before any RPC, so the answer does not depend on the server being
  reachable to say "this was never allowed".

The undo goes back through `applyMemory` rather than writing directly, so
restoring is guarded by the same staleness check as the push: if the agent has
rewritten its own persona since, putting the old one back is as destructive as
the push was.

---

## 9e. The two controls that were missing, and the failures that were hidden

Phase 2's design says *the person is the merge resolver, and the UI must make
that cheap rather than pretending it is automatic* — but `rule()` had no call
site in the app, and `MemoryOp.remove` was never issued from it. Both are
closed now:

- **Merge.** A cluster's `…` menu offers *Merge with another…* when another
  cluster of the same kind exists. The picker shows the candidates, the
  confirmation shows both wordings one above the other, and confirming records
  a `same` ruling for every entry pair — which is exactly what two agents
  wording one fact differently need, the usual case the conservative
  fingerprint cannot join.
- **Keep separate.** A cluster the fingerprint *did* join (two backends, two
  copies) offers *Keep separate*. Confirming records a `different` ruling for
  each cross-backend pair — the safety valve, surfaced instead of left in
  code.
- **Remove.** A cluster whose copy on the connected backend is this app's to
  touch offers *Remove* (or *Archive* for a Hermes skill). Wording and undo
  follow what is being deleted: a Hermes skill is archived on the server
  (restorable there), a Hermes memory is gone, and an OpenClaw entry inside
  the app's block is removed with an immediate *Undo* that re-adds it through
  the same `applyMemory` path — so the same staleness guard protects the
  restore as the removal. R2 is respected before the button exists: the
  OpenClaw parser now tags entries inside the app's block (`clawManagedTag`),
  and *Remove* is only offered on tagged entries. Persona documents are never
  removable from here.
- **A connected server that cannot answer is no longer silent.** `memoryView`
  used to swallow the connected backend's read failure and show its stale
  snapshot as if nothing was wrong. It now goes into the `unreachable` banner
  with the others, while the snapshot stays visible, labelled with its age —
  "does not have it" and "could not be asked" remain different claims.
- **Already-open tabs are asked first.** The shell passes
  `AgentTabs.connectedBackends` (and the saved-connection ids they came from)
  into the bridge, so *Ask every agent* reuses open tabs — no handshake, and
  on OpenClaw no second device pairing — and the pool is told not to reopen
  the servers behind them.
- **Refusals are shown inline, not by blanking the panel.** A partial push
  used to replace the whole list with an error screen. It now renders as a
  banner above the list and the list stays, so the applied half is visible
  while the refused half says why.

All pinned by `test/memory_panel_test.dart` (the ruling controls) and
`test/memory_view_test.dart` (failure visibility and tab reuse), plus the
parser's managed-tag tests in `test/claw_memory_test.dart`.

## 10. Known limitations, stated rather than hidden

- **The template detector cannot spot shipped prose.** It looks for unfilled
  fields (`- **Name:**`) and whole-line italic instructions, which catches
  `USER.md` and `IDENTITY.md`. `SOUL.md` ships as prose with neither, so an
  untouched `SOUL.md` reads as written. It is still the honest answer to "what
  does this agent currently believe about itself", but a later phase should
  compare against the known shipped text and label the difference.
- **The Hermes mapping was verified against a live Hermes, and the check
  found a real bug.** `learning.frames` nodes carry a `body` field that is
  *not* what `fullLabel` contains: memory nodes ship their complete text as
  `body` while `fullLabel` is truncated for a terminal column, and skill
  nodes ship no body at all — their content is the SKILL.md file, fetched
  through `learning.detail`. The adapter previously read `fullLabel`, so a
  memory showed truncated and a skill's `learning.edit` was refused
  (`SKILL.md must start with YAML frontmatter`). Fixed by reading `body`
  first and falling back to `learning.detail` for skills, pinned by three new
  tests. Verified live again with `tool/live_memory_hermes.dart`: memory text
  is complete, skill edits are accepted (`{ok: true}`), and the tool also
  confirmed `learning.add` answers `-32601 unknown method`.
- **Hermes' bucket date is not a modification time.** The journey is bucketed
  by when a thing was *learned*, so `MemoryEntry.updatedAt` from Hermes is
  shown but must never be compared against OpenClaw's `updatedAtMs` to decide
  which side is newer. R3 already says Hermes cannot be guarded that way; this
  is the reason the field is nonetheless populated.
- **`MEMORY.md` is parsed on `#`/`##`/`###` headings.** A memory file
  organised some other way — a flat bullet list, say — becomes one entry
  rather than many. That is a lossless reading, not a wrong one, but the
  granularity a diff can offer follows from it.

---

## 11. Open questions

- ~~**Where does the ledger live on disk?**~~ **Answered:** SharedPreferences,
  in the clear, alongside the server list. These are notes about a person, not
  credentials; the Keychain is the wrong home for kilobytes of markdown, and
  encrypting with a key stored beside the data would be theatre. The tradeoff
  is stated in `MemoryLedger`'s doc rather than assumed.
- ~~**How are entries matched across backends?**~~ **Answered in phase 2**, and
  the answer turned on an asymmetry worth stating: **a duplicate is visible and
  annoying, a wrong merge silently discards a fact**. So `MemoryFingerprint`
  collapses only what is never meaning-bearing — case, whitespace, markdown
  decoration, trailing punctuation — and deliberately does *not* stem, drop
  stop-words, or touch negation. `likes tea` and `dislikes tea` must stay two
  memories. A person's ruling always beats the heuristic, in both directions,
  and persona documents never auto-join at all.
- ~~**Does Hermes have an unwrapped create method?**~~ **Answered against the
  live server:** no. `learning.add` answers `-32601 unknown method: learning.add`
  on Hermes v0.20.0 (2026.8.3), so `add` stays out of `supportedMemoryOps`.
