# Skills Bridge — one skill library, two agents

Hermes and OpenClaw each carry skills the other has never heard of, and there
is no one place to see what *both* of them can do. This is the design for
making Caduceus that place.

Sibling docs: `MEMORY_BRIDGE.md` (the memory bridge this is the sibling of),
`ARCHITECTURE.md` (the backend seam).

**Status: v1 built.** The read-only unified inventory — the abstraction in
`agent_core` (`SkillEntry`, `SkillCluster`, `AgentBackend.skillLibrary`), both
adapters, and the cross-agent panel (`SkillsPanel`, `Workspace.skillView`) —
is implemented and pinned by tests. §9 says where. What is *not* built is
anything that writes: install is registry-shaped and admin-scoped, and stays
out of v1 (§7).

Every claim about a gateway in this document was verified against live
servers on 2026-08-08 (Hermes on a remote server, OpenClaw on a local gateway)
with the read-only probes in `flutter_app/tool/probe_skills.dart` and
`flutter_app/tool/probe_hermes_skills.dart`. Sections are marked so verified
and inferred are never confused.

**A correction since the first draft:** "Hermes cannot be given a skill" was
too strong. `learning.add` is absent, but *installing* a skill is a different
method — `skills.manage {action: 'install'}` — and it exists (§2). What
neither side can do is accept arbitrary SKILL.md content; both install from a
registry.

---

## 1. The unifying fact

**A skill is a SKILL.md file with YAML frontmatter, on both platforms.** That
is what makes a bridge possible at all: the unit is the same, so a skill can
be named, described, compared and (sometimes) read in one vocabulary.

| | Hermes | OpenClaw |
| --- | --- | --- |
| Where a skill lives | a `learning.frames` node with `style: 'skill'` | a file at `<workspace>/skills/<dir>/SKILL.md` |
| Identity | the node id, which is the skill's name | `skillKey` / directory name |
| List | `learning.frames` (50 skill nodes live) or `skills.manage {action:'list'}` (grouped names) | `skills.status {}` (5 skills live, with eligibility + file path) |
| Read content | `learning.detail {id}` → the SKILL.md | `skills.detail {slug}` → **the ClawHub registry copy**, not the installed file |
| Update | `learning.edit {id, content}` | none at chat scope; `skills.get`/`skills.list`/`skills.read` refuse without `operator.admin` |
| Delete | `learning.delete {id}` — archives, restorable | none at chat scope |
| Create | `skills.manage {action:'install', query: <name>}` — installs from the skills.sh/GitHub registry; accepted at chat scope in a live probe (end-to-end install not exercised, deliberately) | `skills.install {slug}` — installs from ClawHub, `operator.admin`, and only by registry slug |

---

## 2. What the live gateways actually answer

Verified by probe, not by reading a schema.

**OpenClaw (`skills.status`)** — five skills, each with a verdict and a path:

```
agent-browser  eligible=true   workspace/skills/openclaw-agent-browser/SKILL.md
exa-search     eligible=false  workspace/skills/exa-search/SKILL.md      (needs node + EXA_API_KEY)
github         eligible=false  workspace/skills/github-api/SKILL.md      (needs MATON_API_KEY)
tavily         eligible=true   workspace/skills/tavily/SKILL.md
trim-cli       eligible=true   workspace/skills/sys-helper/SKILL.md
```

`skills.status` is `operator.read` and already returns, per skill: `name`,
`description`, `source`, `filePath`, `skillKey`, the eligibility flags
(`eligible`, `disabled`, `blockedByAllowlist`, `platformIncompatible`), the
`requirements`/`missing` blocks (bins, env, config — the *reason* it is off),
and `clawhub` metadata (slug, installed version).

**OpenClaw (`skills.detail`)** — is a *registry* call, not a file read:

- `tavily` → the full registry SKILL.md (9 942 chars) — readable at chat scope.
- `exa-search` → registry SKILL.md (1 001 chars).
- `github` / `agent-browser` → `409 AMBIGUOUS_SKILL_SLUG` (several owners on ClawHub).
- `trim-cli` / `sys-helper` → `404 Skill not found` (local workspace skills that were never published).

So on OpenClaw, skill *content* is readable at chat scope **only for
registry-published skills, and even then it is the registry copy, not the
installed one**. Local-only skills have no content path from this client.

**OpenClaw (`agents.files.*`)** — cannot reach skills at all, by design:

- `agents.files.list {agentId: 'main'}` returns the workspace root documents
  (`AGENTS.md`, `SOUL.md`, `USER.md`, `MEMORY.md`, …) and nothing under
  `skills/`.
- `agents.files.get {name: 'skills/tavily/SKILL.md'}` → `unsupported file`.
- The server-side allowlist is in the gateway source, not guessed:
  `ALLOWED_FILE_NAMES = new Set([...BOOTSTRAP_FILE_NAMES, 'MEMORY.md'])` — the
  bootstrap documents plus the memory file, nothing else. It applies to `set`
  as well as `get`, so the file API this client already uses for memory can
  never write a skill into place.

**OpenClaw — how skills actually get created.** The workspace `skills/`
directory is the operator's and the agent's filesystem territory; the gateway
does not expose it over RPC. Verified on a live gateway host: every installed skill
is a directory under `workspace/skills/` holding a `SKILL.md` (YAML
frontmatter: `name`, `description`, optional `metadata.openclaw`), plus
scripts and references. Three creation paths exist, and the first two are the
official ones:

1. **Manually** — create `workspace/skills/<name>/SKILL.md` (the operator, or
   the agent itself with its filesystem tools). `source: openclaw-workspace`
   skills — `trim-cli`, `sys-helper`, `tavily`, … — all got there this way.
2. **The CLI's Skill Workshop** — `openclaw skills workshop propose-create …`
   (proposal → review → apply), a human-reviewed flow.
3. **Admin RPCs from a client** — `skills.install` (from ClawHub, or a staged
   archive upload via `skills.upload.begin/chunk/commit` when the runtime
   config `skills.install.allowUploadedArchives` is on), `skills.update` to
   edit, `skills.proposals.*` for the workshop over RPC. Every one of these is
   `operator.admin`.

The boundary is therefore not "OpenClaw cannot create skills" — it creates
them all the time, by hand and by itself. The boundary is **this client**:
Caduceus connects as a remote device with no filesystem access and never asks
for `operator.admin`, so its only honest surface is the read side, and any
create-from-the-app feature has to go through the admin RPCs (§7).

**OpenClaw write path** — `skills.get` / `skills.list` / `skills.read` all
refuse at chat scope with `missing scope: operator.admin`, and the only
create-ish method is `skills.install`, which is admin and installs from
ClawHub by slug rather than accepting arbitrary SKILL.md content.

**Hermes** — `learning.detail` returns the SKILL.md for every skill node (50
live). `learning.edit` accepts a no-op write (verified `{ok: true}`);
`learning.delete` archives. **Adding a skill is
`skills.manage {action: 'install', query: <name>}`**, after
`skills.manage {action: 'search', query: <keyword>}` finds it in the
skills.sh / GitHub registry — both accepted at this connection's scope in a
live probe (the install echoes `{installed: true, name: <query>}`; an
end-to-end install was not exercised, deliberately, on a live server).
`learning.add` still answers `-32601 unknown method`: the *learning store* has
no create — installing a skill and the journey's learning nodes are different
things, and the nodes are made as the agent actually uses a skill.

---

## 3. The three facts that decide the architecture

1. **The unit is shared, the registries are not.** Both platforms speak
   SKILL.md, but a skill is born in Hermes' learning store or in OpenClaw's
   workspace/ClawHub, and neither client can read the other's store.

2. **Content is readable on one side for everything, on the other for almost
   nothing.** Hermes: every skill. OpenClaw: only registry-published skills,
   and then the registry copy. A bridge that promises "open any skill's
   SKILL.md" would fail on `trim-cli` and `sys-helper`.

3. **Both sides add skills by installing from a registry; neither accepts
   arbitrary content.** Hermes installs from the skills.sh / GitHub registry
   via `skills.manage install`, which works at chat scope. OpenClaw installs
   from ClawHub via `skills.install`, which needs `operator.admin`. Neither
   takes a SKILL.md you hand it — a skill gets in by being *published
   somewhere that side's registry knows*. The asymmetry is scope (Hermes:
   open; OpenClaw: admin), not existence. Two-way *content* sync is not a
   feature that can be built on these contracts; two-way *registry* install is
   possible wherever the skill is published.

Consequence, stated plainly: **v1 is a read-only unified inventory.** "See
everything both agents can do, in one place, and which one has what" is the
feature — exactly the memory bridge's phase 1, for skills. Writes are out of
scope for the same reason the memory bridge started write-free: an honest
v1 ships the view, and the write asymmetry is stated in the UI rather than
hidden behind a button that fails.

---

## 4. The model

```dart
/// One skill as seen by one agent. A row is an *instance*: the same skill on
/// Hermes and on OpenClaw is two entries that a cluster joins by key.
class SkillEntry {
  final String key;          // the cross-backend key: skill name / skillKey
  final String title;        // displayName when present, else the key
  final String description;  // the short description, not the body
  final SkillOrigin origin;  // hermes | openclaw
  final String nativeId;     // Hermes node id, or OpenClaw slug / directory
  final bool eligible;       // Hermes: always true; OpenClaw: `eligible`
  final String? detail;      // why not: "missing bin: gh", version, source
  final String? content;     // the SKILL.md when readable (Hermes: always;
                             // OpenClaw: only registry-published, registry copy)
  final String? filePath;    // OpenClaw only — where the installed file lives
}
```

This is a **new type**, not a reuse of `AgentSkill` or `MemoryKind.skill`:

- `AgentSkill` (inventory.dart) is a flat per-backend inventory row with no
  identity and no content — it is the *current* `skills(SessionHandle)`
  answer. The bridge needs identity, provenance and content, which are three
  different things.
- `MemoryKind.skill` is a *memory* the bridge already pushes around. A skill
  is not a memory: it is capability inventory, re-fetched per open, and it
  must not be conflated with "what the agent knows about you". (The memory
  panel's "What it has learned to do" section stays; this is a different
  surface with a different question.)

---

## 5. Matching strategy

The memory bridge's rule applies: **a duplicate is visible and annoying, a
wrong merge silently discards a fact.** For skills the stakes are lower
(read-only), but the discipline is the same.

- **Primary key: exact `key` match** — Hermes node id (`agent-browser`) vs
  OpenClaw `skillKey` (`agent-browser`). Case-normalised.
- **Near-miss suggestions, never auto-join**: `github` (Hermes) vs `github`
  (OpenClaw, dir `github-api`) match exactly on key; `web-search` vs
  `exa-search`/`tavily` do not, and a person's ruling (reuse the memory
  ledger's `MemoryVerdict` mechanism) wins in both directions.
- **Content fingerprint** as *secondary* evidence only, and only when both
  contents are readable — which, given §2, is rare enough that v1 matches on
  key and leaves content comparison for the detail view.

---

## 6. The UI

**A new panel: "Skills — what each agent can do"** (proposed; the alternative
is a tab inside the Memory panel, see §8).

Interaction model mirrors the memory panel, which the repo already knows how
to do well:

- **Entry**: session menu `…` → `Skills…` and ⌘K → `Skills…`, gated on
  `Capability.skills` of the connected backend (both platforms already
  declare it).
- **Sources chips**: `hermes · live` / `openclaw · live` — the same
  freshness vocabulary as the memory panel. No ledger in v1: skills are live
  inventory, re-fetched per open, so there is nothing to snapshot (the memory
  ledger exists because memory must be visible offline; a skill library does
  not need that).
- **Reach out**: the same "Ask every agent" pattern — connected tabs first
  (`AgentTabs.connectedBackends`), a pool only for servers with no tab open.
- **Divergence bar**: "N skills are known to one agent and not the other"
  with `Show only these` / `Show all` — the memory panel's exact control.
- **Per skill**: name + displayName, origin badges, eligibility with the
  *reason* ("missing bin: gh", "needs EXA_API_KEY") — OpenClaw already gives
  the evidence and the repo already renders it in the server panel — and a
  content viewer (read-only, monospace SKILL.md) when `content` is readable.
- **No write controls in v1.** The panel says what a skill *is*; it does not
  pretend to move skills between agents.

---

## 7. What is deliberately not v1

- **Teaching a skill from one agent to the other.** Both directions are
  *registry* installs, not content pushes. OpenClaw → Hermes works for any
  skill published where Hermes installs from (skills.sh / GitHub), and needs
  no special scope; Hermes → OpenClaw works for skills published on ClawHub,
  and needs requesting `operator.admin` — a scope change this client has
  deliberately never made. Publishing is the bottleneck, and it is a human
  act, not a client one — so the honest v1 is the read-only inventory, and
  install is a later, registry-shaped feature. (On OpenClaw the operator can
  skip publishing entirely: dropping a `SKILL.md` into `workspace/skills/` is
  the manual path, but that is filesystem work on the gateway host, not something a
  remote client does.)
- **Editing an OpenClaw skill.** Needs admin plus a local-file path the
  gateway does not expose to this client.
- **Background sync / auto-install.** The memory bridge's R4 applies here
  too: nothing happens without the person asking.
- **Content diffing between registry and installed copies.** `skills.detail`
  is the registry copy; the installed file is not readable at chat scope, so
  a diff would compare two different things.

---

## 8. What is built, and where

The v1 read-only inventory, verified by tests rather than by a live session:

```
packages/agent_core/
  lib/src/skill.dart         SkillEntry, SkillCluster, clusterSkills
  lib/src/backend.dart       AgentBackend.skillLibrary() — behind Capability.skills
  test/skill_test.dart       key matching, near-miss separation, missingFrom

flutter_app/
  lib/backends/hermes_backend.dart  skillLibrary(): learning.frames skill nodes,
                                    content via learning.detail (concurrent,
                                    best-effort), description from frontmatter
  lib/backends/claw_backend.dart    skillLibrary(): skills.status + per-skill
                                    skills.detail (registry copy, best-effort),
                                    eligibility evidence, file path
  lib/workspace.dart                skillView({reachOut, peers}) — the same
                                    tab-reuse and unreachable rules as memoryView
  lib/skills_panel.dart             the panel: sources, divergence filter,
                                    per-skill provenance, content viewer
  test/skills_panel_test.dart       widget tests
  test/skill_view_test.dart         workspace view tests
  test/hermes_backend_test.dart     adapter tests
  test/claw_backend_test.dart       adapter tests
  tool/verify_bridge_live.dart      live check: both adapters' libraries +
                                    clustering against the real gateways
```

Reached from the session menu's **… → Skills…** and ⌘K → **Skills…**, gated on
`Capability.skills` (which both backends already declare).

---

## 8b. Open questions for confirmation


1. **Scope** — read-only unified inventory (recommended), or should the panel
   also attempt ClawHub-backed installs (requires requesting `operator.admin`
   on OpenClaw, changes the pairing posture)?
2. **Where it lives** — a separate `Skills` panel (recommended), or a tab
   inside the existing Memory panel?
3. **Content** — show the SKILL.md viewer where readable (recommended), or
   names/descriptions only?
4. **Matching** — exact key with near-miss suggestions (recommended), or also
   content-fingerprint joining?
5. **Persistence** — live-only, re-fetched per open (recommended), or a
   snapshot ledger like memory?

Every claim above that says "verified" was checked against the live gateways
with the probes committed alongside this document; nothing inferred is
presented as fact.
