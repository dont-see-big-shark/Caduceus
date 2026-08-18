/// Constants for Hermes Gateway control-plane event types.
abstract final class HermesEventTypes {
  static const String messageDelta = 'message.delta';
  static const String reasoningDelta = 'reasoning.delta';
  static const String thinkingDelta = 'thinking.delta';

  static const String toolGenerating = 'tool.generating';
  static const String toolStart = 'tool.start';
  static const String toolComplete = 'tool.complete';

  static const String messageStart = 'message.start';
  static const String messageComplete = 'message.complete';

  static const String sessionInfo = 'session.info';
  static const String sessionTitle = 'session.title';

  static const String approvalRequest = 'approval.request';

  static const String clarifyRequest = 'clarify.request';
  static const String sudoRequest = 'sudo.request';
  static const String secretRequest = 'secret.request';

  static const String clarifyExpire = 'clarify.expire';
  static const String sudoExpire = 'sudo.expire';
  static const String secretExpire = 'secret.expire';

  static const String terminalReadRequest = 'terminal.read.request';
  static const String terminalReadExpire = 'terminal.read.expire';
}
