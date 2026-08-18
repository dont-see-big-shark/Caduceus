import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'design/components.dart';
import 'design/glass.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'widgets/master_nav.dart';
import 'l10n/app_localizations.dart';
import 'settings/settings_pages.dart';
import 'settings/settings_shell.dart';
import 'workspace.dart';

extension SettingsGroupIdL10n on SettingsGroupId {
  String localizedLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return label;
    return switch (this) {
      SettingsGroupId.model => l10n.settingsItemModel,
      SettingsGroupId.chat => l10n.settingsItemChat,
      SettingsGroupId.appearance => l10n.appearance,
      SettingsGroupId.workspace => l10n.settingsItemWorkspace,
      SettingsGroupId.safety => l10n.settingsItemSafety,
      SettingsGroupId.memory => l10n.settingsItemMemory,
      SettingsGroupId.voice => l10n.voice,
      SettingsGroupId.advanced => l10n.settingsItemAdvanced,
      SettingsGroupId.notifications => l10n.settingsItemNotifications,
      SettingsGroupId.billing => l10n.settingsItemBilling,
      SettingsGroupId.providers => l10n.settingsItemProviders,
      SettingsGroupId.gateway => l10n.gateway,
      SettingsGroupId.shortcuts => l10n.settingsItemShortcuts,
      SettingsGroupId.tools => l10n.settingsItemToolsKeys,
      SettingsGroupId.plugins => l10n.settingsItemPlugins,
      SettingsGroupId.archived => l10n.settingsItemArchived,
      SettingsGroupId.about => l10n.settingsItemAbout,
    };
  }
}

/// The four group headers — 核心 / 设备 / 账户与连接 / 系统.
extension SettingsSectionL10n on SettingsSection {
  String localizedLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return name;
    return switch (this) {
      SettingsSection.core => l10n.settingsGroupCore,
      SettingsSection.device => l10n.settingsGroupDevice,
      SettingsSection.account => l10n.settingsGroupAccount,
      SettingsSection.system => l10n.settingsGroupSystem,
    };
  }
}

/// Settings, as the design draws them: groups you drill into, not one list.
///
/// The shape follows the window. On a Mac the groups sit on the left and the
/// open one fills the right — 设置 › 审批, both halves visible, which is what a
/// wide window is for. On a phone the same groups are a list that *pushes*,
/// because a 393-point master-detail is two columns of nothing.
///
/// Every value shown here is read from somewhere real. A settings row that
/// reports a number nobody measured, or offers a switch that writes nowhere,
/// is worse than an absent one — because it is believed.
class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.workspace, this.initialGroup, super.key});

  final Workspace workspace;

  /// Opens straight into one group. The command palette uses it.
  final SettingsGroupId? initialGroup;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// Which group is open. Null on a phone means the master list is showing;
  /// on a Mac it means nothing has been picked yet.
  late SettingsGroupId? _open = widget.initialGroup;

  /// Below this the two columns stop being two columns.
  static const _wide = 720.0;

  Widget _detail(SettingsGroupId group) => switch (group) {
    SettingsGroupId.model => ModelSettings(workspace: widget.workspace),
    SettingsGroupId.appearance => const AppearanceSettings(),
    // The design's Safety page is the approvals surface: 审批、密钥与无人值守.
    SettingsGroupId.safety => ApprovalSettings(workspace: widget.workspace),
    SettingsGroupId.voice => const VoiceSettings(),
    SettingsGroupId.gateway => GatewaySettings(workspace: widget.workspace),
    // The design's Tools & Keys page hosts the skills configuration — the
    // closest real surface the gateways expose.
    SettingsGroupId.tools => SkillSettings(workspace: widget.workspace),
    SettingsGroupId.shortcuts => const ShortcutSettings(),
    SettingsGroupId.about => const AboutSettings(),
    // The rest are the design's prototype pages with no gateway surface
    // behind them; they are labelled 示例 rather than invented.
    SettingsGroupId.chat => const _DesignPlaceholder(
      title: 'Chat',
      subtitle: 'Reply, streaming and input behaviour',
    ),
    SettingsGroupId.workspace => const _DesignPlaceholder(
      title: 'Workspace',
      subtitle: 'Backend profiles and the default working directory',
    ),
    SettingsGroupId.memory => const _DesignPlaceholder(
      title: 'Memory & Context',
      subtitle: 'Persistent memory, user profile and budget',
    ),
    SettingsGroupId.advanced => const _DesignPlaceholder(
      title: 'Advanced',
      subtitle: 'Rendering, telemetry and diagnostics',
    ),
    SettingsGroupId.notifications => const _DesignPlaceholder(
      title: 'Notifications',
      subtitle: 'Channels and reminder rules',
    ),
    SettingsGroupId.billing => const _DesignPlaceholder(
      title: 'Billing',
      subtitle: 'Plans and usage',
    ),
    SettingsGroupId.providers => const _DesignPlaceholder(
      title: 'Providers',
      subtitle: 'Model service connections',
    ),
    SettingsGroupId.plugins => const _DesignPlaceholder(
      title: 'Plugins',
      subtitle: 'Client extensions',
    ),
    SettingsGroupId.archived => const _DesignPlaceholder(
      title: 'Archived Chats',
      subtitle: 'Archived conversations',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wide;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(child: wide ? _wideLayout() : _phoneLayout()),
    );
  }

  Widget _wideLayout() {
    final l10n = AppLocalizations.of(context);
    // The design opens on the Model page, not on an empty "pick one" state.
    final open = _open ?? SettingsGroupId.model;
    return Column(
      children: [
        // The design's `.hd`: a serif title, a one-line subtitle, and a
        // close × at the far end.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 12, 12),
          child: Row(
            children: [
              Text(
                l10n?.settings ?? 'Settings',
                style: serifDisplay(context, size: 16),
              ),
              const SizedBox(width: 12),
              // The subtitle takes the slack so the status pill and the
              // close × sit against the card's right edge. A `Flexible` next
              // to a `Spacer` split the spare width between them and the
              // short subtitle used none of its share, leaving a gap of
              // ~200 pt between the pill and the edge on a wide window.
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n?.settingsSubtitle ?? 'Caduceus and the Hermes server',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.ink.tertiary),
                  ),
                ),
              ),
              _ConnectionPill(workspace: widget.workspace),
              const SizedBox(width: 4),
              HeaderCloseButton(),
            ],
          ),
        ),
        Divider(height: 1, color: context.ink.hairline),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The design's `.settings-shell` grid: 214 pt of nav, the page
              // beside it.
              SizedBox(
                width: 214,
                child: _MasterList(
                  open: open,
                  onOpen: (g) => setState(() => _open = g),
                ),
              ),
              VerticalDivider(width: 1, color: context.ink.hairline),
              Expanded(
                // Keyed so switching groups replays the entrance rather than
                // swapping content inside a settled surface.
                child: KeyedSubtree(key: ValueKey(open), child: _detail(open)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _phoneLayout() {
    final l10n = AppLocalizations.of(context);
    final isDirectDetail = widget.initialGroup != null;
    if (_open case final open?) {
      void goBack() {
        if (isDirectDetail) {
          Navigator.of(context).pop();
        } else {
          setState(() => _open = null);
        }
      }

      return PopScope(
        canPop: isDirectDetail,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          goBack();
        },
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              SettingsBar(title: open.localizedLabel(context), onBack: goBack),
              Expanded(child: _detail(open)),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          SettingsBar(
            title: l10n?.settings ?? 'Settings',
            onBack: () => Navigator.of(context).pop(),
            trailing: _ConnectionPill(workspace: widget.workspace),
          ),
          Expanded(
            child: _MasterList(
              open: _open,
              onOpen: (g) => setState(() => _open = g),
            ),
          ),
        ],
      ),
    );
  }
}

/// The list of groups, each showing what it currently holds.
///
/// The value on the row is the point: Approvals · smart answers the question
/// without opening anything, and a settings screen you rarely have to open is
/// a better one.
class _MasterList extends StatelessWidget {
  const _MasterList({required this.open, required this.onOpen});

  final SettingsGroupId? open;
  final ValueChanged<SettingsGroupId> onOpen;

  /// The design's settings-nav, in its order — 核心 / 设备 / 账户与连接 / 系统.
  static const _items = <SettingsSection, List<SettingsGroupId>>{
    SettingsSection.core: [
      SettingsGroupId.model,
      SettingsGroupId.chat,
      SettingsGroupId.appearance,
      SettingsGroupId.workspace,
      SettingsGroupId.safety,
      SettingsGroupId.memory,
    ],
    SettingsSection.device: [
      SettingsGroupId.voice,
      SettingsGroupId.advanced,
      SettingsGroupId.notifications,
    ],
    SettingsSection.account: [
      SettingsGroupId.billing,
      SettingsGroupId.providers,
      SettingsGroupId.gateway,
    ],
    SettingsSection.system: [
      SettingsGroupId.shortcuts,
      SettingsGroupId.tools,
      SettingsGroupId.plugins,
      SettingsGroupId.archived,
      SettingsGroupId.about,
    ],
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
      children: [
        for (final group in SettingsSection.values) ...[
          // The design's `.settings-nav-group`: mono, uppercase, faint.
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
            child: Text(
              group.localizedLabel(context).toUpperCase(),
              style: mono(context, size: 10, opacity: InkLevel.faint),
            ),
          ),
          for (final id in _items[group]!)
            MasterNavRow(
              item: MasterNavItem(
                icon: id.icon,
                label: id.localizedLabel(context),
                selected: open == id,
                onTap: () => onOpen(id),
              ),
            ),
        ],
      ],
    );
  }
}

/// One entry of the design's `.settings-nav-item` — a compact 32 pt row with
/// a small glyph and a label, not a settings row with a value on it. The
/// values live on the pages; the nav is for navigating.

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) {
        final live = workspace.connection.isConnected;
        return StatusPill(
          label: live
              ? (l10n?.connected ?? 'Connected')
              : workspace.connection.status.name,
          color: live ? Palette.jade : Palette.coral,
        );
      },
    );
  }
}

/// 语音与对讲 — this client's own, because the recogniser is on the device.
class VoiceSettings extends StatelessWidget {
  const VoiceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      children: [
        SettingsPageHeader(
          title: l10n?.voice ?? 'Voice',
          subtitle: 'Voice input and output',
        ),
        SettingsGroup(
          title: l10n?.dictation ?? 'Dictation',
          children: const [
            FactRow(
              label: 'The microphone types',
              value:
                  'There is no audio channel to the agent, so what you say '
                  'lands in the message field where it can be read and '
                  'corrected before it is sent. Nothing is uploaded as audio.',
            ),
            FactRow(
              label: 'Tap to start, tap to stop',
              value:
                  'Push-to-talk would mean holding the phone still with one '
                  'thumb pinned to a 32-point circle for a whole sentence. The '
                  'recogniser closes itself at the end of one anyway.',
            ),
          ],
        ),
        SettingsGroup(
          title: l10n?.whereItRuns ?? 'Where it runs',
          children: [
            FactRow(
              label: l10n?.onThisDevice ?? 'On this device',
              value:
                  'Speech is transcribed by the operating system. Permission '
                  'is asked the first time you use it, not at launch.',
            ),
          ],
        ),
      ],
    );
  }
}

/// 网关 — the server this client is pointed at.
class GatewaySettings extends StatelessWidget {
  const GatewaySettings({required this.workspace, super.key});

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) {
        final live = workspace.connection.isConnected;
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: [
            SettingsPageHeader(
              title: l10n?.gateway ?? 'Gateway',
              subtitle: 'Hermes server interfaces',
            ),
            SettingsGroup(
              title: l10n?.connection ?? 'Connection',
              children: [
                FactRow(
                  // Never the credential: this is a screen people photograph.
                  // See HermesEndpoint.toString.
                  label: l10n?.address ?? 'Address',
                  value: workspace.gateway.endpoint.toString(),
                  machine: true,
                ),
                FactRow(
                  label: l10n?.status ?? 'Status',
                  value: live
                      ? (l10n?.connected ?? 'Connected')
                      : workspace.connection.status.name,
                  trailing: StatusDot(
                    color: live ? Palette.jade : Palette.coral,
                    pulsing: !live,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 系统 › About — the design's About page: version and runtime, read from
/// the platform rather than guessed.
class AboutSettings extends StatelessWidget {
  const AboutSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      children: [
        SettingsPageHeader(
          title: l10n?.settingsItemAbout ?? 'About',
          subtitle: 'Caduceus version and runtime',
        ),
        SettingsGroup(
          title: l10n?.about ?? 'About',
          children: [
            const FactRow(
              label: 'Caduceus',
              value: 'A native client for Hermes Agent',
            ),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final info = snapshot.data;
                return FactRow(
                  label: l10n?.version ?? 'Version',
                  // Blank rather than a spinner or a guess: the row settles a
                  // frame later, and a version that flickers through a
                  // placeholder is worse than one that arrives quietly.
                  value: info == null
                      ? ''
                      : '${info.version} · build ${info.buildNumber}',
                  machine: true,
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// 系统 › Keyboard Shortcuts — the shortcuts this client actually binds.
class ShortcutSettings extends StatelessWidget {
  const ShortcutSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      children: [
        SettingsPageHeader(
          title: l10n?.settingsItemShortcuts ?? 'Keyboard Shortcuts',
          subtitle: 'Desktop shortcuts',
        ),
        SettingsGroup(
          title: l10n?.sessionActions ?? 'Session actions',
          children: const [
            FactRow(label: 'Command palette', value: '⌘K', machine: true),
            FactRow(label: 'New session', value: '⌘N', machine: true),
            FactRow(label: 'Search sessions', value: '⌘F', machine: true),
            FactRow(label: 'Refresh sessions', value: '⌘R', machine: true),
            FactRow(label: 'Undo last exchange', value: '⌘Z', machine: true),
            FactRow(label: 'Background processes', value: '⌘B', machine: true),
            FactRow(label: 'File checkpoints', value: '⌘⇧C', machine: true),
          ],
        ),
        SettingsGroup(
          title: l10n?.scheduledJobs ?? 'Scheduled jobs',
          children: const [
            FactRow(label: 'Scheduled jobs', value: '⌘J', machine: true),
            FactRow(label: 'Projects', value: '⌘P', machine: true),
          ],
        ),
        SettingsGroup(
          title: l10n?.close ?? 'Dismiss',
          children: const [
            FactRow(
              label: 'Close overlay / drawer',
              value: 'Esc',
              machine: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// The design's settings pages that have no gateway surface behind them yet.
///
/// Shown as the design draws them — a title and a subtitle — plus an explicit
/// 示例 marker, exactly like the connect screen's QR / 6-digit / mDNS mocks
/// and the Messaging / Artifacts / Kanban example views. No invented
/// switches: a control that writes nowhere is worse than one that is absent.
class _DesignPlaceholder extends StatelessWidget {
  const _DesignPlaceholder({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      children: [
        SettingsPageHeader(title: title, subtitle: subtitle),
        SettingsGroup(
          title: l10n?.designSurfaceExample ?? '示例 · design surface',
          children: [
            FactRow(
              label: l10n?.designSurfaceNoData ?? 'No data source yet',
              value: '',
            ),
          ],
        ),
      ],
    );
  }
}

/// Opens the settings overlay — the design's `settings-overlay`.
///
/// On a mobile device, this pushes a full-screen settings page with top bar.
/// On desktop, it opens a floating glass dialog over the workbench.
Future<void> showSettingsOverlay(
  BuildContext context,
  Workspace workspace, {
  SettingsGroupId? initialGroup,
}) {
  final isPhone = MediaQuery.sizeOf(context).width < 720;
  if (isPhone) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SettingsPage(workspace: workspace, initialGroup: initialGroup),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: GlassPanel(
          level: Glass.thick,
          radius: BorderRadius.circular(20),
          child: SizedBox(
            width: 960,
            height: 620,
            child: SettingsPage(
              workspace: workspace,
              initialGroup: initialGroup,
            ),
          ),
        ),
      ),
    ),
  );
}
