/// A model a session can be answered by.
library;

import 'package:meta/meta.dart';

/// One model, as a backend offers it.
///
/// The intersection of what every agent can say about one: which model it is,
/// what to call it, and who runs it. What a specific backend knows on top —
/// Hermes' provider connection state and API keys, OpenClaw's alias — belongs
/// to that backend's own surface, not here.
@immutable
class AgentModel {
  const AgentModel({
    required this.id,
    this.name = '',
    this.provider = '',
    this.available = true,
    this.contextTokens = 0,
    this.reasoning = false,
  });

  /// What [AgentBackend.selectModel] takes. Not the display name: the two
  /// differ on both backends, and sending the label back is how a model
  /// switch silently selects nothing.
  final String id;

  /// What to show. Falls back to [id], which at least names it.
  final String name;

  /// Who runs it — `volcengine`, `anthropic`. Free text; a backend's own word.
  final String provider;

  /// False when the backend knows about it but cannot currently use it —
  /// usually a provider with no credential. Shown, and not selectable.
  final bool available;

  /// Context window, where the backend reports one. Zero means it did not.
  final int contextTokens;

  /// True when this model reasons before answering, so a client can say why a
  /// wait is long before the wait happens.
  final bool reasoning;

  String get label => name.trim().isEmpty ? id : name.trim();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AgentModel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AgentModel($id${provider.isEmpty ? '' : ' @$provider'})';
}
