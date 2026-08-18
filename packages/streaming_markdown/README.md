# streaming_markdown

Incremental streaming Markdown parser and block segmentation engine for Flutter, with widget-identity caching for smooth 60fps LLM stream rendering.

## Overview

`streaming_markdown` solves the quadratic $O(N^2)$ re-parsing overhead in streaming LLM interfaces by splitting streaming Markdown into settled immutable blocks and an incremental active tail.

- **Incremental Parser & Block Splitter**: Settled blocks are identified and cached by widget identity behind `RepaintBoundary`.
- **Zero-Jank Streaming**: Frame-budget coalescing ensures smooth rendering during high-speed token generation without blocking the UI thread.

