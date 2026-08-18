import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('ja'),
    Locale('zh'),
    Locale('zh', 'TW'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Caduceus'**
  String get appTitle;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsItemModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get settingsItemModel;

  /// No description provided for @settingsItemChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get settingsItemChat;

  /// No description provided for @settingsItemWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get settingsItemWorkspace;

  /// No description provided for @settingsItemSafety.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get settingsItemSafety;

  /// No description provided for @settingsItemMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory & Context'**
  String get settingsItemMemory;

  /// No description provided for @settingsItemAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settingsItemAdvanced;

  /// No description provided for @settingsItemNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsItemNotifications;

  /// No description provided for @settingsItemBilling.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get settingsItemBilling;

  /// No description provided for @settingsItemProviders.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get settingsItemProviders;

  /// No description provided for @settingsItemShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get settingsItemShortcuts;

  /// No description provided for @settingsItemToolsKeys.
  ///
  /// In en, this message translates to:
  /// **'Tools & Keys'**
  String get settingsItemToolsKeys;

  /// No description provided for @settingsItemPlugins.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get settingsItemPlugins;

  /// No description provided for @settingsItemArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived Chats'**
  String get settingsItemArchived;

  /// No description provided for @settingsItemAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsItemAbout;

  /// No description provided for @settingsGroupCore.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get settingsGroupCore;

  /// No description provided for @settingsGroupDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get settingsGroupDevice;

  /// No description provided for @settingsGroupAccount.
  ///
  /// In en, this message translates to:
  /// **'Account & Connection'**
  String get settingsGroupAccount;

  /// No description provided for @settingsGroupSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsGroupSystem;

  /// No description provided for @designSurfaceExample.
  ///
  /// In en, this message translates to:
  /// **'示例 · design surface'**
  String get designSurfaceExample;

  /// No description provided for @designSurfaceNoData.
  ///
  /// In en, this message translates to:
  /// **'This is the design\'s page and the gateway has no surface behind it yet. It is shown as a labelled example rather than invented controls.'**
  String get designSurfaceNoData;

  /// No description provided for @composerFootCmd.
  ///
  /// In en, this message translates to:
  /// **'⌘K commands'**
  String get composerFootCmd;

  /// No description provided for @composerFootHints.
  ///
  /// In en, this message translates to:
  /// **'↵ send · ⇧↵ newline · Esc close'**
  String get composerFootHints;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Caduceus and the Hermes server'**
  String get settingsSubtitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get languageSystem;

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @languageZh.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageZh;

  /// No description provided for @languageZhTW.
  ///
  /// In en, this message translates to:
  /// **'繁體中文'**
  String get languageZhTW;

  /// No description provided for @languageJa.
  ///
  /// In en, this message translates to:
  /// **'日本語'**
  String get languageJa;

  /// No description provided for @languageEs.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get languageEs;

  /// No description provided for @material.
  ///
  /// In en, this message translates to:
  /// **'Material'**
  String get material;

  /// No description provided for @reduceVisualEffects.
  ///
  /// In en, this message translates to:
  /// **'Reduce visual effects'**
  String get reduceVisualEffects;

  /// No description provided for @whatItChanges.
  ///
  /// In en, this message translates to:
  /// **'What it changes'**
  String get whatItChanges;

  /// No description provided for @whatItChangesDesc.
  ///
  /// In en, this message translates to:
  /// **'Solid panels instead of glass, and no aurora. Every size, radius, duration and curve stays as it is — the app handles identically and only looks cheaper.'**
  String get whatItChangesDesc;

  /// No description provided for @solid.
  ///
  /// In en, this message translates to:
  /// **'solid'**
  String get solid;

  /// No description provided for @glass.
  ///
  /// In en, this message translates to:
  /// **'glass'**
  String get glass;

  /// No description provided for @session.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get session;

  /// No description provided for @modelAndSession.
  ///
  /// In en, this message translates to:
  /// **'Model & session'**
  String get modelAndSession;

  /// No description provided for @approvals.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get approvals;

  /// No description provided for @skills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get skills;

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @gateway.
  ///
  /// In en, this message translates to:
  /// **'Gateway'**
  String get gateway;

  /// No description provided for @device.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get device;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @connection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @pickGroupOnLeft.
  ///
  /// In en, this message translates to:
  /// **'Pick a group on the left'**
  String get pickGroupOnLeft;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @thisSession.
  ///
  /// In en, this message translates to:
  /// **'This session'**
  String get thisSession;

  /// No description provided for @changingIt.
  ///
  /// In en, this message translates to:
  /// **'Changing it'**
  String get changingIt;

  /// No description provided for @changingItDesc.
  ///
  /// In en, this message translates to:
  /// **'The picker is in the composer, beside the field it will answer. A second one here would be a second list to keep in agreement with the first.'**
  String get changingItDesc;

  /// No description provided for @workingDirectory.
  ///
  /// In en, this message translates to:
  /// **'Working directory…'**
  String get workingDirectory;

  /// No description provided for @noSessionOpen.
  ///
  /// In en, this message translates to:
  /// **'no session open'**
  String get noSessionOpen;

  /// No description provided for @dictation.
  ///
  /// In en, this message translates to:
  /// **'Dictation'**
  String get dictation;

  /// Run-state label in the phone top bar.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get running;

  /// Idle-state label in the phone top bar.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get idle;

  /// No description provided for @whereItRuns.
  ///
  /// In en, this message translates to:
  /// **'Where it runs'**
  String get whereItRuns;

  /// No description provided for @onThisDevice.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get onThisDevice;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// Back affordance label.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Title of the connect-new-backend view.
  ///
  /// In en, this message translates to:
  /// **'Connect a new backend'**
  String get connectNewBackend;

  /// Subtitle of the connect-new-backend view.
  ///
  /// In en, this message translates to:
  /// **'Discover · Pair · Diagnose'**
  String get connectNewBackendSubtitle;

  /// No description provided for @connectToHermesDesc.
  ///
  /// In en, this message translates to:
  /// **'Connect to a Hermes control plane. Tunnel over SSH or Tailscale so it stays bound to loopback — then a session token is all it needs.'**
  String get connectToHermesDesc;

  /// No description provided for @addAnotherServer.
  ///
  /// In en, this message translates to:
  /// **'Add another server'**
  String get addAnotherServer;

  /// No description provided for @sessionEndedWithError.
  ///
  /// In en, this message translates to:
  /// **'The session ended with an error'**
  String get sessionEndedWithError;

  /// No description provided for @nameOptional.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get nameOptional;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrl;

  /// No description provided for @gatewayToken.
  ///
  /// In en, this message translates to:
  /// **'Gateway token'**
  String get gatewayToken;

  /// No description provided for @sessionToken.
  ///
  /// In en, this message translates to:
  /// **'Session token'**
  String get sessionToken;

  /// No description provided for @openClawDeviceNote.
  ///
  /// In en, this message translates to:
  /// **'OpenClaw admits a new device only once an operator approves it, so the first connection stops to wait. This app keeps one key per server, so it is approved once and not again.'**
  String get openClawDeviceNote;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @forgetThisServer.
  ///
  /// In en, this message translates to:
  /// **'Forget this server'**
  String get forgetThisServer;

  /// No description provided for @waitingToBeApproved.
  ///
  /// In en, this message translates to:
  /// **'Waiting to be approved'**
  String get waitingToBeApproved;

  /// No description provided for @openClawApprovalNote.
  ///
  /// In en, this message translates to:
  /// **'The gateway accepted the token and the handshake. It admits a new device only once an operator approves it, so approve this device and connect again.'**
  String get openClawApprovalNote;

  /// No description provided for @copyDeviceId.
  ///
  /// In en, this message translates to:
  /// **'Copy device id'**
  String get copyDeviceId;

  /// No description provided for @newSession.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get newSession;

  /// No description provided for @searchSessions.
  ///
  /// In en, this message translates to:
  /// **'Search sessions'**
  String get searchSessions;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @scheduledJobs.
  ///
  /// In en, this message translates to:
  /// **'Scheduled jobs'**
  String get scheduledJobs;

  /// No description provided for @projects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projects;

  /// No description provided for @backgroundProcesses.
  ///
  /// In en, this message translates to:
  /// **'Background processes…'**
  String get backgroundProcesses;

  /// No description provided for @agents.
  ///
  /// In en, this message translates to:
  /// **'Agents…'**
  String get agents;

  /// No description provided for @checkpoints.
  ///
  /// In en, this message translates to:
  /// **'Checkpoints'**
  String get checkpoints;

  /// No description provided for @learningJourney.
  ///
  /// In en, this message translates to:
  /// **'Learning journey'**
  String get learningJourney;

  /// No description provided for @server.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @noSessions.
  ///
  /// In en, this message translates to:
  /// **'No sessions'**
  String get noSessions;

  /// No description provided for @noSessionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Start a new session to get started'**
  String get noSessionsDesc;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @stopAll.
  ///
  /// In en, this message translates to:
  /// **'Stop all'**
  String get stopAll;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @stopThisTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop this?'**
  String get stopThisTitle;

  /// No description provided for @stopAllProcessesTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop all processes?'**
  String get stopAllProcessesTitle;

  /// No description provided for @stopAllProcessesMessage.
  ///
  /// In en, this message translates to:
  /// **'Every background process on the server is killed, including ones started by other sessions and not listed here.'**
  String get stopAllProcessesMessage;

  /// No description provided for @nothingRunning.
  ///
  /// In en, this message translates to:
  /// **'Nothing running'**
  String get nothingRunning;

  /// No description provided for @hideOutput.
  ///
  /// In en, this message translates to:
  /// **'Hide output'**
  String get hideOutput;

  /// No description provided for @showOutput.
  ///
  /// In en, this message translates to:
  /// **'Show output'**
  String get showOutput;

  /// No description provided for @delegation.
  ///
  /// In en, this message translates to:
  /// **'Delegation'**
  String get delegation;

  /// No description provided for @noSubagentsRunning.
  ///
  /// In en, this message translates to:
  /// **'No subagents running'**
  String get noSubagentsRunning;

  /// No description provided for @subagentsRunning.
  ///
  /// In en, this message translates to:
  /// **'subagent(s) running'**
  String get subagentsRunning;

  /// No description provided for @allowNewSubagents.
  ///
  /// In en, this message translates to:
  /// **'Allow new subagents'**
  String get allowNewSubagents;

  /// No description provided for @spawningPaused.
  ///
  /// In en, this message translates to:
  /// **'Spawning is paused — running children continue'**
  String get spawningPaused;

  /// No description provided for @agentMaySpawnChildren.
  ///
  /// In en, this message translates to:
  /// **'The agent may spawn children'**
  String get agentMaySpawnChildren;

  /// No description provided for @savedSpawnTrees.
  ///
  /// In en, this message translates to:
  /// **'Saved spawn trees'**
  String get savedSpawnTrees;

  /// No description provided for @noneForThisSession.
  ///
  /// In en, this message translates to:
  /// **'None for this session'**
  String get noneForThisSession;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get recentActivity;

  /// No description provided for @interruptThisSubagent.
  ///
  /// In en, this message translates to:
  /// **'Interrupt this subagent'**
  String get interruptThisSubagent;

  /// No description provided for @restoreCheckpointTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore checkpoint?'**
  String get restoreCheckpointTitle;

  /// No description provided for @restoreCheckpointMessage.
  ///
  /// In en, this message translates to:
  /// **'Files on the server are rewritten to their state at {timestamp} ({hash}). Changes made since are lost.'**
  String restoreCheckpointMessage(Object hash, Object timestamp);

  /// No description provided for @noCheckpoints.
  ///
  /// In en, this message translates to:
  /// **'No checkpoints — the agent has not edited files in this session, or checkpointing is off.'**
  String get noCheckpoints;

  /// No description provided for @selectCheckpointToSeeDiff.
  ///
  /// In en, this message translates to:
  /// **'Select a checkpoint to see what it changed'**
  String get selectCheckpointToSeeDiff;

  /// No description provided for @restoreThisCheckpoint.
  ///
  /// In en, this message translates to:
  /// **'Restore this checkpoint'**
  String get restoreThisCheckpoint;

  /// No description provided for @restored.
  ///
  /// In en, this message translates to:
  /// **'Restored {hash}'**
  String restored(Object hash);

  /// No description provided for @newScheduledJob.
  ///
  /// In en, this message translates to:
  /// **'New scheduled job'**
  String get newScheduledJob;

  /// No description provided for @jobName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get jobName;

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @scheduleHelper.
  ///
  /// In en, this message translates to:
  /// **'cron expression, e.g. 0 9 * * * for 09:00 daily'**
  String get scheduleHelper;

  /// No description provided for @promptToRun.
  ///
  /// In en, this message translates to:
  /// **'Prompt to run'**
  String get promptToRun;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @noScheduledJobs.
  ///
  /// In en, this message translates to:
  /// **'No scheduled jobs'**
  String get noScheduledJobs;

  /// No description provided for @newJob.
  ///
  /// In en, this message translates to:
  /// **'New job'**
  String get newJob;

  /// No description provided for @thisEntryNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'This entry is no longer available.'**
  String get thisEntryNoLongerAvailable;

  /// No description provided for @thisEntryHasNoContentYet.
  ///
  /// In en, this message translates to:
  /// **'This entry has no content yet.'**
  String get thisEntryHasNoContentYet;

  /// No description provided for @archiveSkillTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive skill?'**
  String get archiveSkillTitle;

  /// No description provided for @deleteMemoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete memory?'**
  String get deleteMemoryTitle;

  /// No description provided for @archiveSkillContent.
  ///
  /// In en, this message translates to:
  /// **'\"{label}\" is archived on the server and can be restored there.'**
  String archiveSkillContent(Object label);

  /// No description provided for @deleteMemoryContent.
  ///
  /// In en, this message translates to:
  /// **'\"{label}\" is removed from the agent\'s memory. This cannot be undone.'**
  String deleteMemoryContent(Object label);

  /// No description provided for @install.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// No description provided for @noProjects.
  ///
  /// In en, this message translates to:
  /// **'No projects — sessions are not grouped on this server'**
  String get noProjects;

  /// No description provided for @noSessionsInProject.
  ///
  /// In en, this message translates to:
  /// **'No sessions'**
  String get noSessionsInProject;

  /// No description provided for @tools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get tools;

  /// No description provided for @commands.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get commands;

  /// No description provided for @config.
  ///
  /// In en, this message translates to:
  /// **'Config'**
  String get config;

  /// No description provided for @plugins.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get plugins;

  /// No description provided for @thisServerReportsNothing.
  ///
  /// In en, this message translates to:
  /// **'This server reports nothing about this session yet.'**
  String get thisServerReportsNothing;

  /// No description provided for @readOnlyConfigNote.
  ///
  /// In en, this message translates to:
  /// **'Read-only: turning any of this on or off changes the whole server\'s configuration, not this session\'s.'**
  String get readOnlyConfigNote;

  /// No description provided for @maintenanceNote.
  ///
  /// In en, this message translates to:
  /// **'Maintenance — affects every session on this server'**
  String get maintenanceNote;

  /// No description provided for @reloadTargetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reload {target}?'**
  String reloadTargetTitle(Object target);

  /// No description provided for @reloadTargetMessage.
  ///
  /// In en, this message translates to:
  /// **'This changes the server for every session on it, not just this one.'**
  String get reloadTargetMessage;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @typeAMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get typeAMessage;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @stopTurn.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopTurn;

  /// No description provided for @thinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking...'**
  String get thinking;

  /// No description provided for @thinkingTime.
  ///
  /// In en, this message translates to:
  /// **'Thought for {seconds}s'**
  String thinkingTime(Object seconds);

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @sessionActions.
  ///
  /// In en, this message translates to:
  /// **'Session actions'**
  String get sessionActions;

  /// No description provided for @undoLastExchange.
  ///
  /// In en, this message translates to:
  /// **'Undo last exchange'**
  String get undoLastExchange;

  /// No description provided for @fileCheckpoints.
  ///
  /// In en, this message translates to:
  /// **'File checkpoints…'**
  String get fileCheckpoints;

  /// No description provided for @journeyWhatItLearned.
  ///
  /// In en, this message translates to:
  /// **'Journey — what it learned…'**
  String get journeyWhatItLearned;

  /// No description provided for @toolsetsSkillsPlugins.
  ///
  /// In en, this message translates to:
  /// **'Toolsets, skills, plugins…'**
  String get toolsetsSkillsPlugins;

  /// No description provided for @findInConversation.
  ///
  /// In en, this message translates to:
  /// **'Find in conversation…'**
  String get findInConversation;

  /// No description provided for @copyTranscript.
  ///
  /// In en, this message translates to:
  /// **'Copy transcript'**
  String get copyTranscript;

  /// No description provided for @branchSession.
  ///
  /// In en, this message translates to:
  /// **'Branch…'**
  String get branchSession;

  /// No description provided for @usageAndContext.
  ///
  /// In en, this message translates to:
  /// **'Usage and context…'**
  String get usageAndContext;

  /// No description provided for @typeACommand.
  ///
  /// In en, this message translates to:
  /// **'Type a command…'**
  String get typeACommand;

  /// No description provided for @nothingMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches “{query}”'**
  String nothingMatches(Object query);

  /// No description provided for @actOnRunningTurn.
  ///
  /// In en, this message translates to:
  /// **'Act on the running turn'**
  String get actOnRunningTurn;

  /// No description provided for @steerThisTurn.
  ///
  /// In en, this message translates to:
  /// **'Steer this turn'**
  String get steerThisTurn;

  /// No description provided for @redirectThisTurn.
  ///
  /// In en, this message translates to:
  /// **'Redirect this turn'**
  String get redirectThisTurn;

  /// No description provided for @workingDirectoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Working directory'**
  String get workingDirectoryTitle;

  /// No description provided for @workingDirectoryDesc.
  ///
  /// In en, this message translates to:
  /// **'A path on the server running the agent, not on this Mac. Attachments and @-references resolve against it.'**
  String get workingDirectoryDesc;

  /// No description provided for @set.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get set;

  /// No description provided for @nothingToUndo.
  ///
  /// In en, this message translates to:
  /// **'Nothing to undo'**
  String get nothingToUndo;

  /// No description provided for @removedMessages.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} message(s)'**
  String removedMessages(Object count);

  /// No description provided for @copiedCharacters.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} characters'**
  String copiedCharacters(Object count);

  /// No description provided for @branchFailed.
  ///
  /// In en, this message translates to:
  /// **'Branch failed'**
  String get branchFailed;

  /// No description provided for @branchedTo.
  ///
  /// In en, this message translates to:
  /// **'Branched to {id}'**
  String branchedTo(Object id);

  /// No description provided for @sessionUsage.
  ///
  /// In en, this message translates to:
  /// **'Session usage'**
  String get sessionUsage;

  /// No description provided for @sessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get sessions;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @panels.
  ///
  /// In en, this message translates to:
  /// **'Panels'**
  String get panels;

  /// No description provided for @messaging.
  ///
  /// In en, this message translates to:
  /// **'Messaging'**
  String get messaging;

  /// No description provided for @artifacts.
  ///
  /// In en, this message translates to:
  /// **'Artifacts'**
  String get artifacts;

  /// No description provided for @kanban.
  ///
  /// In en, this message translates to:
  /// **'Kanban'**
  String get kanban;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from the clipboard'**
  String get pasteFromClipboard;

  /// No description provided for @referencePathOnServer.
  ///
  /// In en, this message translates to:
  /// **'Reference a path on the server'**
  String get referencePathOnServer;

  /// No description provided for @queueForAfterThisTurn.
  ///
  /// In en, this message translates to:
  /// **'Queue for after this turn'**
  String get queueForAfterThisTurn;

  /// No description provided for @attachSomething.
  ///
  /// In en, this message translates to:
  /// **'Attach something'**
  String get attachSomething;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get rename;

  /// No description provided for @compressHistory.
  ///
  /// In en, this message translates to:
  /// **'Compress history'**
  String get compressHistory;

  /// No description provided for @deleteSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete…'**
  String get deleteSessionTitle;

  /// No description provided for @renameSession.
  ///
  /// In en, this message translates to:
  /// **'Rename session'**
  String get renameSession;

  /// No description provided for @compressHistoryQuestion.
  ///
  /// In en, this message translates to:
  /// **'Compress history?'**
  String get compressHistoryQuestion;

  /// No description provided for @compressHistoryDesc.
  ///
  /// In en, this message translates to:
  /// **'Older messages in \"{label}\" are summarised to reclaim context. This cannot be undone.'**
  String compressHistoryDesc(Object label);

  /// No description provided for @deleteSessionQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete session?'**
  String get deleteSessionQuestion;

  /// No description provided for @deleteSessionDesc.
  ///
  /// In en, this message translates to:
  /// **'\"{label}\" and its {count} messages are removed permanently.'**
  String deleteSessionDesc(Object count, Object label);

  /// No description provided for @holdToDelete.
  ///
  /// In en, this message translates to:
  /// **'Hold to delete'**
  String get holdToDelete;

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deleted;

  /// No description provided for @showSessions.
  ///
  /// In en, this message translates to:
  /// **'Show sessions'**
  String get showSessions;

  /// No description provided for @hideSessions.
  ///
  /// In en, this message translates to:
  /// **'Hide sessions'**
  String get hideSessions;

  /// No description provided for @appearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'Appearance: system'**
  String get appearanceSystem;

  /// No description provided for @appearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Appearance: light'**
  String get appearanceLight;

  /// No description provided for @appearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Appearance: dark'**
  String get appearanceDark;

  /// No description provided for @modelForThisSession.
  ///
  /// In en, this message translates to:
  /// **'Model for this session'**
  String get modelForThisSession;

  /// No description provided for @requeryProviders.
  ///
  /// In en, this message translates to:
  /// **'Re-query the providers'**
  String get requeryProviders;

  /// No description provided for @noModelList.
  ///
  /// In en, this message translates to:
  /// **'This server did not offer a model list.'**
  String get noModelList;

  /// No description provided for @noCredential.
  ///
  /// In en, this message translates to:
  /// **'no credential'**
  String get noCredential;

  /// No description provided for @composerSuggestionResume.
  ///
  /// In en, this message translates to:
  /// **'Continue the last task'**
  String get composerSuggestionResume;

  /// No description provided for @composerSuggestionStatus.
  ///
  /// In en, this message translates to:
  /// **'Check the current session'**
  String get composerSuggestionStatus;

  /// No description provided for @composerSuggestionRelease.
  ///
  /// In en, this message translates to:
  /// **'Write a release note'**
  String get composerSuggestionRelease;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
