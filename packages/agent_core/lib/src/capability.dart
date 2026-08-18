/// What a backend can do beyond the required core.
///
/// The core interface is only what *every* agent must do — connect, list, open,
/// send, stream, stop, answer a blocking question. Everything else is a
/// capability the backend declares and the UI asks about, so a surface a
/// backend cannot serve is never built rather than built and broken. This is
/// the rule the attachment sheet already follows: a menu item that fails is
/// worse than one that is absent.
///
/// A capability may gate only a *whole surface* — a panel, a menu item, a
/// settings group. Never a single control inside a shared screen; that way lies
/// a thicket of `if (supports(...))` and forty capabilities in a year.
enum Capability {
  /// Prior transcript can be fetched for a resumed session. Without it, a
  /// resumed conversation opens blank and the UI must say so.
  history,

  /// Reasoning/thinking streams as its own channel, not folded into the answer.
  reasoningStream,

  /// Tool calls are surfaced as start/progress/complete events.
  toolCalls,

  /// The agent can block on a question (approval, clarify, secret, sudo).
  approvals,

  /// The model can be chosen per session.
  modelSwitching,

  /// Models are organised by *provider*, and a provider can be connected,
  /// disconnected, and given an API key from this client.
  ///
  /// Separate from [modelSwitching] because they are different surfaces, not
  /// degrees of the same one: a backend can offer a flat catalog of models it
  /// already has credentials for without offering anywhere to put a key.
  /// Gating the rich picker on the plain capability meant a backend that can
  /// switch models got a dialog about API keys it has no concept of.
  modelProviders,

  /// A session can be branched from a point in its history.
  sessionBranching,

  /// Checkpoints / rollback of session state.
  checkpoints,

  /// The last exchange can be taken back off the transcript.
  transcriptUndo,

  /// Token spend and context-window occupancy can be reported.
  usageReporting,

  /// The agent delegates to sub-agents, and they can be inspected.
  subagents,

  /// The agent accumulates learning across sessions and it can be browsed.
  learning,

  /// What the agent remembers can be read — see `MEMORY_BRIDGE.md`.
  ///
  /// Split from [memoryWrite] because the two are different scopes on
  /// OpenClaw: `agents.files.get` is `operator.read` and `agents.files.set` is
  /// `operator.admin`. Reading is the whole of phase 1 and needs neither the
  /// admin grant nor any of the write machinery.
  memoryRead,

  /// …and can be changed from this client.
  memoryWrite,

  /// Scheduled / cron jobs can be listed.
  cron,

  /// …and created from this client.
  ///
  /// Split from [cron] for the same reason [serverMaintenance] is split from
  /// [serverConfig]: reading the schedule and changing it are different
  /// permissions. On OpenClaw `cron.list` is `operator.read` while `cron.add`,
  /// `cron.update`, `cron.remove` and `cron.run` are all `operator.admin`.
  cronEditing,

  /// Background processes the agent has spawned.
  backgroundProcesses,

  /// Project / workspace tree.
  projects,

  /// The inventory of what the agent can reach for — skills, tools, plugins,
  /// user commands. Read-only; see [AgentSkill].
  skills,

  /// The server's own configuration can be read back and shown.
  ///
  /// Separate from [skills] because it is a separate panel and a separate
  /// permission: OpenClaw serves `config.get` at `operator.read` but every
  /// write to it needs `operator.admin`, a scope this client never asks for.
  serverConfig,

  /// The server can be told to reload parts of itself from this client.
  ///
  /// Split from [serverConfig] because reading and writing are different
  /// permissions, and on OpenClaw they are literally different scopes:
  /// `config.get` is `operator.read` while every reload-shaped method there is
  /// `operator.admin`. A client that showed the buttons because it could read
  /// the config would offer three failures.
  serverMaintenance,

  /// Attaching a file from the device.
  fileAttach,

  /// Attaching an image from the device.
  imageAttach,

  /// Setting the working directory of a session.
  cwdControl,

  /// Bridged chat channels (OpenClaw: WhatsApp, Telegram, …). Hermes has none.
  channels,
}
