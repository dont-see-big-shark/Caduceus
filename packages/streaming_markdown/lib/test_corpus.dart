/// Deterministic synthetic corpus, shared by the splitter tests.
///
/// The point of this file is reproducibility: the same seed always produces the
/// same character stream, so two render strategies can be compared on identical
/// input and results stay comparable across runs and machines.
library;

/// A small linear congruential generator. Dart's [Random] with a fixed seed
/// would also be deterministic, but its algorithm is not specified, so results
/// could drift between SDK versions. This one cannot.
class _Lcg {
  _Lcg(this.seed);
  int seed;

  int next(int max) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % max;
  }
}

/// Markdown section templates. `{i}` is replaced with the section index so the
/// generated document is long and varied without embedding a huge literal here.
///
/// The mix is deliberate — these are the constructs that actually cost time in
/// a Markdown renderer, in roughly the proportion an agent transcript contains
/// them. Fenced code is the expensive case and is over-represented on purpose.
const List<String> _sections = [
  '''
## Step {i}: inspect the failing case

The regression only reproduces when the session is resumed from a fork, which
narrows it to the replay path. Note that `previous_response_id` is threaded
through two layers here, and the **second** one silently drops it when the
upstream returns a `409`.
''',
  '''
```dart
Future<void> replay(SessionId id, {String? previousResponseId}) async {
  final events = await _gateway.events(id);
  for (final event in events) {
    switch (event.type) {
      case 'assistant.delta':
        _sink.add(event.text);
      case 'tool.started':
        _tools.begin(event.toolCallId, event.name);
      case 'tool.completed':
        _tools.finish(event.toolCallId, event.result);
      default:
        _log.warning('unhandled event: \${event.type}');
    }
  }
}
```
''',
  '''
Three things follow from that:

1. The replay path never sees the tool boundary, so nested calls collapse.
2. Fork inherits the parent cursor rather than resetting it.
3. Any retry after a `409` starts from a cursor that no longer exists.

> The third one is the actual bug. The first two are symptoms that happen to be
> visible earlier in the log, which is why this took so long to find.
''',
  '''
| surface | transport | auth | stateful |
|---|---|---|---|
| `/v1/chat/completions` | HTTP + SSE | bearer | no |
| `/v1/responses` | HTTP + SSE | bearer | yes |
| `/v1/runs/{i}/events` | SSE | bearer | yes |
| `tui_gateway` | WebSocket | session token | yes |
''',
  '''
```python
def coalesce(tokens, budget_ms=16):
    """Group tokens into at most one batch per frame budget."""
    batch, deadline = [], now() + budget_ms
    for tok in tokens:
        batch.append(tok)
        if now() >= deadline:
            yield "".join(batch)
            batch, deadline = [], now() + budget_ms
    if batch:
        yield "".join(batch)
```
''',
  '''
### Notes on section {i}

Applying the fix means the cursor has to become explicit state rather than an
implicit consequence of iteration order. That is a slightly larger change than
it sounds — `SessionCursor` currently has no identity of its own, and three
call sites construct one inline. See `lib/core/session/cursor.dart` for where
that would live.
''',
  '''
- [x] Reproduce with a forked session
- [x] Confirm the `409` path drops the cursor
- [ ] Add a regression test at the replay boundary
- [ ] Decide whether `SessionCursor` is a value type or an entity
  - if value: cheaper equality, but forking needs an explicit copy
  - if entity: identity is free, but every call site needs a factory
''',
];

/// Builds a deterministic Markdown document of roughly [targetChars]
/// characters by cycling the section templates.
String buildDocument({int targetChars = 12000, int seed = 42}) {
  final rng = _Lcg(seed);
  final out = StringBuffer();
  var i = 0;
  while (out.length < targetChars) {
    // Shuffle lightly so the document is not a strict repeating cycle, while
    // staying fully determined by the seed.
    final section =
        _sections[(i + rng.next(_sections.length)) % _sections.length];
    out.writeln(section.replaceAll('{i}', '${i + 1}'));
    i++;
  }
  return out.toString();
}

/// Splits [document] into token-sized chunks approximating an LLM token stream.
///
/// Real tokenizers emit pieces of roughly 1–6 characters with word boundaries
/// respected more often than not. The exact distribution does not matter for
/// this benchmark — what matters is that both strategies receive the identical
/// sequence, and that the chunk count is realistic.
List<String> tokenize(String document, {int seed = 7}) {
  final rng = _Lcg(seed);
  final tokens = <String>[];
  var pos = 0;
  while (pos < document.length) {
    final len = 2 + rng.next(4); // 2..5 chars
    final end = (pos + len).clamp(0, document.length);
    tokens.add(document.substring(pos, end));
    pos = end;
  }
  return tokens;
}

/// The standard benchmark stream: ~3,000 tokens of mixed Markdown.
List<String> defaultTokenStream() => tokenize(buildDocument());

/// Worst case for block segmentation: one enormous fenced code block.
///
/// The bounded-tail property depends on blocks being small, which the mixed
/// corpus guarantees by having blank lines every few lines. Agent transcripts
/// routinely violate that — "show me the file" produces a single fence hundreds
/// of lines long, and a fence has no internal boundary by design, so the tail
/// grows to the size of the whole block.
///
/// This is the input that decides whether "per-frame parse cost is bounded" is
/// a real property or an artefact of a friendly corpus.
String buildPathologicalDocument({int lines = 400}) {
  final out = StringBuffer()
    ..writeln('Here is the file you asked for.')
    ..writeln()
    ..writeln('```dart');
  for (var i = 0; i < lines; i++) {
    out.writeln(
      '  final field$i = compute(input$i, options: const Options('
      "retries: $i, label: 'step-$i'));",
    );
  }
  out
    ..writeln('```')
    ..writeln()
    ..writeln('That is the whole file.');
  return out.toString();
}

/// A long table — the other construct with no internal blank lines.
String buildWideTableDocument({int rows = 300}) {
  final out = StringBuffer()
    ..writeln('| id | name | status | latency | notes |')
    ..writeln('|---|---|---|---|---|');
  for (var i = 0; i < rows; i++) {
    out.writeln(
      '| $i | service-$i | ${i.isEven ? "ok" : "degraded"} '
      '| ${i * 3}ms | row $i of the report |',
    );
  }
  return out.toString();
}
