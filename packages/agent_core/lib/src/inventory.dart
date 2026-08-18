/// What a server can reach for, and how it is configured.
library;

import 'package:meta/meta.dart';

/// Which kind of thing an [AgentSkill] is.
///
/// Both backends have an inventory of "capabilities the agent can use", and
/// both divide it — but they divide it differently and name the divisions in
/// their own vocabulary. Hermes has toolsets, skills and plugins; OpenClaw has
/// skills, tool groups and slash commands. This enum is the intersection, so
/// the panel groups by something it understands rather than by whichever
/// tabs one server happened to define.
enum SkillGroup {
  /// A named ability the agent loads — Hermes' `skills`, OpenClaw's
  /// workspace skills.
  skill,

  /// An individual tool, or a toolset that bundles several.
  tool,

  /// Something installed alongside the agent that adds tools of its own.
  plugin,

  /// A slash command a *user* invokes, rather than something the model picks.
  command,
}

/// One entry in the server's inventory.
///
/// Deliberately flat and read-only. Both backends can *change* this state, and
/// neither change is safe from here: Hermes' `tools.configure` writes the
/// machine's global CLI config, and OpenClaw's `skills.install` needs
/// `operator.admin`, a scope this client does not ask for. Showing the state
/// answers the question people actually have — "is the browser toolset on?" —
/// without taking either risk.
@immutable
class AgentSkill {
  const AgentSkill({
    required this.name,
    required this.group,
    this.description = '',
    this.enabled = true,
    this.detail = '',
  });

  /// What to call it. Never empty — an entry the backend could not name is
  /// dropped by the adapter rather than shown as `?`.
  final String name;

  final SkillGroup group;

  /// One line about what it does, where the backend says.
  final String description;

  /// False when the server knows about it but will not use it. Shown greyed
  /// rather than hidden: "the skill is installed but disabled" and "the skill
  /// is not installed" are different answers to the same question, and a list
  /// that hides the first cannot tell them apart.
  final bool enabled;

  /// A second line in the backend's own words — a version, a tool count, or
  /// *why* it is unavailable. Free text on purpose; the vocabulary here is
  /// each server's, and normalising it would throw away the reason.
  final String detail;

  @override
  String toString() => 'AgentSkill($name, $group, enabled: $enabled)';
}

/// One labelled group of server settings, as the server renders them.
///
/// Values are strings because this is a *report*, not an editor. Both backends
/// answer with something already rendered for display — Hermes' `config.show`
/// returns label/value rows, OpenClaw's `config.get` returns a redacted
/// snapshot — and neither is a schema you could build controls from. Treating
/// it as facts is what keeps this honest.
@immutable
class ServerConfigSection {
  const ServerConfigSection({required this.title, required this.rows});

  final String title;

  /// Label/value pairs, in the order the server gave them.
  final List<(String, String)> rows;

  @override
  String toString() => 'ServerConfigSection($title, ${rows.length} rows)';
}

/// What one session has cost, and how full its context is.
///
/// The two halves are separate because the backends report them separately and
/// one of them reports only one half: Hermes answers `session.usage` *and*
/// `session.context_breakdown` and so knows how much of the window is left;
/// OpenClaw's `sessions.usage` totals tokens and money and has no live
/// context figure at all. Zero means "not reported" in both, and the UI must
/// check rather than draw a meter against a maximum of nothing.
@immutable
class AgentUsage {
  const AgentUsage({
    this.contextUsed = 0,
    this.contextMax = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
    this.costUsd = 0,
    this.details = const [],
  });

  final int contextUsed;
  final int contextMax;

  final int inputTokens;
  final int outputTokens;

  /// What the backend calls the total. Not `input + output`: both backends
  /// count cache reads and writes too, and adding the two visible numbers
  /// would silently disagree with the server's own arithmetic.
  final int totalTokens;

  /// Money, where the backend prices it. Hermes does not, and reports zero.
  final double costUsd;

  /// Everything else the server said, already rendered. Kept rather than
  /// dropped: the figure someone actually came looking for is often one the
  /// domain has no field for, and a report that hides it sends them to a log.
  final List<(String, String)> details;

  /// True when there is a context window to draw a meter against.
  bool get hasContext => contextMax > 0 && contextUsed <= contextMax;

  /// True when there is anything at all worth showing.
  bool get isEmpty =>
      !hasContext && totalTokens == 0 && costUsd == 0 && details.isEmpty;

  @override
  String toString() =>
      'AgentUsage($totalTokens tokens, \$$costUsd, $contextUsed/$contextMax)';
}

/// Something the agent started and left running.
///
/// A forgotten dev server holds a port and can block a session's lifecycle,
/// and nothing in a transcript says it is still there. The two backends mean
/// slightly different things by it — Hermes lists OS processes it spawned,
/// OpenClaw lists ledger tasks including sub-agent runs — and the fields here
/// are the part that is true of both: it has an identity, it is in some state,
/// and it may be stoppable.
@immutable
class AgentTask {
  const AgentTask({
    required this.id,
    required this.title,
    this.status = '',
    this.detail = '',
    this.outputTail = '',
    this.startedAt,
    this.canStop = false,
  });

  /// What [AgentBackend.stopTask] takes. Not the title.
  final String id;

  /// What to show. A command line on Hermes, a task title on OpenClaw.
  final String title;

  /// Running, exited, cancelled — in the backend's own word. Free text
  /// because the vocabularies differ and flattening them would lose the
  /// distinctions each server actually makes.
  final String status;

  /// A second line: a working directory, a progress summary, an error.
  final String detail;

  /// The tail of whatever it has printed, where the backend keeps one.
  final String outputTail;

  final DateTime? startedAt;

  /// False for something already finished, and for a backend that lists tasks
  /// but cannot cancel them. A stop button that cannot stop is worse than no
  /// stop button.
  final bool canStop;

  @override
  String toString() => 'AgentTask($id, "$title", $status)';
}

/// A run the server has scheduled for itself.
///
/// The two backends express a schedule completely differently — Hermes stores
/// a cron expression string, OpenClaw a tagged union of `at` / `every` /
/// `cron` / `on-exit` — so [schedule] is free text the *adapter* renders. The
/// alternative was a schedule model in the domain that both would have to be
/// squeezed into, and the squeezing would lose the parts each server can
/// actually express.
@immutable
class AgentJob {
  const AgentJob({
    required this.id,
    required this.name,
    this.schedule = '',
    this.prompt = '',
    this.enabled = true,
    this.nextRunAt,
    this.lastRunAt,
    this.lastRunStatus = '',
  });

  /// What [AgentBackend.removeJob] takes. Hermes has no separate id and uses
  /// the name; the adapter puts whichever it needs here.
  final String id;

  final String name;

  /// When it runs, already rendered for a human by the adapter.
  final String schedule;

  /// What the agent is asked to do. Empty for a job whose payload is not a
  /// prompt at all — OpenClaw also schedules system events and raw commands.
  final String prompt;

  final bool enabled;

  final DateTime? nextRunAt;
  final DateTime? lastRunAt;

  /// How the last run went, in the backend's own word. Empty where it has
  /// not run or the backend does not say.
  final String lastRunStatus;

  @override
  String toString() => 'AgentJob($id, "$name", $schedule)';
}
