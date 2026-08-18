/// The seam: what every agent backend must do.
library;

import 'attachment.dart';
import 'capability.dart';
import 'connection.dart';
import 'errors.dart';
import 'event.dart';
import 'inventory.dart';
import 'memory.dart';
import 'message.dart';
import 'model.dart';
import 'opened.dart';
import 'prompt.dart';
import 'session.dart';
import 'skill.dart';

/// What every agent backend must do.
///
/// Thirty-two members. Seventeen are here because a client that cannot do
/// them is not an agent client: connect, list, open, create, release, read what was
/// opened, read history, send, interrupt, answer, stream, and say what else it
/// can do.
///
/// The other fifteen — [models], [selectModel], [branch], [skills],
/// [serverConfig], [usage], [tasks], [stopTask], [stopAllTasks], [memory],
/// [jobs], [createJob], [reloadTargets], [reloadServer] and [sessionUpdates]
/// — are the exception the rule allows for, and it is worth being explicit about
/// why. Each is gated on a capability and each has a *neutral* shape that both
/// backends can serve. They are on the interface rather than reached through a
/// raw client because the alternative was a surface that only one backend
/// could ever have, which is how the Hermes-only panels ended up where they
/// are — correctly, in their case, because nothing else has checkpoints.
/// Two agents that both switch models, or both list what they can reach
/// for, should not need two code paths to do it.
///
/// The test for admitting one is not "both backends have it" but "both
/// backends have it *and* the neutral shape does not lie about either". That
/// is why reloading is split from reading the config: OpenClaw serves
/// `config.get` at `operator.read` and gates every write behind
/// `operator.admin`, so one capability covering both would have offered
/// buttons that could only be refused.
///
/// Everything beyond that is a [Capability] the backend declares and the UI
/// asks about. The tempting alternative — one interface with forty methods —
/// makes every backend implement seven features it does not have by throwing,
/// and the UI offers buttons that fail. This codebase already has the rule,
/// from the attachment sheet: **a menu item that fails is worse than one that
/// is absent.**
///
/// Every method may throw [AgentException]. Adapters translate their
/// protocol's errors into it; nothing above this line sees a wire code.
abstract interface class AgentBackend {
  /// A stable identifier for this backend kind — `hermes`, `openclaw`. Used
  /// for persisted connection records and for logs, never for behaviour: a
  /// `switch` on this in the UI is the abstraction failing.
  String get id;

  /// What to call it on screen.
  String get displayName;

  /// Connect and authenticate. Whatever that means here — a token in a URL, a
  /// challenge-response handshake with a device key — stays inside.
  ///
  /// Completing does not mean usable: a backend whose device is not yet
  /// approved completes and reports [AgentStatus.awaitingApproval] on
  /// [connection]. Callers must watch that stream rather than treating a
  /// returned future as readiness.
  Future<void> connect();

  /// Returns whether the current connection can answer a protocol request.
  ///
  /// This is the recovery seam for app resume: a socket left quiet while the
  /// process was suspended can still report connected even though its network
  /// path is gone. Implementations should make one small request and return
  /// false rather than throwing when that request cannot complete.
  Future<bool> verifyConnection();

  Future<void> dispose();

  /// The current state, and every change to it. Emits the current value on
  /// subscription so a late listener is not left blank.
  Stream<AgentConnection> get connection;

  /// The most recent value of [connection], for a synchronous read.
  AgentConnection get connectionState;

  /// Ordered by last activity, newest first.
  Future<List<AgentSession>> sessions({int limit});

  /// Opens a session and begins receiving its events.
  ///
  /// Returns a handle because the durable id and the live id are not the same
  /// thing on either backend — Hermes resumes to a gateway handle beside a
  /// stored id, OpenClaw subscribes per session and carries a cursor. Callers
  /// hold the handle and pass it back; they never construct one.
  Future<SessionHandle> open(String sessionId);

  Future<SessionHandle> create({
    String? title,
    String? cwd,
    String? model,
  });

  /// Stops delivery for one session.
  ///
  /// A no-op where the server pushes everything regardless (Hermes); a real
  /// unsubscribe on OpenClaw, which otherwise keeps streaming a conversation
  /// nobody is looking at.
  Future<void> release(SessionHandle handle);

  /// The live state of a session that was just opened.
  ///
  /// A sibling of [history] rather than part of [open]'s return value, for the
  /// same reason [history] is one: the backend already has this the moment it
  /// opens a session, and threading it through the handle would make the
  /// handle a payload instead of a reference.
  ///
  /// The split from [history] is the split [AgentMessage] documents — stored
  /// versus happening. Joining mid-turn is not an edge case; it is what
  /// happens every time the app is reopened while the agent is still working,
  /// and a client that ignores it appends new deltas under nothing.
  Future<OpenedSession> opened(SessionHandle handle);

  /// Prior messages for a resumed session.
  ///
  /// Only meaningful when [supports] says [Capability.history]. Without it a
  /// resumed conversation opens blank, and the UI must *say so* rather than
  /// looking empty — a conversation that appears to have lost its history is
  /// indistinguishable from one that has.
  Future<List<AgentMessage>> history(SessionHandle handle);

  /// Sends a message.
  ///
  /// [clientId] is the idempotency key, and it is required even where the
  /// backend ignores it. Generated by the caller, always: a key invented
  /// inside the adapter is regenerated on the retry it exists to make safe,
  /// which is precisely when it must not change.
  /// [queued] parks the message behind a turn that is already running instead
  /// of failing. Not every backend needs telling — OpenClaw queues anyway —
  /// but on one that does, the alternative is a message that vanishes with no
  /// reply and no error.
  Future<void> send(
    SessionHandle handle,
    String text, {
    required String clientId,
    List<Attachment> attachments,
    bool queued,
  });

  /// Abandons the running turn.
  ///
  /// Also the only way out of a blocked question other than answering it, so a
  /// backend with [Capability.approvals] must implement this for real.
  Future<void> interrupt(SessionHandle handle);

  /// Answers a blocking question.
  Future<void> respond(PromptId id, PromptAnswer answer);

  /// Models this backend can answer [handle] with.
  ///
  /// Takes the session, because on Hermes the catalog is *per session* — the
  /// call is refused outright without one — and because which models are
  /// available can depend on the agent behind the session. A backend with one
  /// global catalog ignores it.
  ///
  /// Only meaningful behind [Capability.modelSwitching]. A backend without it
  /// returns nothing rather than throwing, because an empty list is what a
  /// caller that ignored the capability would have to handle anyway.
  Future<List<AgentModel>> models(SessionHandle handle);

  /// Answers this session with [modelId] from here on.
  ///
  /// Takes [AgentModel.id], not its label: the two differ on both backends,
  /// and sending the label back is how a model switch silently selects
  /// nothing.
  Future<void> selectModel(SessionHandle handle, String modelId);

  /// Forks a session, transcript and all, into a new one.
  ///
  /// Only meaningful behind [Capability.sessionBranching]. Returns a handle to
  /// the new session, already open — the caller wanted somewhere to continue,
  /// and making it ask for the thing it just created is a round trip for
  /// nothing.
  Future<SessionHandle> branch(SessionHandle handle);

  /// What the server can reach for: skills, tools, plugins, commands.
  ///
  /// Only meaningful behind [Capability.skills]. Takes a handle for the same
  /// reason [models] does — the tool half of the answer is *per session* on
  /// both backends (Hermes' `tools.list` and OpenClaw's `tools.effective`
  /// both refuse without one), because which tools are live depends on the
  /// session's profile.
  ///
  /// Returns one flat list; [AgentSkill.group] is what a panel divides on. A
  /// backend that serves only part of the inventory returns that part rather
  /// than failing — an entry missing from a read-only report costs less than
  /// a report that will not open.
  Future<List<AgentSkill>> skills(SessionHandle handle);

  /// The skill library — every skill this agent has, with identity and content.
  ///
  /// Behind [Capability.skills]. Richer than [skills]: that is a flat
  /// inventory row for the server panel; this carries a stable cross-backend
  /// key, a per-backend identity and — best-effort — the SKILL.md itself,
  /// which is what lets two agents' libraries be compared side by side. See
  /// `SKILLS_BRIDGE.md`.
  Future<List<SkillEntry>> skillLibrary();

  /// How the server is configured, as the server itself renders it.
  ///
  /// Only meaningful behind [Capability.serverConfig]. A report, not an
  /// editor: see [ServerConfigSection] for why it is strings.
  Future<List<ServerConfigSection>> serverConfig();

  /// What this session has cost, and how full its context is.
  ///
  /// Only meaningful behind [Capability.usageReporting]. Backends fill the
  /// half they know: see [AgentUsage] for why the two halves are separate and
  /// why zero means "not reported" rather than "none".
  Future<AgentUsage> usage(SessionHandle handle);

  /// What the agent has left running.
  ///
  /// Only meaningful behind [Capability.backgroundProcesses]. Takes a handle
  /// because both backends scope the list to a session, and neither can
  /// answer for a session it does not have open.
  Future<List<AgentTask>> tasks(SessionHandle handle);

  /// Stops one, by [AgentTask.id].
  ///
  /// Only called for a task whose [AgentTask.canStop] is true — a backend
  /// that cannot cancel says so there rather than by throwing here, so the
  /// button is absent rather than present and broken.
  Future<void> stopTask(SessionHandle handle, String id);

  /// Stops *everything* the server is running, for every session on it.
  ///
  /// Behind [Capability.serverMaintenance] rather than
  /// [Capability.backgroundProcesses], and the split is the point: listing
  /// this session's tasks and killing another session's are different powers.
  /// The blast radius is why — a caller must say so before calling it, and a
  /// backend that cannot do it must not appear able to.
  Future<void> stopAllTasks();

  /// Runs the server has scheduled for itself.
  ///
  /// Only meaningful behind [Capability.cron].
  /// What this agent remembers.
  ///
  /// Only meaningful behind [Capability.memoryRead]. One flat list; the
  /// caller groups by [MemoryEntry.kind] and [MemoryEntry.origin]. See
  /// `MEMORY_BRIDGE.md` for why the two backends' very different stores are
  /// projected onto one type, and why writing them back is a separate
  /// capability rather than the other half of this method.
  Future<List<MemoryEntry>> memory();

  /// Which memory operations this backend can actually perform.
  ///
  /// Declared rather than discovered at the last moment, so the UI never
  /// offers "push this new memory to Hermes" — there is no `learning.add`, and
  /// finding that out by watching the push fail is the failure mode the whole
  /// capability system exists to avoid.
  ///
  /// Empty unless [Capability.memoryWrite] is supported.
  Set<MemoryOp> get supportedMemoryOps;

  /// Applies [changes], reporting the fate of each one separately.
  ///
  /// Only meaningful behind [Capability.memoryWrite]. **A batch does not fail
  /// as a batch**: Hermes refuses every [MemoryOp.add] and accepts the updates
  /// in the same push, and the screen has to be able to say exactly that.
  ///
  /// Implementations must honour `MEMORY_BRIDGE.md`'s rules — in particular
  /// R2, that a `remove` never touches something the app did not write, and
  /// R3, that a write is refused rather than applied when the server's copy
  /// moved since it was read.
  Future<MemoryWriteResult> applyMemory(List<MemoryChange> changes);

  /// Runs the server has scheduled for itself.
  ///
  /// Only meaningful behind [Capability.cron].
  Future<List<AgentJob>> jobs();

  /// Schedules a new one.
  ///
  /// Behind [Capability.cronEditing], which is split from [Capability.cron]
  /// for the reason [Capability.serverMaintenance] is split from
  /// [Capability.serverConfig]: on OpenClaw `cron.list` is `operator.read`
  /// while `cron.add` is `operator.admin`, so a client that could see the
  /// schedule would otherwise offer a create button that can only be refused.
  ///
  /// [schedule] is whatever [AgentJob.schedule] looks like on that backend —
  /// the caller shows the user an example the backend gave it, rather than
  /// this interface inventing a syntax neither server speaks.
  Future<void> createJob({
    required String name,
    required String schedule,
    required String prompt,
  });

  /// What this server can be told to reload, in its own words.
  ///
  /// Only meaningful behind [Capability.serverMaintenance]. The strings are
  /// opaque to the UI in exactly the way [AgentModel.id] is: it shows them,
  /// and hands one back to [reloadServer]. Inventing the list in the UI would
  /// mean every backend had to have the same three things to reload, and
  /// neither of the first two does.
  Future<List<String>> reloadTargets(SessionHandle handle);

  /// Reloads [target], which must be one [reloadTargets] returned.
  ///
  /// Affects every session on that machine, not just [handle]'s — the handle
  /// is here because some targets are scoped to a session on the wire, not
  /// because the blast radius is.
  Future<void> reloadServer(SessionHandle handle, String target);

  /// Everything the server says about one open session, already normalised.
  ///
  /// Broadcast: the workspace and a detail panel may both listen. Closes when
  /// the session is released or the backend is disposed.
  Stream<AgentEvent> events(SessionHandle handle);

  /// Sessions changing anywhere, whether this client has them open or not.
  ///
  /// Separate from [events] because it is a different scope, not a different
  /// shape: [events] is a conversation and this is the index. A session
  /// started on a phone, renamed by the server, or finished by a scheduled
  /// job appears in a sidebar only through this — the per-session stream can
  /// say nothing about a session nobody opened.
  ///
  /// Backends without an index subscription never emit, and a sidebar refreshed
  /// on demand is what that looks like. Broadcast, and closed on dispose.
  Stream<AgentSession> get sessionUpdates;

  /// Whether a surface built on [capability] should exist at all.
  bool supports(Capability capability);
}
