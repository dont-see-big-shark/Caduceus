# Agent Graph — who knows whom

The memory bridge answers "what does each agent know" one entry at a time.
The skills bridge answers "what can each agent do" one skill at a time.
This is the layer above both: the view organised by **agent** rather than by
item, where a fleet is a set of nodes and a divergence is a visible edge —
and where "push this over" is offered from the relationship itself instead of
from a per-item diff.

Sibling docs: `MEMORY_BRIDGE.md` (the memory bridge this projects),
`SKILLS_BRIDGE.md` (the skills bridge this projects), `ARCHITECTURE.md`
(the backend seam).

**Status: built and live-verified.** The projection (`agent_graph.dart`), the
panel (`fleet_panel.dart`), the push (`Workspace.applyMemory` to any target),
and the entries (session menu `…` and ⌘K → **Fleet…**) are implemented and
pinned by `packages/agent_core/test/agent_graph_test.dart` (11 tests) and
`flutter_app/test/fleet_panel_test.dart` (7 widget tests). The projection was
verified against the live gateways on 2026-08-09 with
`tool/verify_bridge_live.dart` (§8b). As designed, the graph reads nothing
new — it projects `memoryView` + `skillView` + the saved-server list.

The current fleet, measured live: Hermes 63 memories / 50 skills, OpenClaw
1 memory / 5 skills, **0 shared memories, 2 shared skills, both nodes lone**
— an asymmetric pair, which is the normal real-world shape and the one this
view exists to make legible.

---

## 1. What this is, and what it deliberately is not

**It is** a relationship layer. One screen that says, of every agent in the
fleet: *who is connected, what it knows, what it can do, what it alone has,
what it is missing, and who else shares it.* The unit of attention is the
agent, not the row.

**It is not** a third diff. The memory panel already shows entry-level
divergence and the skills panel already shows skill-level divergence. The
graph aggregates those verdicts per agent and per pair, so "Hermes knows 62
things, OpenClaw knows 8, they share 3, and Hermes alone has 5 skills that
would run on OpenClaw" is answerable in one glance.

**It is not** a canvas. No node-graph rendering engine, no force layout, no
zoomable topology. A roster of cards plus explicit link rows carries the same
information with better density, accessibility, and testability — and a
"graph" that needs a mouse to read is a chart, not a client.

**It is not** a synchroniser. It pushes only when a person asks, exactly like
the two bridges it sits on. Nothing reconciles in the background.

Scope for v1, proposed:

- **The relationship view** — nodes for every saved server, links between
  every pair, per-agent detail, per-item cross-agent view.
- **Memory push from the graph** — reuses the existing `applyMemory` path.
- **Skills: read + guidance only.** The honest v1 is the same as
  `SKILLS_BRIDGE.md` §7: Hermes can *install* from a registry at chat scope,
  OpenClaw installs are admin-scoped or host-filesystem work, so the graph
  says what a skill is and how it would get there, and does not pretend to
  move it. A registry-shaped push is a v2 decision (§7).

**Confirmed with the user on 2026-08-09:** name **Fleet…**, roster + link
rows (no canvas), all saved servers in the fleet, memory push from the
graph, skills guidance-only — and the panel is designed for the phone first:
the sheet navigates inside itself (no stacked routes), the roster is one
column under 560 px, and every card is a full-width tap target.

---

## 2. Why this data is free

The graph makes **no new gateway calls**. Everything it shows comes from two
reads the client already makes, plus the saved-server list it already keeps:

| Source | Already built in | What the graph takes |
| --- | --- | --- |
| `ConnectionStore.list()` | connection_store.dart | the fleet's membership: every saved server, its `label`, its `backendId` |
| `AgentTabs.connectedBackends` + `MemoryPeers` | agent_tabs.dart, workspace.dart | which servers are already open as tabs, so the graph asks them first and never opens a second socket |
| `Workspace.memoryView({reachOut, peers})` | workspace.dart | `MemoryView` — clusters, per-backend freshness (`sources`), `unreachable` |
| `Workspace.skillView({reachOut, peers})` | workspace.dart | `SkillLibraryView` — clusters, `liveBackendIds`, `unreachable` |
| `MemoryCluster` / `SkillCluster` | agent_core | `backends`, `missingFrom`, `isShared` — the relationship atoms |
| `Workspace.applyMemory` | workspace.dart | the v1.5 push path, with its staleness guard and per-change refusals |

The one new cost is a `reachOut` read for servers that are saved but not
open — the same pool + `MemoryPeers` dance `memoryView`/`skillView` already
perform. The graph is **a projection, not a pipeline**, and that is what
keeps it honest: it cannot know less than the bridges, because it reads
through them.

Current fleet profile, measured by `tool/verify_bridge_live.dart`
(2026-08-08, the two live gateways): Hermes 62 memories + 50 skills,
OpenClaw 1 memory + 5 skills, one skill shared (`agent-browser`). That is
the shape the graph must make legible: a pair with a deep asymmetry, which
is the normal real-world case and the one a per-item diff hides.

---

## 3. The model

Pure and testable, in `agent_core` beside the cluster types it projects.
Nothing here talks to a gateway.

```dart
enum AgentPresence {
  live,        // read just now through the connected tab / reach-out
  tab,         // open as a tab; asked first, not re-read by the pool
  saved,       // in the store, not connected — shown as offline, never as live
  unreachable, // asked and could not answer; why is in the view
}

class AgentNode {
  final String backendId;          // 'hermes' | 'openclaw'
  final String label;              // SavedConnection.displayLabel, else backendLabel
  final AgentPresence presence;
  final int memoryEntryCount;      // entries this agent holds
  final int skillCount;            // skills this agent can run (eligible)
  final List<MemoryCluster> memory; // for the detail pane
  final List<SkillCluster> skills;  // for the detail pane
}

class AgentLink {
  final String a; final String b;   // sorted backendId pair
  final int sharedMemory;           // clusters present on both
  final int sharedSkills;
  final int aOnlyMemory; final int bOnlyMemory;   // divergent, per side
  final int aOnlySkills; final int bOnlySkills;
}

class AgentGraph {
  final List<AgentNode> nodes;
  final List<AgentLink> links;
  final Map<String, String> unreachable;  // server -> why, the bridges' own vocabulary
}
```

Derivation rules, stated so they can be argued with:

- **Shared vs unique is decided at cluster level.** A `MemoryCluster` /
  `SkillCluster` whose `backends` contains both agents is shared; one whose
  copies all live on a single agent is that agent's alone. An entry that
  exists twice on one side and once on the other is still shared — the
  cluster already represents "one fact, N copies".
- **Counts are entry counts, divergence is cluster counts.** A node's
  `memoryEntryCount` is how many `MemoryEntry`s that agent holds (what a
  person means by "how much does it know"); a link's `sharedMemory` is how
  many *facts* are known on both sides (what a person means by "how much do
  they agree"). The two denominators are different on purpose and the panel
  labels them so.
- **Links exist only between nodes that are in the same read.** A saved-but-
  offline server gets a node and no links until it answers — an edge to a
  server that never spoke would assert a comparison nobody could verify.
- **One agent ⇒ nodes with no links. Zero agents ⇒ empty state**, the same
  "nothing to compare" the bridges already render.

---

## 4. The view

A new panel, reached the same way the two bridges are: session menu `…` and
⌘K, gated on `Capability.memoryRead || Capability.skills` (a server that can
do neither has no graph). Proposed name **Fleet…** — `Agents…` is taken by
Hermes subagents (`agents_panel.dart`), and the graph is about the
relationship, not about one server's delegation.

Three depths, one entry:

**1. Roster — the nodes and the edges.** One card per agent: presence dot
(the same live/tab/offline/unreachable vocabulary as the memory panel's
source chips), label, memory count, skill count, and a **lone** marker when
the agent holds something nobody else does (§5). Between the cards, one link
row per pair: `hermes ↔ openclaw · 3 facts shared · 59 hers only · 1 its
only · 45 skills hers only`. The pair is the unit a person actually acts on;
a canvas would hide it, a roster row shows it.

**2. Agent detail.** Tap a node: *knows* (memory grouped by `MemoryKind`,
expandable to full text), *can do* (skills with eligibility and the reason an
ineligible one is off), and *missing* — clusters `missingFrom` this agent
that another agent has, each with a push affordance when the target can
receive it (§5).

**3. Item cross-view.** Tap any cluster in a detail pane: *who has it, who
does not, who could not be asked* — the memory panel's exact three-way
distinction — and the push control. This is the graph's answer to "I can see
OpenClaw is missing `tavily`; make it so", which today requires opening the
skills panel and knowing what to look for.

Unreachable servers never vanish and never masquerade: the roster shows
their node greyed with the reason, exactly as the bridges' banners do.

---

## 5. Push

**Memory — real, now.** The graph's push calls the same
`Workspace.applyMemory([MemoryChange(MemoryOp.add, cluster.best)])` path the
memory panel's `_push` uses, with the same diff preview, the same staleness
guard, the same per-change refusal rendering, and the same "re-read after
write" so the next projection reflects what the server actually accepted.
The only difference is the entry point: instead of opening Memory… and
scrolling, the user sees "OpenClaw is missing *X*" in the roster and pushes
from there. Tab-first reach-out (`MemoryPeers`) applies unchanged.

**Skills — guidance now, install later.** Both directions are registry
installs, not content pushes, and publishing is a human act
(`SKILLS_BRIDGE.md` §7). So v1 shows, on a missing skill, *how it would get
there*: to Hermes via `skills.manage {action:'install', query}` (chat scope,
works today), to OpenClaw via ClawHub (needs `operator.admin`, which this
client has never requested) or the host `workspace/skills/` manual path. The
UI says "OpenClaw cannot take this from the client yet" rather than offering
a button that can only be refused. A registry-shaped install is the v2
decision at the end of this document — the abstraction the graph needs for
it (`SkillCluster` + `missingFrom`) is already in place.

---

## 6. What is deliberately not v1

- **A rendering engine.** No canvas, no zoom, no pan. Roster + link rows.
- **Background reconciliation or auto-sync.** The bridges' R4 rule: nothing
  happens without the person asking.
- **Skills install / content push.** §5, above; requires the admin-scope or
  host-filesystem decision.
- **Transcript / working-context edges.** "Who has this conversation open"
  is a real feature and is explicitly out of scope for both bridges (§1 of
  `MEMORY_BRIDGE.md`); the graph inherits that boundary.
- **A third backend's protocol.** The graph is backend-agnostic by
  construction (it reads `AgentBackend`s), but v1 is verified against the
  two this client has.
- **Persisting the graph.** It is a projection of live reads + the saved
  list, recomputed per open; there is no graph ledger to keep fresh.

---

## 7. Phases

- **Phase 1 — read-only graph.** `agent_core`: `AgentGraph` projection from
  `MemoryView` + `SkillLibraryView` + the saved list, all pure and tested.
  `flutter_app`: `Fleet` panel with roster, links, agent detail, item
  cross-view; gated entry in the session menu and ⌘K.
- **Phase 2 — memory push from the graph.** Reuse `applyMemory`; inline
  refusals exactly as the memory panel renders them.
- **Phase 3 — skills install (registry-shaped).** Hermes `skills.manage
  install` is chat-scope and live-verified; OpenClaw needs the admin-scope
  decision. Until the user confirms that posture change, v1 ships the
  guidance text and no button.

---

## 8. Tests

- `packages/agent_core/test/agent_graph_test.dart` (11) — projection from
  hand-built memory/skill cluster pairs and saved-list fakes: shared vs
  unique at cluster level, entry-vs-cluster denominators, links only for
  answered servers, single-agent cases, presence mapping, the lone marker.
- `flutter_app/test/fleet_panel_test.dart` (7) — widget tests: the roster
  shows every agent, the edge, and the lone marker; unreachable shown not
  dropped; the detail lists what is missing and offers the push; the push
  goes through `applyMemory` with refusals inline; a target that cannot
  receive offers no control; the cross view says who has it and who does
  not; skills are read-only guidance.
- `tool/verify_bridge_live.dart` — prints the graph summary (nodes, links,
  lone markers) against the real gateways; the same one command that
  verifies the bridges verifies the projection (ran 2026-08-09).

---

## 9. Open questions for confirmation

1. **Name** — `Fleet…` (proposed), `Agent Graph…`, or merge into an
   existing panel?
2. **Canvas or roster** — I recommend roster + link rows (no rendering
   engine); say so if you want a drawn topology instead.
3. **Lone marker** — my proposal: an agent gets the **lone** marker when it
   holds at least one skill no other agent has, or more than half its memory
   is unique. Calibrate against the real profile before shipping.
4. **Skills push** — confirm v1 is guidance-only and Phase 3 (registry
   install, including the OpenClaw admin-scope question) waits for your
   decision.
5. **Scope of "fleet"** — all saved servers (proposed), or only servers with
   an open tab? Saved-but-offline nodes are the difference between "this is
   my fleet" and "this is what I happen to have open".
