/// Pick a model from a flat catalog.
library;

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../workspace.dart';
import 'model_sheet.dart' show ModelSheetResult, PickModel;
import 'panel_frame.dart';

/// The picker for a backend that switches models but has no providers to
/// connect.
Future<ModelSheetResult?> showModelList(
  BuildContext context, {
  required Workspace workspace,
  required String sessionId,
  required String current,
}) => showPanel<ModelSheetResult>(
  context,
  (_) =>
      _ModelList(workspace: workspace, sessionId: sessionId, current: current),
);

class _ModelList extends StatefulWidget {
  const _ModelList({
    required this.workspace,
    required this.sessionId,
    required this.current,
  });

  final Workspace workspace;
  final String sessionId;
  final String current;

  @override
  State<_ModelList> createState() => _ModelListState();
}

class _ModelListState extends State<_ModelList> {
  late final Future<List<AgentModel>> _models = widget.workspace.models(
    widget.sessionId,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Panel(
      title: Text(l10n?.model ?? 'Model'),
      content: PanelFrame(
        preferredWidth: 420,
        preferredHeight: 460,
        child: FutureBuilder<List<AgentModel>>(
          future: _models,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final models = snapshot.data ?? const <AgentModel>[];
            if (models.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 16,
                ),
                child: Text(
                  l10n?.noModelList ??
                      'This server did not offer a model list.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.ink.secondary,
                  ),
                ),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: models.length,
              itemBuilder: (context, i) => _Row(
                model: models[i],
                selected: models[i].id == widget.current,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.model, required this.selected});

  final AgentModel model;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return ListTile(
      dense: true,
      enabled: model.available,
      onTap: model.available
          ? () => Navigator.of(context).pop(PickModel(model.id, model.provider))
          : null,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 18,
        color: selected ? Palette.brass : context.ink.faint,
      ),
      title: Text(model.label, style: mono(context, size: 12)),
      subtitle: model.provider.isEmpty && model.available
          ? null
          : Text(
              [
                if (model.provider.isNotEmpty) model.provider,
                if (!model.available) (l10n?.noCredential ?? 'no credential'),
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.ink.faint,
              ),
            ),
    );
  }
}
