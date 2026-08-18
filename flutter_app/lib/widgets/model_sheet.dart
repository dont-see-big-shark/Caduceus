import 'package:flutter/material.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

import '../design/components.dart';
import '../design/press.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../haptics.dart';

import '../l10n/app_localizations.dart';
import '../workspace.dart';
import 'panel_frame.dart';

/// What the picker was closed with.
///
/// Replaces a scheme that encoded the three outcomes as prefixed strings and
/// relied on no model id ever starting with the prefix. The provider slug is
/// why it has to be a type now: the same model name can be declared by two
/// configured providers, and the server refuses to guess between them.
sealed class ModelSheetResult {
  const ModelSheetResult();
}

class PickModel extends ModelSheetResult {
  const PickModel(this.model, this.providerSlug);
  final String model;
  final String providerSlug;
}

class ConnectProvider extends ModelSheetResult {
  const ConnectProvider(this.slug);
  final String slug;
}

class DisconnectProvider extends ModelSheetResult {
  const DisconnectProvider(this.slug);
  final String slug;
}

/// Model picker that opens immediately and loads inside itself.
///
/// `model.options` measured 3–7 seconds against the reference server, with no
/// speed-up on repeat. Awaiting it *before* showing the dialog produced a
/// button that did nothing for several seconds, which is what invited the
/// repeated taps that stacked dialogs and duplicated the call.
class ModelSheet extends StatefulWidget {
  const ModelSheet({
    required this.workspace,
    required this.sessionId,
    super.key,
  });

  final Workspace workspace;
  final String sessionId;

  @override
  State<ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<ModelSheet> {
  ModelInventory? _inventory;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh && mounted) setState(() => _refreshing = true);
    final inventory = await widget.workspace.modelInventory(
      widget.sessionId,
      refresh: refresh,
    );
    if (!mounted) return;
    setState(() {
      _inventory = inventory;
      _refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inventory = _inventory;

    return Panel(
      title: Row(
        children: [
          Expanded(
            child: Text(
              AppLocalizations.of(context)?.modelForThisSession ??
                  'Model for this session',
            ),
          ),
          IconButton(
            tooltip:
                AppLocalizations.of(context)?.requeryProviders ??
                'Re-query the providers',
            onPressed: _refreshing ? null : () => _load(refresh: true),
            icon: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
          ),
        ],
      ),
      content: PanelFrame(
        preferredWidth: 460,
        preferredHeight: 420,
        child: inventory == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Asking the server which models are available…',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  14,
                  4,
                  14,
                  MediaQuery.paddingOf(context).bottom + 20,
                ),
                children: [
                  for (final provider in inventory.providers) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 10, 0, 6),
                      child: Row(
                        children: [
                          Expanded(child: Eyebrow(provider.name)),
                          if (!provider.authenticated)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: StatusDot(
                                color: context.ink.base.withValues(alpha: .25),
                              ),
                            ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(
                              provider.authenticated
                                  ? DisconnectProvider(provider.slug)
                                  : ConnectProvider(provider.slug),
                            ),
                            child: Text(
                              provider.authenticated
                                  ? 'Disconnect'
                                  : 'Connect…',
                              style: TextStyle(
                                fontSize: 12,
                                color: provider.authenticated
                                    ? context.ink.tertiary
                                    : Palette.brass,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final model in provider.models)
                      _ModelRow(
                        model: model,
                        providerName: provider.name,
                        current: model == inventory.currentModel,
                        enabled: provider.authenticated,
                        onTap: () {
                          Haptics.select();
                          Navigator.of(
                            context,
                          ).pop(PickModel(model, provider.slug));
                        },
                      ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: context.ink.base.withValues(alpha: .03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.ink.hairline),
                      ),
                      child: Center(
                        child: Text(
                          '切换模型将在下一次交互生效',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.ink.faint,
                            letterSpacing: .2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// One model.
///
/// Refactored to match the premium card-based design in Image 4.
class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.providerName,
    required this.current,
    required this.enabled,
    required this.onTap,
  });

  final String model;
  final String providerName;
  final bool current;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: current
            ? context.ink.base.withValues(alpha: .10)
            : context.ink.base.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: current
              ? Palette.jade.withValues(alpha: .40)
              : context.ink.hairline,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(context, size: 13.5).copyWith(
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                    color: enabled
                        ? (current
                              ? context.ink.primary
                              : context.ink.secondary)
                        : context.ink.faint,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  providerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: context.ink.faint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (current)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Palette.jade.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Palette.jade.withValues(alpha: .32)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, size: 13, color: Palette.jade),
                  SizedBox(width: 4),
                  Text(
                    '当前',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Palette.jade,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    if (!enabled) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Opacity(opacity: .4, child: card),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: onTap,
        haptic: false,
        scale: .98,
        semanticLabel: model,
        child: card,
      ),
    );
  }
}
