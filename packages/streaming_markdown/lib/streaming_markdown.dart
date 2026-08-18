/// Incremental Markdown rendering for streaming LLM output.
///
/// The naive approach re-parses the accumulated response on every update, which
/// is quadratic in response length. This parses each block once. Measured on an
/// Android device: 42x less parser work for identical output — see
/// `docs/BENCHMARKS.md`.
library;

// Re-exported so a caller can style the transcript without taking a direct
// dependency on the Markdown renderer this package happens to use.
export 'package:flutter_markdown_plus/flutter_markdown_plus.dart'
    show MarkdownStyleSheet;

export 'src/block_splitter.dart';
export 'src/streaming_markdown_view.dart';
