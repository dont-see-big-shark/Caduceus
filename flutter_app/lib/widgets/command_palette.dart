/// ⌘K — every session action, in one place.
library;

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/components.dart';
import '../design/glass.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../haptics.dart';
import '../l10n/app_localizations.dart';
import 'console_menu.dart';

/// One thing the palette can do.
@immutable
class Command {
  const Command({
    required this.label,
    required this.run,
    this.shortcut = '',
    this.keywords = '',
    this.danger = false,
    this.enabled = true,
    this.needs,
  });

  final String label;
  final VoidCallback run;

  /// What the backend must declare for this row to exist.
  ///
  /// Absent, not disabled. A disabled row still tells the reader the feature
  /// is there and they are doing something wrong; an absent one tells the
  /// truth, which is that this agent does not have it.
  final Capability? needs;

  /// Printed on the right. Empty on a phone, where there is no ⌘ to press.
  final String shortcut;

  /// Extra words that should match this row — what someone would *call* it
  /// rather than what it is named. "undo" should find "Undo last exchange",
  /// but so should "revert" and "oops".
  final String keywords;

  final bool danger;
  final bool enabled;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return label.toLowerCase().contains(q) || keywords.contains(q);
  }
}

/// The session's whole action surface, derived from the same record the
/// menus use.
List<Command> sessionCommands(ConsoleActions a, [BuildContext? context]) {
  final l10n = context != null ? AppLocalizations.of(context) : null;
  return [
    Command(
      label: l10n?.undoLastExchange ?? 'Undo last exchange',
      needs: Capability.transcriptUndo,
      shortcut: '⌘Z',
      keywords: 'revert oops remove back 撤销 撤銷',
      enabled: !a.streaming,
      run: a.onUndo,
    ),
    Command(
      label: l10n?.findInConversation ?? 'Find in conversation…',
      shortcut: '⌘F',
      keywords: 'search grep look 查找 搜尋 搜索',
      run: a.onFindInConversation,
    ),
    Command(
      label: l10n?.copyTranscript ?? 'Copy transcript',
      keywords: 'clipboard export save 复制 複製',
      run: a.onCopyTranscript,
    ),
    Command(
      label: l10n?.fileCheckpoints ?? 'File checkpoints…',
      needs: Capability.checkpoints,
      shortcut: '⌘⇧C',
      keywords: 'restore revert files diff 检查点 檢查點',
      run: a.onShowCheckpoints,
    ),
    Command(
      label: l10n?.backgroundProcesses ?? 'Background processes…',
      needs: Capability.backgroundProcesses,
      shortcut: '⌘B',
      keywords: 'jobs running shell 进程 進程 后台 背景',
      run: a.onShowProcesses,
    ),
    Command(
      label: l10n?.agents ?? 'Agents…',
      needs: Capability.subagents,
      keywords: 'subagents workers 智能体 智能體',
      run: a.onShowAgents,
    ),
    Command(
      label: l10n?.journeyWhatItLearned ?? 'Journey — what it learned…',
      needs: Capability.learning,
      keywords: 'learning memory skills 学习 學習 历程 歷程',
      run: a.onShowJourney,
    ),
    // On a phone the palette *is* the session menu, so an entry missing here
    // is unreachable there however well it works on desktop.
    Command(
      label: 'Memory — what it knows about you…',
      needs: Capability.memoryRead,
      keywords:
          'memory remember knows about me profile '
          '记忆 記憶 知道 档案 檔案 人设 人設',
      run: a.onShowMemory,
    ),
    Command(
      label: l10n?.toolsetsSkillsPlugins ?? 'Toolsets, skills, plugins…',
      needs: Capability.skills,
      keywords: 'server tools mcp 工具 技能 插件 外挂',
      run: a.onShowServer,
    ),
    Command(
      label: 'Skills…',
      needs: Capability.skills,
      keywords: 'skills skill 技能 互通',
      run: a.onShowSkills,
    ),
    Command(
      label: 'Fleet — every agent, and who knows what…',
      needs: Capability.memoryRead,
      keywords:
          'agents fleet graph who knows whom relationship 关系 舰队 互通 '
          '谁认识谁 誰認識誰',
      run: a.onShowFleet,
    ),
    Command(
      label: 'Shared memory — facts every agent should know…',
      needs: Capability.memoryRead,
      keywords:
          'shared collective knowledge base sync drift 共享 集体 知识库 漂移 '
          '同步 應該知道 应该知道',
      run: a.onShowSharedMemory,
    ),
    Command(
      label: l10n?.usageAndContext ?? 'Usage and context…',
      needs: Capability.usageReporting,
      keywords: 'tokens cost stats window 用量 上下文',
      run: a.onShowStats,
    ),
    Command(
      label: l10n?.workingDirectory ?? 'Working directory…',
      needs: Capability.cwdControl,
      keywords: 'cwd path folder 工作目录 工作目錄 路径',
      run: a.onSetCwd,
    ),
    Command(
      label: l10n?.branchSession ?? 'Branch…',
      needs: Capability.sessionBranching,
      keywords: 'fork split copy 分支',
      run: a.onBranch,
    ),
  ].where((c) => c.needs == null || a.supports(c.needs!)).toList();
}

/// Opens the palette.
///
/// 移动端同一面板由下往上推 — the same list, entering from the bottom on a
/// phone and from above on a desktop. Same content, same order, same keyboard
/// handling; only where it comes from differs, because on a phone the top of
/// the screen is the furthest thing from your thumb.
Future<void> showCommandPalette(BuildContext context, List<Command> commands) {
  final phone = MediaQuery.sizeOf(context).width < 720;
  final dark = Theme.of(context).brightness == Brightness.dark;
  Haptics.select();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    // Weighted per mode, like the drawer's scrim. Black at 45% over a dark
    // transcript reads as a dimming; over a light one it reads as the app
    // switching off. The sheet is thick glass — the point is that you can
    // still see the conversation it came out of.
    barrierColor: Colors.black.withValues(alpha: dark ? .45 : .24),
    transitionDuration: Motion.emphasized,
    pageBuilder: (context, _, _) => _Palette(commands: commands, phone: phone),
    transitionBuilder: (context, animation, _, child) {
      final t = CurvedAnimation(
        parent: animation,
        curve: Motion.emphasizedCurve,
        reverseCurve: Motion.exitCurve,
      );
      return FadeTransition(
        opacity: t,
        child: SlideTransition(
          position: Tween(
            begin: Offset(0, phone ? .12 : -.04),
            end: Offset.zero,
          ).animate(t),
          child: child,
        ),
      );
    },
  );
}

class _Palette extends StatefulWidget {
  const _Palette({required this.commands, required this.phone});

  final List<Command> commands;
  final bool phone;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette>
    with SingleTickerProviderStateMixin {
  final _query = TextEditingController();
  final _focus = FocusNode();
  int _cursor = 0;

  /// 打开弹窗 = 玻璃变厚（blur 24→40），不是淡入.
  ///
  /// The sheet does not fade in; it *thickens*. That is what makes it read as
  /// coming forward out of the page rather than being drawn on top of it, and
  /// it is the one piece of this design that is genuinely hard to imitate with
  /// opacity.
  late final AnimationController _thicken = AnimationController(
    vsync: this,
    duration: Motion.emphasized,
    value: .2,
  )..forward();

  List<Command> get _visible =>
      widget.commands.where((c) => c.matches(_query.text.trim())).toList();

  @override
  void dispose() {
    _thicken.dispose();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _move(int delta) {
    final items = _visible;
    if (items.isEmpty) return;
    setState(() => _cursor = (_cursor + delta) % items.length);
    if (_cursor < 0) setState(() => _cursor += items.length);
  }

  void _runAt(int index) {
    final items = _visible;
    if (index < 0 || index >= items.length) return;
    final command = items[index];
    if (!command.enabled) return;
    Haptics.tap();
    // Closed *before* running: several of these open a dialog of their own,
    // and stacking a panel on top of the palette leaves the palette behind it
    // for the user to dismiss twice.
    Navigator.of(context).pop();
    command.run();
  }

  /// How far the sheet has been dragged down, in logical pixels.
  double _drag = 0;

  /// Past this, letting go dismisses rather than springs back.
  static const _dismissAfter = 90.0;

  void _onDragUpdate(DragUpdateDetails d) {
    if (!widget.phone) return;
    setState(() => _drag = (_drag + d.delta.dy).clamp(0, 400));
  }

  void _onDragEnd(DragEndDetails d) {
    if (!widget.phone) return;
    // Velocity *or* distance: a fast flick is a dismissal even if it covered
    // barely any ground, which is how the gesture is actually performed.
    final flung = d.velocity.pixelsPerSecond.dy > 700;
    if (flung || _drag > _dismissAfter) {
      Navigator.of(context).pop();
    } else {
      setState(() => _drag = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return Align(
      alignment: widget.phone ? Alignment.bottomCenter : Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(
          top: widget.phone ? 0 : 90,
          bottom: widget.phone ? 0 : 40,
          left: 12,
          right: 12,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: SafeArea(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    _move(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    _move(-1),
                const SingleActivator(LogicalKeyboardKey.enter): () =>
                    _runAt(_cursor),
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    Navigator.of(context).pop(),
              },
              child: AnimatedBuilder(
                animation: _thicken,
                builder: (context, child) => Transform.translate(
                  // Follows the finger 1:1 rather than easing behind it.
                  // Anything less makes the sheet feel stuck to the glass.
                  offset: Offset(0, _drag),
                  child: GlassPanel(
                    level: Glass.thick,
                    radius: Radii.largeAll,
                    thickness: _thicken.value,
                    child: child!,
                  ),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 支持下拉关闭 — the grab handle, and the whole header is
                      // the drag target. On a phone the palette rises from the
                      // bottom, so pulling it back down is the gesture the
                      // hand is already in position for; reaching for a
                      // dismiss button at the top is not.
                      if (widget.phone)
                        GestureDetector(
                          key: const ValueKey('palette-handle'),
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: _onDragUpdate,
                          onVerticalDragEnd: _onDragEnd,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 2),
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: context.ink.base.withValues(
                                    alpha: .22,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                        child: TextField(
                          controller: _query,
                          focusNode: _focus,
                          autofocus: !widget.phone,
                          onChanged: (_) => setState(() => _cursor = 0),
                          onSubmitted: (_) => _runAt(_cursor),
                          style: Theme.of(context).textTheme.bodyLarge,
                          decoration: InputDecoration(
                            hintText:
                                AppLocalizations.of(context)?.typeACommand ??
                                'Type a command…',
                            hintStyle: TextStyle(color: context.ink.faint),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 15,
                            ),
                          ),
                        ),
                      ),
                      Divider(height: 1, color: context.ink.hairline),
                      Flexible(
                        child: items.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(28),
                                child: Text(
                                  AppLocalizations.of(
                                        context,
                                      )?.nothingMatches(_query.text.trim()) ??
                                      'Nothing matches “${_query.text.trim()}”',
                                  style: TextStyle(
                                    color: context.ink.tertiary,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            // Scoped for two reasons: rows recycle when the
                            // list scrolls, and the list rebuilds on every
                            // keystroke while filtering. Without it the whole
                            // result set re-animates as you type, which is the
                            // opposite of what a filter should feel like.
                            : StaggerScope(
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  itemCount: items.length,
                                  itemBuilder: (context, i) => Staggered(
                                    index: i,
                                    from: const Offset(0, 6),
                                    child: _Row(
                                      command: items[i],
                                      selected: i == _cursor,
                                      phone: widget.phone,
                                      onTap: () => _runAt(i),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.command,
    required this.selected,
    required this.phone,
    required this.onTap,
  });

  final Command command;
  final bool selected;
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = command.danger
        ? dangerInk(context)
        : command.enabled
        ? context.ink.primary
        : context.ink.faint;
    return InkWell(
      onTap: command.enabled ? onTap : null,
      child: Container(
        // Selection is a brighter sheet, same as everywhere else in this
        // design — never an accent-coloured bar.
        color: selected
            ? context.ink.base.withValues(alpha: .10)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                command.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: ink),
              ),
            ),
            // A shortcut printed on a phone is instructions for hardware the
            // reader is not holding.
            if (!phone && command.shortcut.isNotEmpty)
              Text(
                command.shortcut,
                style: mono(context, size: 11, opacity: InkLevel.faint),
              ),
          ],
        ),
      ),
    );
  }
}
