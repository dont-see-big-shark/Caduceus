import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import 'backends/claw_backend.dart';
import 'backends/hermes_backend.dart';
import 'design/components.dart';
import 'design/glass.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'widgets/panel_frame.dart';
import 'workspace.dart';

/// The shared knowledge base — `SHARED_MEMORY.md`.
///
/// Facts the person wants every agent to know, and each agent's verified
/// state against them: synced, missing, drifted, kept-for-this-reading, or
/// unverifiable. One screen to see the collective memory, sync the gaps, and
/// resolve a drift with the shared wording side by side with the local one.
///
/// Phone-first like the Fleet panel: the sheet navigates inside itself
/// (roster → fact detail), and compose/drop are confirmations, never stacked
/// routes.
class SharedMemoryPanel extends StatefulWidget {
  const SharedMemoryPanel({
    required this.workspace,
    this.embedded = false,
    this.peers = MemoryPeers.none,
    super.key,
  });

  final Workspace workspace;

  /// Already-open tabs, so sync can reach them without a handshake.
  final MemoryPeers peers;

  /// Render inside a parent surface (right panel rail) instead of a
  /// dialog/sheet. See [Panel.embedded].
  final bool embedded;

  @override
  State<SharedMemoryPanel> createState() => _SharedMemoryPanelState();
}

class _SharedMemoryPanelState extends State<SharedMemoryPanel> {
  SharedMemoryView? _view;
  String? _error;
  String? _notice;
  bool _loading = true;
  bool _reaching = false;
  bool _busy = false;

  /// The fact being read in detail. Null = roster.
  String? _factId;

  /// Drifted copies the person chose to keep *for this reading*.
  ///
  /// `SHARED_MEMORY.md` §10: Keep local is per-reading, not permanent — the
  /// detector reports again on the next read, so this set is cleared on
  /// reload and nothing is persisted.
  final Set<String> _keptLocal = {};

  Workspace get _ws => widget.workspace;

  static String _keepKey(String factId, String backendId) =>
      '$factId\u0000$backendId';

  /// Keep local is per-reading: fold this drifted copy's warning until the
  /// next read. Nothing is persisted.
  void _keepLocal(String factId, String backendId) =>
      setState(() => _keptLocal.add(_keepKey(factId, backendId)));

  void _openFact(String factId) => setState(() => _factId = factId);

  /// Every backend this panel can write to: the connected one and open tabs.
  List<AgentBackend> get _targets {
    final seen = <String>{_ws.backend.id};
    return [
      _ws.backend,
      for (final backend in widget.peers.backends.values)
        if (seen.add(backend.id)) backend,
    ];
  }

  AgentBackend? _targetFor(String backendId) {
    if (backendId == _ws.backend.id) return _ws.backend;
    for (final entry in widget.peers.backends.entries) {
      if (entry.key == backendId) return entry.value;
    }
    return null;
  }

  bool _canSync(AgentBackend target) =>
      target is HermesBackend ||
      (target is ClawBackend && target.supports(Capability.memoryWrite));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reachOut = false}) async {
    setState(() {
      _error = null;
      _notice = null;
      _loading = true;
      _reaching = reachOut;
      // A fresh read is a fresh detection: kept-for-this-reading is over.
      _keptLocal.clear();
    });
    try {
      final view = await _ws.sharedMemoryView(
        reachOut: reachOut,
        peers: widget.peers,
      );
      if (mounted) {
        setState(() {
          _view = view;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _ws.describeFailure(e);
          _loading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _reaching = false);
    }
  }

  SharedFact? get _fact =>
      _view?.facts.where((f) => f.id == _factId).firstOrNull;

  Future<void> _compose({SharedFact? existing}) async {
    final textController = TextEditingController(text: existing?.text ?? '');
    MemoryKind kind = existing?.kind ?? MemoryKind.fact;
    final saved = await showDialog<({String text, MemoryKind kind})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => Panel(
          title: Text(
            existing == null ? 'Add a shared fact' : 'Edit shared fact',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: textController,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'What every agent should know',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MemoryKind>(
                  initialValue: kind,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kind'),
                  items: const [
                    DropdownMenuItem(
                      value: MemoryKind.fact,
                      child: Text(
                        'Fact — something true about the world or work',
                      ),
                    ),
                    DropdownMenuItem(
                      value: MemoryKind.preference,
                      child: Text(
                        'Preference — how you like to be worked with',
                      ),
                    ),
                    DropdownMenuItem(
                      value: MemoryKind.project,
                      child: Text('Project — something scoped to ongoing work'),
                    ),
                  ],
                  onChanged: (value) => setDialog(() => kind = value ?? kind),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = textController.text.trim();
                if (text.isEmpty) return;
                Navigator.of(context).pop((text: text, kind: kind));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == null || !mounted) return;
    final now = DateTime.now();
    await _ws.ledger.saveSharedFact(
      existing == null
          ? SharedFact(
              id: 'shared-${now.microsecondsSinceEpoch}',
              kind: saved.kind,
              text: saved.text,
              updatedAt: now,
            )
          : existing.copyWith(
              kind: saved.kind,
              text: saved.text,
              updatedAt: now,
            ),
    );
    await _load();
  }

  Future<void> _syncFact(SharedFact fact, String backendId) async {
    final target = _targetFor(backendId);
    if (target == null) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await _ws.syncSharedFact(fact, target);
      if (!mounted) return;
      setState(
        () => _notice = result.ok
            ? null
            : '${target.displayName}: ${result.detail}',
      );
    } catch (e) {
      if (mounted) setState(() => _notice = _ws.describeFailure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _syncAll() async {
    final view = _view;
    if (view == null) return;
    final jobs = <({SharedFact fact, AgentBackend target})>[];
    for (final fact in view.needsAttention) {
      final states = view.statesFor(fact.id);
      if (states == null) continue;
      for (final entry in states.byBackend.entries) {
        if (entry.value.status != AgentFactStatus.missing) continue;
        final target = _targetFor(entry.key);
        if (target != null && _canSync(target)) {
          jobs.add((fact: fact, target: target));
        }
      }
    }
    if (jobs.isEmpty) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text(
          'Sync ${jobs.length} shared fact${jobs.length == 1 ? '' : 's'}?',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hermes is asked through its agent and the write is verified '
                  'by reading it back; OpenClaw is written through the app-owned '
                  'memory block. Refusals are shown after.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final job in jobs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '+ ${job.fact.label} → ${job.target.displayName}',
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
            child: const Text('Sync'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    setState(() {
      _busy = true;
      _notice = null;
    });
    final refusals = <String>[];
    for (final job in jobs) {
      try {
        final result = await _ws.syncSharedFact(job.fact, job.target);
        if (!result.ok) {
          refusals.add('${job.target.displayName}: ${result.detail}');
        }
      } catch (e) {
        refusals.add('${job.target.displayName}: ${_ws.describeFailure(e)}');
      }
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _notice = refusals.isEmpty ? null : refusals.join('\n');
      });
      await _load();
    }
  }

  Future<void> _restore(SharedFact fact, AgentBackend target) async {
    final anchors = await _ws.ledger.anchorsFor(fact.id);
    if (!mounted) return;
    final anchor = anchors[target.id];
    if (anchor == null) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text('Restore the shared wording on ${target.displayName}?'),
        content: Text(
          'The local copy is overwritten with the shared fact.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await _ws.restoreSharedFact(fact, target, anchor);
      if (mounted) {
        setState(
          () => _notice = result.ok
              ? null
              : '${target.displayName}: ${result.detail}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _notice = _ws.describeFailure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _drop(SharedFact fact) async {
    var removeCopies = false;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => Panel(
          title: Text('Remove "${fact.label}" from the shared base?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The fact stops being something every agent should know.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: removeCopies,
                onChanged: (value) =>
                    setDialog(() => removeCopies = value ?? false),
                title: const Text('Also remove the copies this app wrote'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
    if (agreed != true || !mounted) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final notes = await _ws.dropSharedFact(
        fact.id,
        removeCopies: removeCopies,
        targets: _targets,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _factId = null;
        _notice = notes.isEmpty ? null : notes;
      });
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _notice = _ws.describeFailure(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      embedded: widget.embedded,
      title: Row(
        children: [
          if (_fact != null)
            IconButton(
              onPressed: () => setState(() => _factId = null),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
            ),
          const Expanded(child: Text('Shared memory')),
          if (_reaching)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            onPressed: _reaching ? null : () => _load(reachOut: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: 'Ask every agent',
          ),
        ],
      ),
      content: PanelFrame(
        child: switch ((_error, _loading, _view)) {
          (final String message, _, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
          (_, true, _) => const Center(child: CircularProgressIndicator()),
          (_, _, null) => const Center(child: CircularProgressIndicator()),
          (_, _, final SharedMemoryView view) =>
            _fact == null
                ? _Roster(state: this, view: view)
                : _FactDetail(state: this, view: view, fact: _fact!),
        },
      ),
    );
  }
}

/// The first depth: one card per shared fact, and every agent's status.
class _Roster extends StatelessWidget {
  const _Roster({required this.state, required this.view});

  final _SharedMemoryPanelState state;
  final SharedMemoryView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _Sources(view: view),
        if (view.unreachable.isNotEmpty)
          _Unreachable(unreachable: view.unreachable),
        if (state._notice != null) _Notice(notice: state._notice!),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  view.facts.isEmpty
                      ? 'Nothing is shared yet.'
                      : '${view.facts.length} shared fact'
                            '${view.facts.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (view.needsAttention.isNotEmpty)
                TextButton(
                  onPressed: state._busy ? null : state._syncAll,
                  child: Text(
                    state._busy
                        ? 'Syncing…'
                        : 'Sync ${view.needsAttention.length}',
                  ),
                ),
              TextButton(
                onPressed: () => state._compose(),
                child: const Text('New fact'),
              ),
            ],
          ),
        ),
        Expanded(
          child: view.facts.isEmpty
              ? _EmptyShared(state: state)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  children: [
                    for (final fact in view.facts)
                      _FactCard(state: state, fact: fact),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EmptyShared extends StatelessWidget {
  const _EmptyShared({required this.state});

  final _SharedMemoryPanelState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 28,
              color: context.ink.tertiary,
            ),
            const SizedBox(height: 10),
            Text(
              'No shared facts yet. Add the first thing every agent should '
              'know — then sync it to both.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => state._compose(),
              child: const Text('Add a shared fact'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One shared fact, and each agent's status chip.
class _FactCard extends StatelessWidget {
  const _FactCard({required this.state, required this.fact});

  final _SharedMemoryPanelState state;
  final SharedFact fact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final states = state._view?.statesFor(fact.id);
    final needsAttention =
        (states?.anyNeedsAttention ?? false) &&
        !state._keptLocal.contains('${fact.id}\u0000*');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        level: needsAttention ? Glass.regular : Glass.thin,
        radius: Radii.mediumAll,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => state._openFact(fact.id),
            borderRadius: Radii.mediumAll,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        needsAttention
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 16,
                        color: needsAttention ? Palette.coral : Palette.jade,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fact.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  if (fact.text != fact.label)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        fact.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.ink.secondary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (states == null)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            'no agents known',
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      else
                        for (final entry in states.byBackend.entries)
                          _StatusChip(
                            state: state,
                            fact: fact,
                            backendId: entry.key,
                            agentState: entry.value,
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One agent's verdict on a fact, as a chip.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.state,
    required this.fact,
    required this.backendId,
    required this.agentState,
  });

  final _SharedMemoryPanelState state;
  final SharedFact fact;
  final String backendId;
  final AgentFactState agentState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = state._view?.sources.keys.contains(backendId) == true
        ? backendId
        : backendId;
    final kept = state._keptLocal.contains(
      _SharedMemoryPanelState._keepKey(fact.id, backendId),
    );
    final (icon, color, text) = switch (agentState.status) {
      AgentFactStatus.synced => (
        Icons.check_circle_outline_rounded,
        Palette.jade,
        '$label · synced',
      ),
      AgentFactStatus.missing => (
        Icons.add_circle_outline_rounded,
        Palette.brass,
        '$label · missing',
      ),
      AgentFactStatus.drifted when kept => (
        Icons.done_all_rounded,
        context.ink.tertiary,
        '$label · kept (this reading)',
      ),
      AgentFactStatus.drifted => (
        Icons.warning_amber_rounded,
        Palette.coral,
        '$label · drifted',
      ),
      AgentFactStatus.unverifiable => (
        Icons.cloud_off_outlined,
        context.ink.tertiary,
        '$label · unverifiable',
      ),
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 14, color: color),
      label: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}

/// The second depth: one fact, and per-agent resolution controls.
class _FactDetail extends StatelessWidget {
  const _FactDetail({
    required this.state,
    required this.view,
    required this.fact,
  });

  final _SharedMemoryPanelState state;
  final SharedMemoryView view;
  final SharedFact fact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final states = view.statesFor(fact.id);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(fact.label, style: theme.textTheme.titleMedium),
            ),
            TextButton(
              onPressed: () => state._compose(existing: fact),
              child: const Text('Edit'),
            ),
            TextButton(
              onPressed: () => state._drop(fact),
              child: Text('Remove', style: TextStyle(color: Palette.coralText)),
            ),
          ],
        ),
        Text(
          fact.text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.ink.secondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${fact.kind.name} · updated ${_ago(fact.updatedAt)}',
          style: theme.textTheme.labelSmall?.copyWith(color: context.ink.faint),
        ),
        if (state._notice != null) ...[
          const SizedBox(height: 8),
          _Notice(notice: state._notice!),
        ],
        const SizedBox(height: 10),
        if (states == null)
          Text('No agents are known yet.', style: theme.textTheme.bodySmall)
        else
          for (final entry in states.byBackend.entries)
            _AgentRow(
              state: state,
              fact: fact,
              backendId: entry.key,
              agentState: entry.value,
            ),
        if (states != null &&
            states.byBackend.values.any(
              (s) => s.status == AgentFactStatus.missing,
            ))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: state._busy ? null : () => state._syncAll(),
                child: Text(state._busy ? 'Syncing…' : 'Sync missing copies'),
              ),
            ),
          ),
      ],
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

/// One fact × one agent: verdict, the side-by-side when drifted, and the
/// controls that resolve it.
class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.state,
    required this.fact,
    required this.backendId,
    required this.agentState,
  });

  final _SharedMemoryPanelState state;
  final SharedFact fact;
  final String backendId;
  final AgentFactState agentState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = state._targetFor(backendId);
    final kept = state._keptLocal.contains(
      _SharedMemoryPanelState._keepKey(fact.id, backendId),
    );
    final (color, label) = switch (agentState.status) {
      AgentFactStatus.synced => (Palette.jade, 'synced'),
      AgentFactStatus.missing => (Palette.brass, 'missing'),
      AgentFactStatus.drifted when kept => (
        context.ink.tertiary,
        'kept · this reading',
      ),
      AgentFactStatus.drifted => (Palette.coral, 'drifted'),
      AgentFactStatus.unverifiable => (context.ink.tertiary, 'unverifiable'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        level: Glass.thin,
        radius: Radii.mediumAll,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusDot(color: color, size: 7),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    target?.displayName ?? backendId,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
            if (agentState.status == AgentFactStatus.drifted && !kept) ...[
              const SizedBox(height: 8),
              _DiffRow(title: 'shared', text: fact.text, color: Palette.jade),
              const SizedBox(height: 6),
              _DiffRow(
                title: 'local',
                text: agentState.localText ?? '(no local text)',
                color: Palette.coral,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (target != null)
                    FilledButton(
                      onPressed: state._busy
                          ? null
                          : () => state._restore(fact, target),
                      child: Text(state._busy ? 'Working…' : 'Restore shared'),
                    ),
                  TextButton(
                    onPressed: () => state._keepLocal(fact.id, backendId),
                    child: const Text('Keep local'),
                  ),
                ],
              ),
            ] else if (agentState.status == AgentFactStatus.missing)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: target == null
                    ? Text(
                        'Open this agent to sync to it.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.ink.faint,
                        ),
                      )
                    : state._canSync(target)
                    ? FilledButton(
                        onPressed: state._busy
                            ? null
                            : () => state._syncFact(fact, backendId),
                        child: Text(
                          state._busy
                              ? 'Syncing…'
                              : 'Sync to ${target.displayName}',
                        ),
                      )
                    : Text(
                        '${target.displayName} cannot receive new memory right '
                        'now. Open the connection list, turn on Request '
                        'administrator for it, then reconnect.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.ink.faint,
                        ),
                      ),
              )
            else if (agentState.status == AgentFactStatus.unverifiable)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  agentState.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.ink.faint,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.title,
    required this.text,
    required this.color,
  });

  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
        Expanded(
          child: SelectableText(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.ink.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Every backend the memory bridge knows, and whether the read was live.
class _Sources extends StatelessWidget {
  const _Sources({required this.view});

  final SharedMemoryView view;

  @override
  Widget build(BuildContext context) => Padding(
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
                  : '${entry.key} · snapshot',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    ),
  );
}

class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.unreachable});

  final Map<String, String> unreachable;

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
            'Could not reach ${unreachable.keys.join(", ")} — they read as '
            'unverifiable below. ${unreachable.values.first}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.notice});

  final String notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: Palette.coral),
          const SizedBox(width: 8),
          Expanded(child: Text(notice, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
