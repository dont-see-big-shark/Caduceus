// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Caduceus';

  @override
  String get settings => 'Settings';

  @override
  String get settingsItemModel => 'Model';

  @override
  String get settingsItemChat => 'Chat';

  @override
  String get settingsItemWorkspace => 'Workspace';

  @override
  String get settingsItemSafety => 'Safety';

  @override
  String get settingsItemMemory => 'Memory & Context';

  @override
  String get settingsItemAdvanced => 'Advanced';

  @override
  String get settingsItemNotifications => 'Notifications';

  @override
  String get settingsItemBilling => 'Billing';

  @override
  String get settingsItemProviders => 'Providers';

  @override
  String get settingsItemShortcuts => 'Keyboard Shortcuts';

  @override
  String get settingsItemToolsKeys => 'Tools & Keys';

  @override
  String get settingsItemPlugins => 'Plugins';

  @override
  String get settingsItemArchived => 'Archived Chats';

  @override
  String get settingsItemAbout => 'About';

  @override
  String get settingsGroupCore => 'Core';

  @override
  String get settingsGroupDevice => 'Device';

  @override
  String get settingsGroupAccount => 'Account & Connection';

  @override
  String get settingsGroupSystem => 'System';

  @override
  String get designSurfaceExample => '示例 · design surface';

  @override
  String get designSurfaceNoData =>
      'This is the design\'s page and the gateway has no surface behind it yet. It is shown as a labelled example rather than invented controls.';

  @override
  String get composerFootCmd => '⌘K commands';

  @override
  String get composerFootHints => '↵ send · ⇧↵ newline · Esc close';

  @override
  String get settingsSubtitle => 'Caduceus and the Hermes server';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Follow System';

  @override
  String get languageEn => 'English';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageZhTW => '繁體中文';

  @override
  String get languageJa => '日本語';

  @override
  String get languageEs => 'Español';

  @override
  String get material => 'Material';

  @override
  String get reduceVisualEffects => 'Reduce visual effects';

  @override
  String get whatItChanges => 'What it changes';

  @override
  String get whatItChangesDesc =>
      'Solid panels instead of glass, and no aurora. Every size, radius, duration and curve stays as it is — the app handles identically and only looks cheaper.';

  @override
  String get solid => 'solid';

  @override
  String get glass => 'glass';

  @override
  String get session => 'Session';

  @override
  String get modelAndSession => 'Model & session';

  @override
  String get approvals => 'Approvals';

  @override
  String get skills => 'Skills';

  @override
  String get voice => 'Voice';

  @override
  String get gateway => 'Gateway';

  @override
  String get device => 'Device';

  @override
  String get about => 'About';

  @override
  String get connection => 'Connection';

  @override
  String get connected => 'Connected';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get pickGroupOnLeft => 'Pick a group on the left';

  @override
  String get model => 'Model';

  @override
  String get thisSession => 'This session';

  @override
  String get changingIt => 'Changing it';

  @override
  String get changingItDesc =>
      'The picker is in the composer, beside the field it will answer. A second one here would be a second list to keep in agreement with the first.';

  @override
  String get workingDirectory => 'Working directory…';

  @override
  String get noSessionOpen => 'no session open';

  @override
  String get dictation => 'Dictation';

  @override
  String get running => 'Running';

  @override
  String get idle => 'Idle';

  @override
  String get whereItRuns => 'Where it runs';

  @override
  String get onThisDevice => 'On this device';

  @override
  String get address => 'Address';

  @override
  String get status => 'Status';

  @override
  String get version => 'Version';

  @override
  String get back => 'Back';

  @override
  String get connectNewBackend => 'Connect a new backend';

  @override
  String get connectNewBackendSubtitle => 'Discover · Pair · Diagnose';

  @override
  String get connectToHermesDesc =>
      'Connect to a Hermes control plane. Tunnel over SSH or Tailscale so it stays bound to loopback — then a session token is all it needs.';

  @override
  String get addAnotherServer => 'Add another server';

  @override
  String get sessionEndedWithError => 'The session ended with an error';

  @override
  String get nameOptional => 'Name (optional)';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get gatewayToken => 'Gateway token';

  @override
  String get sessionToken => 'Session token';

  @override
  String get openClawDeviceNote =>
      'OpenClaw admits a new device only once an operator approves it, so the first connection stops to wait. This app keeps one key per server, so it is approved once and not again.';

  @override
  String get connect => 'Connect';

  @override
  String get forgetThisServer => 'Forget this server';

  @override
  String get waitingToBeApproved => 'Waiting to be approved';

  @override
  String get openClawApprovalNote =>
      'The gateway accepted the token and the handshake. It admits a new device only once an operator approves it, so approve this device and connect again.';

  @override
  String get copyDeviceId => 'Copy device id';

  @override
  String get newSession => 'New session';

  @override
  String get searchSessions => 'Search sessions';

  @override
  String get refresh => 'Refresh';

  @override
  String get scheduledJobs => 'Scheduled jobs';

  @override
  String get projects => 'Projects';

  @override
  String get backgroundProcesses => 'Background processes…';

  @override
  String get agents => 'Agents…';

  @override
  String get checkpoints => 'Checkpoints';

  @override
  String get learningJourney => 'Learning journey';

  @override
  String get server => 'Server';

  @override
  String get noSessions => 'No sessions';

  @override
  String get noSessionsDesc => 'Start a new session to get started';

  @override
  String get reload => 'Reload';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get stop => 'Stop';

  @override
  String get stopAll => 'Stop all';

  @override
  String get delete => 'Delete';

  @override
  String get archive => 'Archive';

  @override
  String get stopThisTitle => 'Stop this?';

  @override
  String get stopAllProcessesTitle => 'Stop all processes?';

  @override
  String get stopAllProcessesMessage =>
      'Every background process on the server is killed, including ones started by other sessions and not listed here.';

  @override
  String get nothingRunning => 'Nothing running';

  @override
  String get hideOutput => 'Hide output';

  @override
  String get showOutput => 'Show output';

  @override
  String get delegation => 'Delegation';

  @override
  String get noSubagentsRunning => 'No subagents running';

  @override
  String get subagentsRunning => 'subagent(s) running';

  @override
  String get allowNewSubagents => 'Allow new subagents';

  @override
  String get spawningPaused => 'Spawning is paused — running children continue';

  @override
  String get agentMaySpawnChildren => 'The agent may spawn children';

  @override
  String get savedSpawnTrees => 'Saved spawn trees';

  @override
  String get noneForThisSession => 'None for this session';

  @override
  String get recentActivity => 'Recent activity';

  @override
  String get interruptThisSubagent => 'Interrupt this subagent';

  @override
  String get restoreCheckpointTitle => 'Restore checkpoint?';

  @override
  String restoreCheckpointMessage(Object hash, Object timestamp) {
    return 'Files on the server are rewritten to their state at $timestamp ($hash). Changes made since are lost.';
  }

  @override
  String get noCheckpoints =>
      'No checkpoints — the agent has not edited files in this session, or checkpointing is off.';

  @override
  String get selectCheckpointToSeeDiff =>
      'Select a checkpoint to see what it changed';

  @override
  String get restoreThisCheckpoint => 'Restore this checkpoint';

  @override
  String restored(Object hash) {
    return 'Restored $hash';
  }

  @override
  String get newScheduledJob => 'New scheduled job';

  @override
  String get jobName => 'Name';

  @override
  String get schedule => 'Schedule';

  @override
  String get scheduleHelper =>
      'cron expression, e.g. 0 9 * * * for 09:00 daily';

  @override
  String get promptToRun => 'Prompt to run';

  @override
  String get create => 'Create';

  @override
  String get noScheduledJobs => 'No scheduled jobs';

  @override
  String get newJob => 'New job';

  @override
  String get thisEntryNoLongerAvailable => 'This entry is no longer available.';

  @override
  String get thisEntryHasNoContentYet => 'This entry has no content yet.';

  @override
  String get archiveSkillTitle => 'Archive skill?';

  @override
  String get deleteMemoryTitle => 'Delete memory?';

  @override
  String archiveSkillContent(Object label) {
    return '\"$label\" is archived on the server and can be restored there.';
  }

  @override
  String deleteMemoryContent(Object label) {
    return '\"$label\" is removed from the agent\'s memory. This cannot be undone.';
  }

  @override
  String get install => 'Install';

  @override
  String get noProjects =>
      'No projects — sessions are not grouped on this server';

  @override
  String get noSessionsInProject => 'No sessions';

  @override
  String get tools => 'Tools';

  @override
  String get commands => 'Commands';

  @override
  String get config => 'Config';

  @override
  String get plugins => 'Plugins';

  @override
  String get thisServerReportsNothing =>
      'This server reports nothing about this session yet.';

  @override
  String get readOnlyConfigNote =>
      'Read-only: turning any of this on or off changes the whole server\'s configuration, not this session\'s.';

  @override
  String get maintenanceNote =>
      'Maintenance — affects every session on this server';

  @override
  String reloadTargetTitle(Object target) {
    return 'Reload $target?';
  }

  @override
  String get reloadTargetMessage =>
      'This changes the server for every session on it, not just this one.';

  @override
  String get continueAction => 'Continue';

  @override
  String get typeAMessage => 'Type a message...';

  @override
  String get send => 'Send';

  @override
  String get stopTurn => 'Stop';

  @override
  String get thinking => 'Thinking...';

  @override
  String thinkingTime(Object seconds) {
    return 'Thought for ${seconds}s';
  }

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get retry => 'Retry';

  @override
  String get edit => 'Edit';

  @override
  String get sessionActions => 'Session actions';

  @override
  String get undoLastExchange => 'Undo last exchange';

  @override
  String get fileCheckpoints => 'File checkpoints…';

  @override
  String get journeyWhatItLearned => 'Journey — what it learned…';

  @override
  String get toolsetsSkillsPlugins => 'Toolsets, skills, plugins…';

  @override
  String get findInConversation => 'Find in conversation…';

  @override
  String get copyTranscript => 'Copy transcript';

  @override
  String get branchSession => 'Branch…';

  @override
  String get usageAndContext => 'Usage and context…';

  @override
  String get typeACommand => 'Type a command…';

  @override
  String nothingMatches(Object query) {
    return 'Nothing matches “$query”';
  }

  @override
  String get actOnRunningTurn => 'Act on the running turn';

  @override
  String get steerThisTurn => 'Steer this turn';

  @override
  String get redirectThisTurn => 'Redirect this turn';

  @override
  String get workingDirectoryTitle => 'Working directory';

  @override
  String get workingDirectoryDesc =>
      'A path on the server running the agent, not on this Mac. Attachments and @-references resolve against it.';

  @override
  String get set => 'Set';

  @override
  String get nothingToUndo => 'Nothing to undo';

  @override
  String removedMessages(Object count) {
    return 'Removed $count message(s)';
  }

  @override
  String copiedCharacters(Object count) {
    return 'Copied $count characters';
  }

  @override
  String get branchFailed => 'Branch failed';

  @override
  String branchedTo(Object id) {
    return 'Branched to $id';
  }

  @override
  String get sessionUsage => 'Session usage';

  @override
  String get sessions => 'Sessions';

  @override
  String get chat => 'Chat';

  @override
  String get panels => 'Panels';

  @override
  String get messaging => 'Messaging';

  @override
  String get artifacts => 'Artifacts';

  @override
  String get kanban => 'Kanban';

  @override
  String get photo => 'Photo';

  @override
  String get library => 'Library';

  @override
  String get file => 'File';

  @override
  String get video => 'Video';

  @override
  String get pasteFromClipboard => 'Paste from the clipboard';

  @override
  String get referencePathOnServer => 'Reference a path on the server';

  @override
  String get queueForAfterThisTurn => 'Queue for after this turn';

  @override
  String get attachSomething => 'Attach something';

  @override
  String get rename => 'Rename…';

  @override
  String get compressHistory => 'Compress history';

  @override
  String get deleteSessionTitle => 'Delete…';

  @override
  String get renameSession => 'Rename session';

  @override
  String get compressHistoryQuestion => 'Compress history?';

  @override
  String compressHistoryDesc(Object label) {
    return 'Older messages in \"$label\" are summarised to reclaim context. This cannot be undone.';
  }

  @override
  String get deleteSessionQuestion => 'Delete session?';

  @override
  String deleteSessionDesc(Object count, Object label) {
    return '\"$label\" and its $count messages are removed permanently.';
  }

  @override
  String get holdToDelete => 'Hold to delete';

  @override
  String get deleted => 'Deleted';

  @override
  String get showSessions => 'Show sessions';

  @override
  String get hideSessions => 'Hide sessions';

  @override
  String get appearanceSystem => 'Appearance: system';

  @override
  String get appearanceLight => 'Appearance: light';

  @override
  String get appearanceDark => 'Appearance: dark';

  @override
  String get modelForThisSession => 'Model for this session';

  @override
  String get requeryProviders => 'Re-query the providers';

  @override
  String get noModelList => 'This server did not offer a model list.';

  @override
  String get noCredential => 'no credential';

  @override
  String get composerSuggestionResume => 'Continue the last task';

  @override
  String get composerSuggestionStatus => 'Check the current session';

  @override
  String get composerSuggestionRelease => 'Write a release note';
}
