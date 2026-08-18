/// The second level: one screen per settings group.
///
/// Each of these is backed by something the gateway actually answers. That is
/// the whole constraint on this screen — a settings row that reports a number
/// nobody measured, or offers a switch that writes nowhere, is worse than an
/// absent one, because it is believed.
library;

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/glass.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../haptics.dart';
import '../l10n/app_localizations.dart';
import '../main.dart'
    show themeMode, setThemeMode, setReduceEffects, localeNotifier, setLocale;
import '../workspace.dart';
import 'settings_shell.dart';

/// The four groups the design's settings-nav draws: 核心 / 设备 / 账户与连接 /
/// 系统. The master list is grouped by this, exactly as `desktop.html` lays
/// the settings nav out.
enum SettingsSection { core, device, account, system }

/// Which page is open. The master list and the detail pane both need it, and
/// on a phone it is also what the back button pops.
///
/// The seventeen entries are the design's settings-nav, in its order. Pages
/// with a real backend answer render real settings; the rest are the design's
/// prototype pages and are shown as explicitly-labelled 示例 surfaces rather
/// than invented controls.
enum SettingsGroupId {
  model(
    'Model',
    Icons.auto_awesome_rounded,
    Palette.brass,
    SettingsSection.core,
  ),
  chat(
    'Chat',
    Icons.chat_bubble_outline_rounded,
    Palette.azure,
    SettingsSection.core,
  ),
  appearance(
    'Appearance',
    Icons.contrast_rounded,
    Palette.azure,
    SettingsSection.core,
  ),
  workspace(
    'Workspace',
    Icons.folder_outlined,
    Palette.violet,
    SettingsSection.core,
  ),
  safety(
    'Safety',
    Icons.verified_user_outlined,
    Palette.jade,
    SettingsSection.core,
  ),
  memory(
    'Memory & Context',
    Icons.psychology_outlined,
    Palette.violet,
    SettingsSection.core,
  ),
  voice(
    'Voice',
    Icons.graphic_eq_rounded,
    Palette.coral,
    SettingsSection.device,
  ),
  advanced(
    'Advanced',
    Icons.tune_rounded,
    Palette.azure,
    SettingsSection.device,
  ),
  notifications(
    'Notifications',
    Icons.notifications_outlined,
    Palette.brass,
    SettingsSection.device,
  ),
  billing(
    'Billing',
    Icons.receipt_long_outlined,
    Palette.jade,
    SettingsSection.account,
  ),
  providers(
    'Providers',
    Icons.cloud_outlined,
    Palette.azure,
    SettingsSection.account,
  ),
  gateway(
    'Gateway',
    Icons.dns_outlined,
    Palette.azure,
    SettingsSection.account,
  ),
  shortcuts(
    'Keyboard Shortcuts',
    Icons.keyboard_outlined,
    Palette.violet,
    SettingsSection.system,
  ),
  tools(
    'Tools & Keys',
    Icons.handyman_outlined,
    Palette.jade,
    SettingsSection.system,
  ),
  plugins(
    'Plugins',
    Icons.extension_outlined,
    Palette.violet,
    SettingsSection.system,
  ),
  archived(
    'Archived Chats',
    Icons.inventory_2_outlined,
    Palette.coral,
    SettingsSection.system,
  ),
  about(
    'About',
    Icons.info_outline_rounded,
    Palette.brass,
    SettingsSection.system,
  );

  const SettingsGroupId(this.label, this.icon, this.tint, this.section);

  final String label;
  final IconData icon;
  final Color tint;
  final SettingsSection section;
}

/// 模型与会话 — what this session is talking to.
class ModelSettings extends StatelessWidget {
  const ModelSettings({required this.workspace, super.key});

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final console = workspace.activeId == null
        ? null
        : workspace.consoleFor(workspace.activeId!);
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          SettingsPageHeader(
            title: AppLocalizations.of(context)?.settingsItemModel ?? 'Model',
            subtitle: 'Main model, reasoning budget and auxiliary assignment',
          ),
          SettingsGroup(
            title: 'This session',
            children: [
              FactRow(
                label: 'Model',
                value: console?.model.isNotEmpty ?? false
                    ? console!.model
                    : 'no session open',
                machine: true,
              ),
              const FactRow(
                label: 'Changing it',
                value:
                    'The picker is in the composer, beside the field it '
                    'will answer. A second one here would be a second list '
                    'to keep in agreement with the first.',
              ),
              if (console != null)
                FactRow(
                  label: 'Working directory',
                  value: console.cwd.isEmpty ? '/' : console.cwd,
                  machine: true,
                ),
            ],
          ),
          _ServerConfig(workspace: workspace),
        ],
      ),
    );
  }
}

/// What the server reports about itself, rendered as it sends it.
///
/// `config.show` answers with pre-rendered sections — a title and rows of
/// label/value — rather than a schema. That is a display surface, not a
/// settings one, so it is shown as facts and nothing here offers to edit it.
class _ServerConfig extends StatefulWidget {
  const _ServerConfig({required this.workspace});

  final Workspace workspace;

  @override
  State<_ServerConfig> createState() => _ServerConfigState();
}

class _ServerConfigState extends State<_ServerConfig> {
  Future<List<ServerConfigSection>>? _sections;

  @override
  void initState() {
    super.initState();
    _sections = widget.workspace.serverConfig();
  }

  @override
  void didUpdateWidget(_ServerConfig oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      _sections = widget.workspace.serverConfig();
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<ServerConfigSection>>(
        future: _sections,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SettingsGroup(
              title: 'Server',
              children: [
                FactRow(
                  label: 'Could not read the configuration',
                  value: '${snapshot.error}',
                ),
              ],
            );
          }
          final sections = snapshot.data;
          if (sections == null) return const SizedBox.shrink();
          return Column(
            children: [
              for (final section in sections)
                SettingsGroup(
                  title: section.title,
                  children: [
                    for (final (label, value) in section.rows)
                      FactRow(label: label, value: value, machine: true),
                  ],
                ),
            ],
          );
        },
      );
}

/// 审批 — how much the agent may do without asking.
///
/// Read from the server, and written **session-scoped only**. `approvals.mode`
/// is global config: changing it there would change how every session on the
/// server behaves, including ones this client has never opened, and a settings
/// screen on a phone is no place to do that silently. The scope is stated on
/// the screen rather than assumed.
class ApprovalSettings extends StatefulWidget {
  const ApprovalSettings({required this.workspace, super.key});

  final Workspace workspace;

  @override
  State<ApprovalSettings> createState() => _ApprovalSettingsState();
}

class _ApprovalSettingsState extends State<ApprovalSettings> {
  String? _mode;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mode = await widget.workspace.approvalMode();
      if (mounted) setState(() => _mode = mode);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _choose(String mode) async {
    final id = widget.workspace.activeId;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    final ok = await widget.workspace.setApprovalMode(id, mode);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _mode = mode;
    });
    if (ok) Haptics.tap();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.workspace.activeId != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      children: [
        SettingsPageHeader(
          title: AppLocalizations.of(context)?.settingsItemSafety ?? 'Safety',
          subtitle: 'Approvals, keys and unattended operation',
        ),
        SettingsGroup(
          title: 'Policy',
          children: [
            for (final mode in ApprovalMode.values)
              ChoiceRow(
                label: mode.label,
                description: mode.description,
                icon: mode.icon,
                tint: mode.tint,
                selected: _mode == mode.key,
                onTap: live && !_busy ? () => _choose(mode.key) : null,
              ),
          ],
        ),
        SettingsGroup(
          title: 'Scope',
          children: [
            FactRow(
              label: live
                  ? 'Applies to this session only'
                  : 'Open a session to change this',
              value:
                  _error ??
                  'The server default stays as it is. Changing it globally '
                      'would change every session on the server, including '
                      'ones this client has never opened.',
            ),
          ],
        ),
      ],
    );
  }
}

/// The approval policies Hermes documents, and only those.
///
/// `smart` is what the server reports by default and `yolo` is a command in
/// the gateway's own catalogue — *"Toggle YOLO mode (skip all dangerous
/// command approvals)"*. Nothing else is offered: `config.set` echoes back
/// whatever string it is handed without validating it, so an invented mode
/// would be accepted here and then quietly mean nothing to the agent.
enum ApprovalMode {
  smart(
    'smart',
    'Smart',
    'Ask before anything destructive. The default.',
    Icons.verified_user_outlined,
    Palette.jade,
  ),
  yolo(
    'yolo',
    'Trust this session',
    'Skip approval for dangerous commands. Nothing will ask again.',
    Icons.bolt_rounded,
    Palette.coral,
  );

  const ApprovalMode(
    this.key,
    this.label,
    this.description,
    this.icon,
    this.tint,
  );

  final String key;
  final String label;
  final String description;
  final IconData icon;
  final Color tint;
}

/// 技能 — what the agent can reach for.
class SkillSettings extends StatefulWidget {
  const SkillSettings({required this.workspace, super.key});

  final Workspace workspace;

  @override
  State<SkillSettings> createState() => _SkillSettingsState();
}

class _SkillSettingsState extends State<SkillSettings> {
  // The active session, because half the inventory is per session: which
  // tools are live depends on the session's profile on both backends, and
  // asking without one gets the request refused rather than answered.
  late final String? _session = widget.workspace.activeId;
  late final Future<List<AgentSkill>> _skills = switch (_session) {
    final String id => widget.workspace.skills(id),
    null => Future.value(const []),
  };
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AgentSkill>>(
    future: _skills,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not list skills: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.ink.tertiary),
            ),
          ),
        );
      }
      // "No session open" and "this server has no skills" are different
      // answers, and an empty list tells them apart for nobody.
      if (_session == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Open a session first — which tools are live depends on it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.ink.tertiary),
            ),
          ),
        );
      }
      final all = snapshot.data;
      if (all == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: _filter,
        builder: (context, value, _) {
          final query = value.text.trim().toLowerCase();
          final shown = query.isEmpty
              ? all
              : all.where((s) => s.name.toLowerCase().contains(query)).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                child: GlassPanel(
                  level: Glass.thin,
                  radius: Radii.pillAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 16,
                          color: context.ink.faint,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _filter,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: '${all.length} skills',
                              hintStyle: TextStyle(color: context.ink.faint),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(
                          'No skills match "${value.text.trim()}"',
                          style: TextStyle(color: context.ink.tertiary),
                        ),
                      )
                    : StaggerScope(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                          itemCount: shown.length,
                          itemBuilder: (context, i) => Staggered(
                            index: i,
                            child: _SkillRow(skill: shown[i]),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      );
    },
  );
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.skill});

  final AgentSkill skill;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: GlassPanel(
      level: Glass.thin,
      radius: Radii.mediumAll,
      // No switch: `tools.configure` writes the *global* CLI config, so a
      // stray tap here would change what every session on the server can
      // reach. Listing is the honest half of this screen.
      child: SettingsRow(
        icon: switch (skill.group) {
          SkillGroup.skill => Icons.auto_awesome_outlined,
          SkillGroup.tool => Icons.build_outlined,
          SkillGroup.plugin => Icons.extension_outlined,
          SkillGroup.command => Icons.terminal_rounded,
        },
        tint: skill.enabled ? Palette.jade : Palette.coral,
        label: skill.name,
        // The backend's own words for why, when there are any. A greyed row
        // with no reason is a mystery; "missing bin: gh" is an answer.
        value: skill.detail.isNotEmpty
            ? skill.detail
            : (skill.enabled ? 'enabled' : 'off'),
      ),
    ),
  );
}

/// 外观 — the two choices that are this client's alone, now with Language selection.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      children: [
        SettingsPageHeader(
          title: l10n?.appearance ?? 'Appearance',
          subtitle: 'Dark material, motion and type hierarchy',
        ),
        SettingsGroup(
          title: l10n?.language ?? 'Language',
          children: [
            ValueListenableBuilder<Locale?>(
              valueListenable: localeNotifier,
              builder: (context, currentLocale, _) {
                final String currentTag = currentLocale == null
                    ? 'system'
                    : (currentLocale.countryCode == 'TW' ||
                              currentLocale.scriptCode == 'Hant'
                          ? 'zh_TW'
                          : currentLocale.languageCode);

                final options = [
                  (
                    key: 'system',
                    label: l10n?.languageSystem ?? 'Follow System',
                    desc: l10n?.languageSystem ?? 'System',
                  ),
                  (key: 'en', label: 'English', desc: 'English'),
                  (key: 'zh', label: '简体中文', desc: 'Simplified Chinese'),
                  (key: 'zh_TW', label: '繁體中文', desc: 'Traditional Chinese'),
                  (key: 'ja', label: '日本語', desc: 'Japanese'),
                  (key: 'es', label: 'Español', desc: 'Spanish'),
                ];

                return Column(
                  children: [
                    for (final opt in options)
                      ChoiceRow(
                        label: opt.label,
                        description: opt.desc,
                        icon: Icons.language_rounded,
                        tint: Palette.azure,
                        selected: currentTag == opt.key,
                        onTap: () {
                          Haptics.select();
                          final selectedLocale = switch (opt.key) {
                            'en' => const Locale('en'),
                            'zh' => const Locale('zh'),
                            'zh_TW' => const Locale.fromSubtags(
                              languageCode: 'zh',
                              scriptCode: 'Hant',
                              countryCode: 'TW',
                            ),
                            'ja' => const Locale('ja'),
                            'es' => const Locale('es'),
                            _ => null,
                          };
                          setLocale(selectedLocale);
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        SettingsGroup(
          title: l10n?.theme ?? 'Theme',
          children: [
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeMode,
              builder: (context, mode, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: Segmented(
                  labels: [
                    l10n?.themeSystem ?? 'System',
                    l10n?.themeLight ?? 'Light',
                    l10n?.themeDark ?? 'Dark',
                  ],
                  index: ThemeMode.values.indexOf(mode),
                  onChanged: (i) {
                    Haptics.select();
                    setThemeMode(ThemeMode.values[i]);
                  },
                ),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: l10n?.material ?? 'Material',
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: Materials.degraded,
              builder: (context, reduced, _) => SettingsRow(
                icon: Icons.blur_on_rounded,
                tint: Palette.violet,
                label: l10n?.reduceVisualEffects ?? 'Reduce visual effects',
                value: reduced
                    ? (l10n?.solid ?? 'solid')
                    : (l10n?.glass ?? 'glass'),
                trailing: GlassSwitch(
                  value: reduced,
                  onChanged: setReduceEffects,
                  semanticLabel:
                      l10n?.reduceVisualEffects ?? 'Reduce visual effects',
                ),
              ),
            ),
            FactRow(
              label: l10n?.whatItChanges ?? 'What it changes',
              value:
                  l10n?.whatItChangesDesc ??
                  'Solid panels instead of glass, and no aurora. Every size, '
                      'radius, duration and curve stays as it is — the app handles '
                      'identically and only looks cheaper.',
            ),
          ],
        ),
      ],
    );
  }
}
