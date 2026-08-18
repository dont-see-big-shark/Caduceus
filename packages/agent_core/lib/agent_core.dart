/// A backend-neutral model of an agent conversation, and the interface an
/// agent backend implements.
///
/// The package depends on nothing but `meta`. That is the point: the wire
/// clients (`hermes_protocol`, `openclaw_protocol`) do not know about these
/// types, and these types do not know about any wire. The *adapters* map
/// between them, which keeps both wire clients independently testable and
/// stops either protocol's vocabulary leaking into the app.
///
/// See `ARCHITECTURE.md` for why the interface is narrow and everything else
/// is a [Capability].
library;

export 'src/agent_graph.dart';
export 'src/attachment.dart';
export 'src/backend.dart';
export 'src/capability.dart';
export 'src/connection.dart';
export 'src/errors.dart';
export 'src/event.dart';
export 'src/inventory.dart';
export 'src/memory.dart';
export 'src/memory_block.dart';
export 'src/memory_match.dart';
export 'src/message.dart';
export 'src/model.dart';
export 'src/opened.dart';
export 'src/prompt.dart';
export 'src/session.dart';
export 'src/shared_memory.dart';
export 'src/skill.dart';
export 'src/tool.dart';
