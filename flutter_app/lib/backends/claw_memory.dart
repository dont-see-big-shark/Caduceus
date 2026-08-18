/// OpenClaw's memory files, as neutral entries.
///
/// Kept out of `claw_backend.dart` because it is a *parser*, not an adapter:
/// it turns markdown into entries and has no idea a gateway exists. That makes
/// it testable without a socket, which matters more here than usual — the
/// failure mode is a user's notes being mis-attributed or lost, and that is
/// found by feeding it awkward markdown, not by mocking a connection.
///
/// See `MEMORY_BRIDGE.md` §5.
library;

import 'package:agent_core/agent_core.dart';

/// The file OpenClaw's agents write their memories into.
const clawMemoryFile = 'MEMORY.md';

/// The tag marking entries that live inside the block Caduceus owns.
///
/// `MEMORY_BRIDGE.md` R2: only what the app wrote may be removed by the app.
/// The parser knows which entries are inside the `<!-- caduceus: -->` block,
/// so it says so on the entry rather than making the UI guess.
const clawManagedTag = 'caduceus:managed';

/// The workspace documents that describe who the agent is and who you are.
///
/// `AGENTS.md`, `TOOLS.md` and `HEARTBEAT.md` are deliberately absent: they
/// are operating instructions, not memory, and putting them in a memory view
/// buries the two documents that actually change as the agent learns.
const clawPersonaFiles = ['SOUL.md', 'IDENTITY.md', 'USER.md'];

/// Whether [name] is one of the workspace documents this app will write.
///
/// An allowlist, not a pattern. `agents.files.set` will happily write
/// `AGENTS.md` — the file that tells the agent how to operate — and a bug that
/// sent a persona document to that name would rewrite the agent's
/// instructions. The set of files this feature may touch is small and known,
/// so it is stated.
bool isClawPersonaFile(String name) => clawPersonaFiles.contains(name);

/// True when a workspace document is still the template it shipped with.
///
/// Every one of these files exists from first boot, filled with prompts like
/// `- **Name:**` and italic instructions to the agent. Showing that as
/// "what the agent knows about you" is worse than showing nothing: it looks
/// like knowledge and is a form.
///
/// The test is the *placeholder* markers rather than a checksum of the
/// original, because a user who deletes one line from the template has still
/// not told the agent anything, and a checksum would call that file learned.
bool clawDocumentIsTemplate(String content) {
  final body = content.trim();
  if (body.isEmpty) return true;
  // An unfilled field — `- **Name:**` with nothing after the colon.
  final unfilledFields = RegExp(
    r'^\s*[-*]\s*\*\*[^*]+:\*\*\s*(_\([^)]*\)_)?\s*$',
    multiLine: true,
  ).allMatches(body).length;
  // A whole-line italic instruction to the agent — `_Learn about the…_`.
  final instructions = RegExp(
    r'^\s*_[^_].*_\s*$',
    multiLine: true,
  ).allMatches(body).length;
  return unfilledFields >= 2 || (unfilledFields >= 1 && instructions >= 1);
}

/// [content] of `MEMORY.md`, split into one entry per `##` heading.
///
/// Headings rather than list items because a heading is what the agent's own
/// memory tooling writes, and because a bullet is rarely a whole thought — a
/// list under one heading is one memory with structure, not five memories.
///
/// Text before the first heading becomes one untitled entry rather than being
/// dropped: a memory file that is just prose is a perfectly ordinary thing for
/// a person to have written by hand, and losing it would be the worst kind of
/// bug in a feature about remembering.
List<MemoryEntry> clawMemoriesFromMarkdown(
  String content, {
  DateTime? updatedAt,
}) {
  final entries = <MemoryEntry>[];
  final lines = content.split('\n');

  var title = '';
  final body = StringBuffer();
  var inFence = false;
  var fence = '';
  // Whether the current entry began inside the block Caduceus owns. Only
  // those entries may be removed by this app (R2).
  var inBlock = false;
  var managedSinceLastFlush = false;
  // Slugs already handed out. Two sections can legitimately carry the same
  // heading, and letting both take the same id is how a later diff deletes
  // the wrong one — so the second occurrence is suffixed rather than shared.
  final used = <String>{};

  void flush() {
    final text = body.toString().trim();
    body.clear();
    if (text.isEmpty && title.isEmpty) return;
    var slug = _slug(title, entries.length);
    if (!used.add(slug)) {
      var attempt = 2;
      while (!used.add('$slug-$attempt')) {
        attempt++;
      }
      slug = '$slug-$attempt';
    }
    entries.add(
      MemoryEntry(
        id: 'openclaw:$clawMemoryFile#$slug',
        kind: MemoryKind.fact,
        title: title,
        text: text,
        updatedAt: updatedAt,
        tags: managedSinceLastFlush ? {clawManagedTag} : const {},
        origin: MemoryOrigin(
          backendId: 'openclaw',
          nativeId: '$clawMemoryFile#$slug',
        ),
      ),
    );
  }

  for (final line in lines) {
    final trimmed = line.trimLeft();
    // The block markers are this app's own scaffolding, not content. They
    // must not become an untitled entry (or the tail of the last one) when
    // the whole file is read.
    if (trimmed == memoryBlockBegin || trimmed == memoryBlockEnd) {
      inBlock = trimmed == memoryBlockBegin;
      continue;
    }
    // A `##` inside a fenced block is code, not a heading. Splitting on it
    // would cut a shell script in half and file the pieces as two memories.
    final fenceMatch = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed);
    if (fenceMatch != null) {
      final marker = fenceMatch.group(1)!;
      if (!inFence) {
        inFence = true;
        fence = marker;
      } else if (marker[0] == fence[0] && marker.length >= fence.length) {
        inFence = false;
      }
      body.writeln(line);
      continue;
    }
    if (!inFence && RegExp(r'^#{1,3}\s').hasMatch(trimmed)) {
      flush();
      managedSinceLastFlush = inBlock;
      title = trimmed.replaceFirst(RegExp(r'^#{1,3}\s+'), '').trim();
      continue;
    }
    body.writeln(line);
  }
  flush();

  return entries;
}

/// One persona document, as a single entry whose text is the whole file.
///
/// Returns null for a document still holding its template, which is the
/// honest reading of "the agent has not learned this yet".
MemoryEntry? clawPersonaEntry(
  String name,
  String content, {
  DateTime? updatedAt,
}) {
  if (clawDocumentIsTemplate(content)) return null;
  return MemoryEntry(
    id: 'openclaw:$name',
    kind: MemoryKind.persona,
    title: name,
    text: content.trim(),
    updatedAt: updatedAt,
    origin: MemoryOrigin(backendId: 'openclaw', nativeId: name),
  );
}

/// A stable, readable fragment id for a heading.
///
/// Falls back to the ordinal so two identically-titled sections — or a file of
/// untitled prose — still get distinct ids. Two entries sharing an id is how a
/// later phase's diff would delete the wrong one.
String _slug(String title, int ordinal) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9一-鿿]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'section-$ordinal' : slug;
}

/// The ledger's entries, rendered for the block Caduceus owns in `MEMORY.md`.
///
/// One `##` heading each, which is exactly what [clawMemoriesFromMarkdown]
/// reads back — the two are a pair, and a change to either is a change to
/// both. Round-tripped in tests for that reason: a render the parser cannot
/// read is how a managed block turns into one giant untitled entry on the next
/// read, and then into one giant entry written back.
///
/// An entry with no title is given one from its native id, because a run of
/// untitled entries would parse back as a single blob.
String renderClawMemoryBlock(List<MemoryEntry> entries) {
  final buffer = StringBuffer();
  for (final entry in entries) {
    final title = entry.title.trim().isEmpty
        ? _titleFromNativeId(entry.origin.nativeId)
        : entry.title.trim();
    buffer
      ..writeln('## $title')
      ..writeln()
      ..writeln(entry.text.trim())
      ..writeln();
  }
  return buffer.toString().trim();
}

/// A readable heading for an entry that arrived without one.
String _titleFromNativeId(String nativeId) {
  final fragment = nativeId.contains('#') ? nativeId.split('#').last : nativeId;
  final words = fragment.replaceAll('-', ' ').trim();
  return words.isEmpty ? 'Note' : words;
}
