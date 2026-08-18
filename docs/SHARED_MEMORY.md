# Shared Memory — a collective memory, and drift that announces itself

The memory bridge (`MEMORY_BRIDGE.md`) is a ledger: Caduceus records what each
agent remembers, the person compares the two, and merge/keep/remove are
**manual** — the screen shows two wordings of a fact and asks. This is the
design for the next layer: a **shared knowledge base** the person curates and
every agent projects, with **automatic drift detection** that marks when an
agent's copy stops matching the agreed one — so the merge/keep/remove controls
are triggered by evidence, not by eyeballing.

Sibling docs: `MEMORY_BRIDGE.md` (the ledger this sits on), `AGENT_GRAPH.md`
(the relationship layer this feeds), `SKILLS_BRIDGE.md` (the sibling bridge).

**Status: built and live-verified.** The pure core (`agent_core` shared_memory),
the physical store (`MemoryLedger`), the workspace actions (sync/restore/drop),
the **Shared memory…** panel, and the Memory panel's drift badge are
implemented and pinned by `packages/agent_core/test/shared_memory_test.dart`
(10 tests), `flutter_app/test/shared_memory_workspace_test.dart` (7) and
`flutter_app/test/shared_memory_panel_test.dart` (5).

**A decisive correction since the first draft, verified against the live Hermes
on 2026-08-09:** Hermes *can* receive a new fact — through its agent, not its
RPC. §2 carries the probe evidence and §6 the sync shape it forces.

Live verification on 2026-08-09 (`tool/verify_bridge_live.dart`), after the
user granted OpenClaw writes: a fresh fact reads `missing` on both agents,
the sync to OpenClaw lands (`1 applied, 0 refused`), read-back reports
`synced @ MEMORY.md#note` (the anchor points at the actual block entry), and
the probe entry is removed afterwards. The Hermes agent-mediated write was
verified end-to-end in the probe (§2): the fact landed in `MEMORY.md` as
`memory:memory:N` within ~30 s and was deleted again via `learning.delete`.

---

## 1. What this is, and what it deliberately is not

**It is** a shared knowledge base with a diff that runs itself:

- A person adds "facts every agent should know" to a shared list.
- Each fact carries, per agent, a **status**: `synced`, `missing`, `drifted`,
  `kept-divergent`, or `unverifiable`.
- A drifted fact shows both versions side by side and offers *restore the
  shared version*, *keep the local one* (mark divergent, stop nagging), or
  *drop it from the shared base*.
- One control syncs the whole base to every agent that can receive it.

**It is not** a physical shared file. Hermes and OpenClaw may live on
different hosts or isolated environments; there is no disk both agents read, and inventing one
would be the first thing to break. "Shared" here means **logically shared**:
Caduceus holds the canonical copy and projects it into each agent's own store,
exactly as the bridge already projects memory. The honest wording is "one
source of truth, many local copies", and the drift detector exists precisely
because copies can diverge.

**It is not** a synchroniser that runs in the background. Nothing reconciles
without the person asking — `MEMORY_BRIDGE.md` R4 holds here too. The *detector*
runs on every read (it is free); the *write* is always a deliberate act.

**It is not** a semantic engine. Detection compares fingerprints and the
anchors the sync left behind, never meaning. "likes tea" becoming "dislikes
tea" in the same anchored entry *is* caught — the fingerprint changed — but two
unrelated entries are never guessed to be one fact. The bridge's rule stands:
a duplicate is visible and annoying, a wrong merge silently discards a fact.

---

## 2. The facts that shape the design

Re-stated from `MEMORY_BRIDGE.md` §2, because three of them decide everything:

1. **Hermes' memory is physical files, and they are what the bridge reads.**
   `learning.frames` memory nodes are `memory:<source>:<index>` projections of
   `§`-delimited entries in `~/.hermes/memories/MEMORY.md` (source `memory`)
   and `USER.md` (source `profile`) — confirmed in `agent/learning_graph.py`.
   `learning.detail` / `.edit` / `.delete` on those ids operate the files
   directly. There is no mtime or version on a node, so Hermes drift is
   detected by fingerprint-and-anchor comparison, never by a timestamp.
2. **Hermes has no create RPC — but it has a create channel, verified live.**
   Probed on 2026-08-09: `learning.add`, `memory.*`, `files.*` all answer
   `-32601 unknown method`; `learning.edit` updates only (a new id answers
   `not found in active profile`); the dashboard REST exposes get/delete/
   update only; `cli.exec` runs the Hermes CLI, which has no memory-add
   command. What works: a `prompt.submit` asking Hermes to remember a fact
   makes the agent's `memory` tool append it to `MEMORY.md`; within ~30 s it
   appears in `learning.frames` as a new `memory:memory:N` node with the full
   text in `body` — readable via `learning.detail`, deletable via
   `learning.delete`. **So Hermes sync is agent-mediated: the client asks, the
   agent writes, the client reads back to verify.** Caveats: the agent may
   reword (observed: near-verbatim, with a suffix appended), `write_approval:
   true` stages writes for `/memory approve`, and the 2,200-char `MEMORY.md`
   cap refuses an overfull add.
3. **An OpenClaw write replaces the whole `MEMORY.md` block.** The sync writes
   through the existing `applyMemory` path — block splice, staleness guard,
   `clawManagedTag` — so a shared fact dropped into OpenClaw is an ordinary
   entry the app owns, removable and restorable by the same rules.

One more, from this design's own scope: **a shared fact is a fact, not a
persona document.** `SOUL.md` is who an agent is, and the bridge deliberately
never auto-joins persona documents (`memory_match.dart`). The shared base does
not change that: persona stays a per-agent, per-person act.

---

## 3. The model

Pure and testable in `agent_core`, beside the matching code it reuses.

```dart
/// One fact the person wants every agent to know.
class SharedFact {
  final String id;          // stable, like MemoryEntry.id
  final MemoryKind kind;    // fact / preference / project — never persona
  final String text;        // the canonical wording
  final String? title;
  final DateTime updatedAt;
}

/// What one agent's copy of a shared fact looks like right now.
enum AgentFactStatus {
  synced,          // fingerprint matches the shared fact
  missing,         // agent has nothing matching — syncable where MemoryOp.add exists
  drifted,         // an anchored entry exists but its content moved
  keptDivergent,   // the person ruled "keep the local version", so stop nagging
  unverifiable,    // agent could not be asked
}

class AgentFactState {
  final String backendId;
  final AgentFactStatus status;
  final String? nativeId;      // the agent's address for it, when found
  final String? localText;     // the drifted local wording, for the side-by-side
  final String? detail;        // unverifiable reason, in the bridge's vocabulary
}

/// Where the sync left each fact on each agent — the drift detector's memory.
class SyncAnchor {
  final String factId;
  final String backendId;
  final String nativeId;       // 'MEMORY.md#<slug>' or a Hermes node id
  final String fingerprint;    // what we last wrote, so a change is visible
  final DateTime syncedAt;
}
```

Storage: two new keys in the existing `MemoryLedger` store (SharedPreferences,
in the clear, same reasoning as the ledger itself): `memory.sharedFacts.v1` and
`memory.sharedAnchors.v1`. **This store is the physical copy** — the canonical
one Caduceus holds, and the thing a future cloud sync would replicate (the
schema is kept flat and versioned so that migration is a plain read). Every
agent that receives a fact holds its own physical copy too: a `§` entry in
Hermes' `MEMORY.md`, a block entry in OpenClaw's `MEMORY.md`. "Shared" means
one canonical store plus verified local copies, never a shared pointer.

Divergence is deliberately **not** persisted: per the user's decision, *Keep
local* means "this reading" — the badge folds for the session and the detector
reports again on the next read. There is no permanent `keptDivergent` state to
reconcile later.

---

## 4. Detection — the part that runs itself

One pure function, fed what `memoryView` already returns:

```dart
List<AgentFactState> detectFactStates({
  required SharedFact fact,
  required List<MemoryCluster> clusters,   // memoryView.clusters
  required Set<String> knownBackends,      // memoryView.backends
  required Map<String, String> unreachable,// memoryView.unreachable
  required SyncAnchor? anchor,             // per fact × backend
  required bool keptDivergent,
})
```

The rule, per agent, in order:

1. **Unreachable** → `unverifiable` (never "missing" — opposite claims).
2. **Kept divergent** → `keptDivergent` (the person decided; no nagging).
3. **Anchor present** → look up `nativeId` in the agent's entries:
   - still there, fingerprint equal → `synced`;
   - still there, fingerprint differs → **`drifted`** (show both texts);
   - gone → fall to 4 (the entry was deleted or reworded out of recognition).
4. **No anchor, or anchor lost** → search the agent's entries by fingerprint:
   - a match → `synced` (and re-anchor — the fact is there, in new clothes);
   - no match → `missing`.

The anchor is what makes "drifted" trustworthy: it says *this exact entry was
the shared fact, and now it says something else*. Without an anchor, all the
detector can honestly say is "not found" — it never guesses that an unrelated
entry used to be the shared one.

**Hermes anchors are captured by read-back, not assumed.** Because the write
is agent-mediated, the sync does not know in advance what text will land or
which `memory:memory:N` id it gets. So a Hermes sync is: ask (`prompt.submit`)
→ poll `learning.frames` until a node matching the requested fingerprint
appears (or a timeout/refusal is reported) → anchor that node with the
fingerprint of what *actually* landed. The shared fact's canonical text stays
the person's; the anchor records the agent's copy, which is what drift is
measured against.

---

## 5. The view

A new panel, **Shared memory…**, reached from the session menu `…` and ⌘K,
gated on `Capability.memoryRead` — the shared base is a fleet view, not a
per-agent one, so it does not live inside the Memory panel (whose push target
is "the agent I am looking at").

Phone-first, same rule as the Fleet panel: the sheet navigates inside itself,
no stacked routes.

- **Roster of facts.** Each `SharedFact` is a card: text, kind, updated, and
  one status chip per agent (`synced` jade · `missing` brass · `drifted` coral ·
  `keptDivergent` grey · `unverifiable` coral-outline). A fact with any
  `drifted`/`missing` agent gets a **"needs attention"** edge, so the collective
  state is scannable without opening anything.
- **Fact detail.** Tap a card: per-agent rows. A drifted row shows the shared
  wording and the local wording side by side, with the controls from §6.
- **Compose.** Add a fact (text + kind), edit one, or drop one. Dropping asks
  what to do with the copies already pushed: leave them (they become ordinary
  memories) or remove them where this app owns them (the `_remove` path, R2).
- **Sync all.** One button pushes every `missing` fact to every agent that can
  take it (Hermes: only facts with an anchor it can `update`; OpenClaw:
  `add`/`update` through the block). Refusals inline, exactly as the memory
  panel renders them — a sync that half-worked must say which half.

**The Memory panel gets the evidence, not a new layout.** A cluster that the
detector marks `drifted` on the connected agent shows a small coral **drifted**
badge on its row; expanding it shows "shared: … / local: …" and a *Restore
shared* action. The existing merge/keep/remove controls stay exactly where they
are — the upgrade is that a drift now *tells* the person instead of waiting to
be spotted.

---

## 6. The actions

| Control | What it does | Reuses |
| --- | --- | --- |
| **Sync all** / per-fact **Sync** | OpenClaw: `MemoryOp.add`/`update` through `applyMemory` (block splice, R3). Hermes: ask the agent via `prompt.submit`, then read back `learning.frames` to capture the anchor — the sync result is *verified*, not assumed. Both record/refresh anchors | `Workspace.applyMemory`; `prompt.submit` + `learning.frames` read-back |
| **Restore shared** | overwrite the drifted entry with the shared text via its anchor (`update`) | `applyMemory`, anchor |
| **Keep local** | mark `keptDivergent` for that fact×backend — the copy stays, the badge stops | the ruling store's philosophy |
| **Drop from shared** | remove the fact from the base; optionally remove app-owned copies | `_remove` / R2 |
| **Remove from an agent** | the existing per-entry removal, unchanged | `_removable` gates |

Every write is a deliberate, previewed act — the memory panel's confirmation
dialogues, not a background reconciler.

---

## 7. What is deliberately not v1

- **Physical shared storage** — §1: the honest "shared" is logical.
- **Direct Hermes fact creation** — no create RPC exists; the only channel is
  agent-mediated (`prompt.submit` → `memory` tool → `MEMORY.md`), which this
  design uses and then verifies by read-back. Where the agent refuses (approval
  gate, full memory, reword-to-ambiguity) the sync says so and the fact stays
  `missing` for that agent.
- **Semantic drift** — only fingerprint + anchor; "likes tea" vs "dislikes
  tea" as *unrelated entries* are two facts, never auto-joined.
- **Auto-reconcile / background sync** — R4.
- **Shared persona** — persona stays per-agent (§2).
- **Three-backend fan-out** — the projection is backend-agnostic, but v1 is
  verified against the two this client has.

---

## 8. Phases

- **Phase 1 — the base and the detector.** `agent_core`: `SharedFact`,
  `AgentFactState`, `detectFactStates` (pure, tested). `flutter_app`: shared
  facts ledger in `MemoryLedger`, the **Shared memory…** panel (roster +
  detail, read-only), drift badges on Memory-panel clusters.
- **Phase 2 — the writes.** Sync all / per-fact sync via `applyMemory`,
  anchors recorded and re-read; Restore shared; Keep local; Drop from shared
  (with the optional remove-copies question).
- **Phase 3 — live verification.** Extend `tool/verify_bridge_live.dart` to
  seed one shared fact, sync it to both gateways, mutate the OpenClaw copy,
  and print the detector's verdict.

---

## 9. Tests

- `packages/agent_core/test/shared_memory_test.dart` — the five states:
  synced, missing (syncable vs Hermes-unsupported), drifted (anchor changed),
  kept-divergent (no nagging), unverifiable (never "missing"); anchor-lost
  falls back to fingerprint search; persona never enters the base.
- `flutter_app/test/shared_memory_panel_test.dart` — roster chips per agent,
  needs-attention edge, fact detail side-by-side, sync-all refusals inline,
  drop-with-removal question.
- `flutter_app/test/memory_panel_test.dart` — extended: a drifted cluster
  shows the badge and Restore shared; the merge/keep/remove controls are
  unchanged.

---

## 10. Decisions, confirmed with the user on 2026-08-09

1. **Physical copies are required.** The shared base is a physical store on
   the device (the canonical copy, designed as the future cloud-sync source);
   every agent that receives a fact holds its own physical copy. "Shared" is
   one canonical store plus verified local copies — not a shared pointer.
2. **A separate Shared memory… panel**, with only the drift badge + Restore
   action added to the Memory panel.
3. **Hermes has a creation channel — agent-mediated.** Confirmed live: asking
   the agent to remember writes `MEMORY.md`, surfaces as `memory:memory:N`,
   and is read-back-verified. A fact Hermes cannot receive (approval gate,
   full memory) shows the reason and stays `missing`.
4. **Keep local is per-reading, not permanent.** The badge folds for this
   reading; the detector reports again next time. No divergence verdict is
   persisted.
5. **Drop asks** whether to also remove the app-owned copies (recommended) or
   leave them as ordinary memories.

Still open:

- **Hermes reword tolerance.** The probe landed near-verbatim (a suffix was
  appended). A sync that reads back a heavily reworded fact should not mark
  drift the moment it lands — the read-back should match by fingerprint
  *contains* rather than exact equality, and the anchor records the landed
  text. The exact tolerance is a Phase 2 calibration.
- **Cloud sync of the shared base** — deferred; the store is shaped for it.
