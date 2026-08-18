import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import 'backends/claw_memory.dart';
import 'design/press.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'memory_ledger.dart';
import 'widgets/menu_card.dart';
import 'widgets/panel_frame.dart';
import 'workspace.dart';

/// What this agent remembers.
///
/// Phase 1 of `MEMORY_BRIDGE.md`, and deliberately read-only. The value of
/// this screen alone — *everything one agent knows about me, in one place* —
/// is the thing worth confirming before any of the write machinery is built.
///
/// The two backends fill it very differently and the screen does not hide
/// that. Hermes has a learning journey of many small nodes; OpenClaw has a
/// handful of markdown documents. Grouping by [MemoryKind] rather than by
/// backend vocabulary is what makes them sit side by side without either
/// being described in the other's words.
class MemoryPanel extends StatefulWidget {
  const MemoryPanel({
    required this.workspace,
    this.embedded = false,
    this.peers = MemoryPeers.none,
    super.key,
  });

  final Workspace workspace;

  /// Already-open tabs the bridge can ask without a handshake.
  final MemoryPeers peers;

  /// Render inside a parent surface (right panel rail) instead of a
  /// dialog/sheet. See [Panel.embedded].
  final bool embedded;

  @override
  State<MemoryPanel> createState() => _MemoryPanelState();
}

/// The order the sections appear in, and what each is called.
///
/// Persona first: it is the smallest group and the one that frames the rest —
/// who the agent thinks it is, and who it thinks you are.
const _kindLabels = <MemoryKind, String>{
  MemoryKind.persona: 'Who it thinks we are',
  MemoryKind.fact: 'What it knows',
  MemoryKind.preference: 'How you like to work',
  MemoryKind.project: 'What you are working on',
  MemoryKind.skill: 'What it has learned to do',
};

class _MemoryPanelState extends State<MemoryPanel> {
  MemoryView? _view;
  String? _error;

  /// Refusals from the last write, shown inline rather than blanking the
  /// whole panel. A partial push is a finding, not a failure of the screen.
  String? _notice;
  String? _expanded;

  /// Show only what one agent has and another does not.
  ///
  /// The question the bridge exists for, and a filter rather than a separate
  /// screen — the same rows, narrowed, so the answer is checkable against the
  /// full list without navigating away.
  bool _onlyDivergent = false;

  /// Shared facts whose copy on this agent has drifted from the canonical
  /// wording (`SHARED_MEMORY.md`). Shown as evidence on the rows it touches;
  /// the resolution controls live in the Shared memory panel.
  List<SharedFact> _drifted = const [];

  /// Whether the drift bar's list is expanded.
  bool _showDrifted = false;

  /// True while the other saved servers are being opened.
  bool _reaching = false;

  /// True while a push is in flight.
  bool _pushing = false;

  Workspace get _ws => widget.workspace;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [reachOut] opens the other saved servers so their memory is read now
  /// rather than recalled. Not the default: it pays a full handshake — and on
  /// OpenClaw a pairing check — per server, which is not something a panel
  /// should do every time it opens.
  Future<void> _load({bool reachOut = false}) async {
    setState(() {
      _error = null;
      _notice = null;
      _reaching = reachOut;
    });
    try {
      final view = await _ws.memoryView(
        reachOut: reachOut,
        peers: widget.peers,
      );
      final drifted = await _driftedOnMe(view);
      if (mounted) {
        setState(() {
          _view = view;
          _drifted = drifted;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    } finally {
      if (mounted) setState(() => _reaching = false);
    }
  }

  /// Shared facts whose copy on the connected agent has drifted.
  ///
  /// Uses the same detector as the Shared memory panel, scoped to this agent —
  /// the badge here is the evidence; the side-by-side and Restore/Keep live
  /// in the Shared memory panel.
  Future<List<SharedFact>> _driftedOnMe(MemoryView view) async {
    final result = <SharedFact>[];
    final facts = await _ws.ledger.sharedFacts();
    for (final fact in facts) {
      final states = detectFactStates(
        fact: fact,
        clusters: view.clusters,
        knownBackends: {_ws.backend.id},
        unreachable: view.unreachable,
        anchors: await _ws.ledger.anchorsFor(fact.id),
      ).byBackend;
      if (states[_ws.backend.id]?.status == AgentFactStatus.drifted) {
        result.add(fact);
      }
    }
    return result;
  }

  /// The clusters this agent is missing that could be given to it.
  ///
  /// Gated three ways, and each gate removes a way to offer a button that
  /// fails: the backend must support writing at all, it must support `add`
  /// (Hermes never will — there is no `learning.add`), and the memory must
  /// actually be absent here.
  List<MemoryCluster> _pushable(MemoryView view) {
    if (!_ws.supports(Capability.memoryWrite)) return const [];
    if (!_ws.memoryOps.contains(MemoryOp.add)) return const [];
    final me = _ws.backend.id;
    return [
      for (final cluster in view.clusters)
        // Persona documents are excluded here on purpose. Pushing one is a
        // whole-file overwrite, not an addition, and folding it into "teach
        // it N memories" would hide a destructive act inside an additive
        // sentence. It gets its own control — see [_replaceable].
        if (cluster.best.kind != MemoryKind.persona &&
            cluster.missingFrom({me}).isNotEmpty)
          cluster,
    ];
  }

  /// Persona documents another agent has and this one could be given.
  ///
  /// Separate from [_pushable] because the operation is different in kind:
  /// this **replaces** `SOUL.md` rather than adding to a list, and the
  /// wording, the confirmation and the undo all have to say so.
  List<MemoryCluster> _replaceable(MemoryView view) {
    if (!_ws.supports(Capability.memoryWrite)) return const [];
    if (!_ws.memoryOps.contains(MemoryOp.update)) return const [];
    final me = _ws.backend.id;
    return [
      for (final cluster in view.clusters)
        if (cluster.best.kind == MemoryKind.persona &&
            cluster.missingFrom({me}).isNotEmpty)
          cluster,
    ];
  }

  /// The connected backend's copy of [cluster] that this app may remove.
  ///
  /// Null when there is nothing removable here. Three gates, each removing a
  /// way to offer a button that fails: the backend must support `remove` at
  /// all, the entry must be one this app owns (inside OpenClaw's block — R2 —
  /// or a Hermes node this ledger has an address for), and persona documents
  /// are never deletable from here, because deleting `SOUL.md` is not
  /// forgetting a memory, it is breaking the agent.
  MemoryEntry? _removable(MemoryCluster cluster) {
    if (!_ws.supports(Capability.memoryWrite)) return null;
    if (!_ws.memoryOps.contains(MemoryOp.remove)) return null;
    for (final entry in cluster.entries) {
      if (entry.origin.backendId != _ws.backend.id) continue;
      if (entry.kind == MemoryKind.persona) return null;
      if (entry.origin.nativeId.isEmpty) return null;
      if (_ws.backend.id == 'openclaw' &&
          !entry.tags.contains(clawManagedTag)) {
        return null;
      }
      return entry;
    }
    return null;
  }

  /// The clusters [cluster] could be merged with: same kind, not itself.
  List<MemoryCluster> _mergeCandidates(
    MemoryView view,
    MemoryCluster cluster,
  ) => [
    for (final other in view.clusters)
      if (other.id != cluster.id && other.best.kind == cluster.best.kind) other,
  ];

  /// Whether [cluster] can be split apart. Two backends' wordings of "the
  /// same" fact are exactly what a person must be able to un-join.
  bool _canSplit(MemoryCluster cluster) =>
      cluster.backends.length >= 2 && cluster.entries.length >= 2;

  /// Records that two clusters are one fact, after the person says so.
  ///
  /// The fingerprint is deliberately conservative, so two agents rarely word a
  /// fact identically and the *usual* case is that the person has to say
  /// "these are the same". This is that control.
  Future<void> _merge(MemoryCluster cluster, MemoryView view) async {
    final candidates = _mergeCandidates(view, cluster);
    if (candidates.isEmpty) return;
    final other = await showDialog<MemoryCluster>(
      context: context,
      builder: (context) => Panel(
        title: Text('Merge "${cluster.best.label}" with…'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 300),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in candidates)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${c.best.label} — ${c.backends.join(", ")}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    onTap: () => Navigator.of(context).pop(c),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (other == null || !mounted) return;

    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: const Text('These are the same memory?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 300),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in cluster.entries) ...[
                  Text(
                    e.origin.backendId,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  SelectableText(
                    e.text,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                ],
                for (final e in other.entries) ...[
                  Text(
                    e.origin.backendId,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  SelectableText(
                    e.text,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  'They are shown one above the other so the wording can be '
                  'compared before they are joined. This ruling is kept.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.ink.tertiary),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('They are the same'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    setState(() => _pushing = true);
    try {
      for (final a in cluster.entries) {
        for (final b in other.entries) {
          await _ws.ruleMemory(a.origin, b.origin, same: true);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    } finally {
      if (mounted) setState(() => _pushing = false);
      await _load();
    }
  }

  /// Records that one cluster is really several facts, after the person says so.
  ///
  /// The fingerprint joins what it can, and "likes tea" vs "dislikes tea" is
  /// the case it is deliberately built not to join — but there are pairs it
  /// *does* join that a person knows are different. This is that safety valve,
  /// surfaced instead of left in code.
  Future<void> _split(MemoryCluster cluster) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: const Text('Keep these separate?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 300),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'They are currently shown as one memory. Each copy below '
                  'becomes its own entry, and the ruling is kept.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final e in cluster.entries) ...[
                  Text(
                    e.origin.backendId,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  SelectableText(
                    e.text.length > 240
                        ? '${e.text.substring(0, 240)}…'
                        : e.text,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keep separate'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    setState(() => _pushing = true);
    try {
      final entries = cluster.entries;
      for (var i = 0; i < entries.length; i++) {
        for (var j = i + 1; j < entries.length; j++) {
          if (entries[i].origin.backendId == entries[j].origin.backendId) {
            continue;
          }
          await _ws.ruleMemory(
            entries[i].origin,
            entries[j].origin,
            same: false,
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    } finally {
      if (mounted) setState(() => _pushing = false);
      await _load();
    }
  }

  /// Removes the connected backend's copy of [cluster] — the one write the
  /// bridge was missing. Wording and undo depend on what it is:
  ///
  ///  * a Hermes skill is **archived** on the server (restorable there);
  ///  * a Hermes memory is deleted outright and cannot be undone;
  ///  * an OpenClaw entry inside this app's block is removed from the block,
  ///    and the app can put it straight back.
  Future<void> _remove(MemoryCluster cluster) async {
    final entry = _removable(cluster);
    if (entry == null) return;
    String? notice;
    final isHermes = _ws.backend.id == 'hermes';
    final isSkill = entry.kind == MemoryKind.skill;
    final title = isHermes
        ? (isSkill ? 'Archive skill?' : 'Delete memory?')
        : 'Remove memory?';
    final content = isHermes
        ? (isSkill
              ? '"${entry.label}" is archived on the server and can be '
                    'restored there.'
              : '"${entry.label}" is removed from the agent\'s memory. '
                    'This cannot be undone.')
        : '"${entry.label}" is removed from the block this app owns in the '
              "agent's memory file. Nothing outside that block is touched, "
              'and it can be brought back.';

    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isHermes ? (isSkill ? 'Archive' : 'Delete') : 'Remove'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    setState(() => _pushing = true);
    try {
      final result = await _ws.applyMemory([
        MemoryChange(MemoryOp.remove, entry),
      ]);
      if (!mounted) return;
      if (result.refused.isNotEmpty) {
        notice = result.refused.map((o) => o.detail).join('\n');
      } else if (!isHermes) {
        _offerRemoveUndo(entry);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    } finally {
      if (mounted) setState(() => _pushing = false);
      await _load();
      if (mounted && notice != null) setState(() => _notice = notice);
    }
  }

  /// The undo for an OpenClaw removal, offered at the moment it is wanted.
  ///
  /// The removed entry is put straight back through [Workspace.applyMemory] —
  /// the same write path, so the same staleness guard applies to the restore
  /// as to the removal.
  void _offerRemoveUndo(MemoryEntry entry) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${entry.label} removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await _ws.applyMemory([MemoryChange(MemoryOp.add, entry)]);
            } catch (e) {
              if (mounted) setState(() => _error = _ws.describeFailure(e));
            }
            await _load();
          },
        ),
      ),
    );
  }

  /// Replaces one workspace document with another agent's.
  ///
  /// Worded as replacement throughout, and it names what is being destroyed.
  /// "Teach it" would be a lie here: nothing is added, one file becomes
  /// another. The undo offered afterwards is what makes it reasonable to
  /// agree to at all.
  Future<void> _replacePersona(MemoryCluster cluster) async {
    final name = cluster.best.title;
    String? notice;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text('Replace $name on ${_ws.backend.displayName}?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 340),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This overwrites the whole document with '
                  "${cluster.backends.join(", ")}'s version. Unlike a memory, "
                  'a profile document has no block to add to — what is there '
                  'now is replaced.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'The previous version is kept, so this can be undone.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.ink.tertiary),
                ),
                const SizedBox(height: 14),
                SelectableText(
                  cluster.best.text,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    setState(() => _pushing = true);
    try {
      final result = await _ws.applyMemory([
        MemoryChange(
          MemoryOp.update,
          cluster.best.copyWith(
            origin: MemoryOrigin(backendId: _ws.backend.id, nativeId: name),
          ),
        ),
      ]);
      if (!mounted) return;
      if (result.refused.isNotEmpty) {
        notice = result.refused.single.detail;
      } else {
        _offerUndo(name);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    } finally {
      if (mounted) setState(() => _pushing = false);
      await _load();
      // The reload clears _notice; the refusal must outlive it or the banner
      // would never be seen.
      if (mounted && notice != null) setState(() => _notice = notice);
    }
  }

  /// The undo, offered at the moment it is wanted.
  ///
  /// A backup nobody knows about is not an undo. It is mentioned in the
  /// confirmation and then offered again here, while the change is the last
  /// thing that happened.
  void _offerUndo(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name replaced'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await _ws.undoPersona(name);
            } catch (e) {
              if (mounted) setState(() => _error = _ws.describeFailure(e));
            }
            await _load();
          },
        ),
      ),
    );
  }

  /// Shows the diff, and pushes only if the person says so.
  ///
  /// `MEMORY_BRIDGE.md` R4: nothing happens in the background, and nothing
  /// happens without a preview. The dialog lists every memory by name because
  /// "12 memories" is not something anyone can consent to.
  Future<void> _push(MemoryView view) async {
    final clusters = _pushable(view);
    String? notice;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text(
          'Teach ${_ws.backend.displayName} ${clusters.length} '
          'memor${clusters.length == 1 ? 'y' : 'ies'}?',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'These are written into a block this app owns in the '
                  "agent's memory file. Nothing you or the agent wrote "
                  'outside that block is touched.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                for (final cluster in clusters)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '+ ${cluster.best.label}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Teach it'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    setState(() => _pushing = true);
    try {
      final result = await _ws.applyMemory([
        for (final cluster in clusters)
          MemoryChange(MemoryOp.add, cluster.best),
      ]);
      if (!mounted) return;
      // Every refusal is reported, inline rather than blanking the panel. A
      // push that silently half-worked is how a person comes to believe an
      // agent knows something it does not.
      if (result.refused.isNotEmpty) {
        notice = result.refused
            .map((o) => '${o.change.entry.label}: ${o.detail}')
            .join('\n');
      }
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    } finally {
      if (mounted) setState(() => _pushing = false);
      await _load();
      if (mounted && notice != null) setState(() => _notice = notice);
    }
  }

  List<MemoryCluster> get _shown {
    final view = _view;
    if (view == null) return const [];
    return _onlyDivergent ? view.divergent : view.clusters;
  }

  List<MemoryKind> get _kinds => [
    for (final kind in _kindLabels.keys)
      if (_shown.any((c) => c.best.kind == kind)) kind,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      embedded: widget.embedded,
      title: Row(
        children: [
          const Expanded(child: Text('Memory')),
          if (_reaching)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          // Opening the other servers is a separate act from reloading this
          // one, and it costs a handshake each — so it is its own control
          // rather than something a refresh does silently.
          TextButton(
            onPressed: _reaching ? null : () => _load(reachOut: true),
            child: const Text('Ask every agent'),
          ),
          IconButton(
            onPressed: _reaching ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: 'Reload',
          ),
        ],
      ),
      content: PanelFrame(
        child: switch ((_error, _view)) {
          (final String message, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
          (_, null) => const Center(child: CircularProgressIndicator()),
          (_, final MemoryView view) when view.isEmpty => _EmptyMemory(
            backendName: _ws.backend.displayName,
          ),
          (_, final MemoryView view) => _body(theme, view),
        },
      ),
    );
  }

  Widget _body(ThemeData theme, MemoryView view) => Column(
    children: [
      _Sources(view: view),
      if (_drifted.isNotEmpty)
        _DriftedBar(
          facts: _drifted,
          open: _showDrifted,
          onToggle: () => setState(() => _showDrifted = !_showDrifted),
        ),
      if (view.unreachable.isNotEmpty) _Unreachable(view: view),
      if (view.divergent.isNotEmpty)
        _DivergenceBar(
          count: view.divergent.length,
          only: _onlyDivergent,
          onToggle: () => setState(() => _onlyDivergent = !_onlyDivergent),
        ),
      for (final cluster in _replaceable(view))
        _ReplaceBar(
          name: cluster.best.title,
          from: cluster.backends.join(', '),
          busy: _pushing,
          onReplace: () => _replacePersona(cluster),
        ),
      if (_pushable(view).isNotEmpty)
        _PushBar(
          count: _pushable(view).length,
          target: _ws.backend.displayName,
          busy: _pushing,
          onPush: () => _push(view),
        ),
      if (_notice != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: Palette.coral),
              const SizedBox(width: 8),
              Expanded(child: Text(_notice!, style: theme.textTheme.bodySmall)),
            ],
          ),
        ),
      Expanded(
        child: _shown.isEmpty
            ? Center(
                child: Text(
                  'Both agents know the same things.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final kind in _kinds) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                      child: Text(
                        _kindLabels[kind]!.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    for (final cluster in _shown.where(
                      (c) => c.best.kind == kind,
                    ))
                      _ClusterTile(
                        cluster: cluster,
                        connected: view.backends,
                        open: _expanded == cluster.id,
                        onToggle: () => setState(
                          () => _expanded = _expanded == cluster.id
                              ? null
                              : cluster.id,
                        ),
                        canMerge: _mergeCandidates(view, cluster).isNotEmpty,
                        canSplit: _canSplit(cluster),
                        removable: _removable(cluster),
                        onMerge: () => _merge(cluster, view),
                        onSplit: () => _split(cluster),
                        onRemove: () => _remove(cluster),
                      ),
                  ],
                ],
              ),
      ),
    ],
  );
}

/// Nothing remembered — which is a finding, not a failure.
///
/// On a fresh OpenClaw workspace `MEMORY.md` does not exist at all and the
/// persona documents are still their shipped templates. Saying "no memories
/// yet" is the honest reading and is more useful than an empty list, which
/// reads as a screen that failed to load.
class _EmptyMemory extends StatelessWidget {
  const _EmptyMemory({required this.backendName});

  final String backendName;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.psychology_outlined, size: 32, color: context.ink.faint),
          const SizedBox(height: 14),
          Text(
            '$backendName has not written anything down yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.ink.secondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Its memory file is empty and its profile documents are still '
            'the ones it shipped with.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

/// Which agents this view is built from, and how fresh each one is.
///
/// The bridge shows servers that are not connected, from snapshots. A screen
/// that did not say which is which would let a three-week-old memory be read
/// as current — so every source names itself and says when it was read.
class _Sources extends StatelessWidget {
  const _Sources({required this.view});

  final MemoryView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final entry in view.sources.entries)
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(
                entry.value == null
                    ? Icons.cloud_done_outlined
                    : Icons.history_rounded,
                size: 14,
                color: context.ink.tertiary,
              ),
              label: Text(
                entry.value == null
                    ? '${entry.key} · live'
                    : '${entry.key} · ${_ago(entry.value!)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  static String _ago(DateTime at) {
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'just now';
    if (minutes < 60) return '${minutes}m ago';
    final hours = minutes ~/ 60;
    if (hours < 24) return '${hours}h ago';
    return '${hours ~/ 24}d ago';
  }
}

/// Servers that were asked and could not answer.
///
/// Shown rather than swallowed, because "this agent does not have that
/// memory" and "this agent could not be asked" are opposite claims about the
/// same row — and a bridge that silently omits a server is lying about what
/// it compared.
class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.view});

  final MemoryView view;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.cloud_off_rounded, size: 15, color: Palette.coral),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Could not reach ${view.unreachable.keys.join(", ")} — the '
            'comparison below leaves them out. '
            '${view.unreachable.values.first}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

/// How many facts one agent has and another does not.
///
/// The single number the whole bridge exists to produce, and a filter rather
/// than a separate screen — narrowing the same list keeps the answer
/// checkable against the full one.
class _DivergenceBar extends StatelessWidget {
  const _DivergenceBar({
    required this.count,
    required this.only,
    required this.onToggle,
  });

  final int count;
  final bool only;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
    child: Row(
      children: [
        Icon(Icons.call_split_rounded, size: 15, color: context.ink.tertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$count ${count == 1 ? 'thing is' : 'things are'} known to one '
            'agent and not the other',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton(
          onPressed: onToggle,
          child: Text(only ? 'Show all' : 'Show only these'),
        ),
      ],
    ),
  );
}

/// One fact, and which agents have it.
class _ClusterTile extends StatelessWidget {
  const _ClusterTile({
    required this.cluster,
    required this.connected,
    required this.open,
    required this.onToggle,
    required this.canMerge,
    required this.canSplit,
    required this.removable,
    required this.onMerge,
    required this.onSplit,
    required this.onRemove,
  });

  final MemoryCluster cluster;

  /// Every backend the ledger knows about — not every backend that exists, so
  /// a user with one server is never told a memory is "missing" from a server
  /// they have never set up.
  final Set<String> connected;

  final bool open;
  final VoidCallback onToggle;

  /// Whether the person can rule on this cluster: merge it with another,
  /// split it apart, or remove this backend's copy.
  final bool canMerge;
  final bool canSplit;
  final MemoryEntry? removable;
  final VoidCallback onMerge;
  final VoidCallback onSplit;
  final VoidCallback onRemove;

  /// Whether any action menu is worth drawing.
  bool get _hasActions => canMerge || canSplit || removable != null;

  /// A persona document is thousands of characters; a learning node is a
  /// sentence. One collapsed height for both would either truncate the
  /// sentence or show a wall of the document.
  bool get _isLong => cluster.best.text.length > 240;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = cluster.best;
    final missing = cluster.missingFrom(connected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          leading: Icon(
            switch (entry.kind) {
              MemoryKind.persona => Icons.face_outlined,
              MemoryKind.skill => Icons.auto_awesome_outlined,
              MemoryKind.preference => Icons.tune_rounded,
              MemoryKind.project => Icons.folder_outlined,
              MemoryKind.fact => Icons.lightbulb_outline,
            },
            size: 18,
            // A fact only one agent has is the actionable kind, so it is the
            // one that carries colour. Shared facts are the quiet default.
            color: missing.isEmpty ? context.ink.tertiary : Palette.brass,
          ),
          title: Text(entry.label),
          subtitle: Text(
            [
              // Who has it, and — more usefully — who does not.
              if (missing.isEmpty)
                'both: ${cluster.backends.join(", ")}'
              else
                '${cluster.backends.join(", ")} · not in '
                    '${missing.join(", ")}',
              if (!_isLong && entry.title.isNotEmpty) entry.text,
            ].where((s) => s.isNotEmpty).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLong || entry.title.isEmpty || cluster.isShared)
                Icon(
                  open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                ),
              if (_hasActions)
                _MemoryMenu(
                  canMerge: canMerge,
                  canSplit: canSplit,
                  removable: removable,
                  onMerge: onMerge,
                  onSplit: onSplit,
                  onRemove: onRemove,
                ),
            ],
          ),
          onTap: onToggle,
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Every agent's wording, not just the fullest one. Two agents
                // recording the same fact differently is exactly what a
                // person needs to see before deciding they are the same.
                for (final e in cluster.entries) ...[
                  Text(e.origin.backendId, style: theme.textTheme.labelSmall),
                  const SizedBox(height: 2),
                  SelectableText(e.text, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// What this agent could be taught, and the one control that teaches it.
class _PushBar extends StatelessWidget {
  const _PushBar({
    required this.count,
    required this.target,
    required this.busy,
    required this.onPush,
  });

  final int count;
  final String target;
  final bool busy;
  final VoidCallback onPush;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
    child: Row(
      children: [
        Icon(Icons.school_outlined, size: 15, color: Palette.jade),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$target could be taught $count '
            'memor${count == 1 ? 'y' : 'ies'} it does not have',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          TextButton(onPressed: onPush, child: const Text('Teach it')),
      ],
    ),
  );
}

/// A profile document another agent has and this one does not.
///
/// Its own bar rather than a line in the push bar, because the operation is
/// different in kind — a replacement, not an addition — and one sentence
/// covering both would describe the destructive one in additive words.
class _ReplaceBar extends StatelessWidget {
  const _ReplaceBar({
    required this.name,
    required this.from,
    required this.busy,
    required this.onReplace,
  });

  final String name;
  final String from;
  final bool busy;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
    child: Row(
      children: [
        Icon(
          Icons.face_retouching_natural_outlined,
          size: 15,
          color: Palette.brass,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$from has a $name this agent does not',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (!busy)
          TextButton(onPressed: onReplace, child: const Text('Replace…')),
      ],
    ),
  );
}

/// Shared facts that have drifted on this agent — the evidence, not the fix.
///
/// `SHARED_MEMORY.md`: a badge on the memory panel that says *this agent's
/// copy of a shared fact no longer matches the agreed wording*. The
/// side-by-side and the Restore / Keep controls live in the Shared memory
/// panel; here it is one line so the drift is visible where the memory is.
class _DriftedBar extends StatelessWidget {
  const _DriftedBar({
    required this.facts,
    required this.open,
    required this.onToggle,
  });

  final List<SharedFact> facts;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: Radii.smallAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 15,
                    color: Palette.coral,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${facts.length} shared fact'
                      '${facts.length == 1 ? '' : 's'} drifted on this agent',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: context.ink.tertiary,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            for (final fact in facts)
              Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 6),
                child: Text(
                  '${fact.label} — shared wording differs from the local copy. '
                  'Open Shared memory… to resolve.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.ink.secondary,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// The memory row's actions — the same anchored glass menu as everywhere else.
class _MemoryMenu extends StatelessWidget {
  const _MemoryMenu({
    required this.canMerge,
    required this.canSplit,
    required this.removable,
    required this.onMerge,
    required this.onSplit,
    required this.onRemove,
  });

  final bool canMerge;
  final bool canSplit;
  final dynamic removable;
  final VoidCallback onMerge;
  final VoidCallback onSplit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final menu = MenuController();
    return Tooltip(
      message: 'Actions',
      child: MenuAnchor(
        controller: menu,
        style: anchoredMenuStyle,
        alignmentOffset: const Offset(-140, 6),
        menuChildren: [
          MenuCard(
            items: [
              if (canMerge)
                MenuItem(
                  label: 'Merge with another…',
                  onTap: () {
                    menu.close();
                    onMerge();
                  },
                ),
              if (canSplit)
                MenuItem(
                  label: 'Keep separate',
                  onTap: () {
                    menu.close();
                    onSplit();
                  },
                ),
              if (removable != null)
                MenuItem(
                  label: removable!.kind == MemoryKind.skill
                      ? 'Archive'
                      : 'Remove',
                  onTap: () {
                    menu.close();
                    onRemove();
                  },
                ),
            ],
          ),
        ],
        child: Pressable(
          onTap: () => menu.open(),
          child: const Icon(Icons.more_vert_rounded, size: 16),
        ),
      ),
    );
  }
}
