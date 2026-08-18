# Spike A — streaming Markdown render performance

> **Nothing here has been executed yet.** It was written on a machine with no
> Flutter SDK. Expect to fix a version constraint or two on first `pub get`.
> See [Status](#status).

## The question

Can Flutter render a streaming LLM response smoothly enough to justify the whole
premise of Caduceus? If the answer is no, the project should switch frameworks
before any product code exists.

## Why this specific comparison

The incumbent Flutter client for Hermes
([`rusty4444/hermes-android`](https://github.com/rusty4444/hermes-android),
`lib/core/screens/chat_screen.dart:377`) does this on every arriving token:

```dart
onToken: (token) {
  setState(() {
    _messages.last['content'] = (_messages.last['content'] as String) + token;
  });
},
```

…and its `build()` hands the entire accumulated string to `MarkdownBody`. So an
n-character response re-parses ~n²/2 characters of Markdown. This is not a
strawman — it is the obvious implementation, and it is what most clients ship.

**Strategy A** reproduces that faithfully. **Strategy B** applies three fixes:

| | change | cost it removes |
|---|---|---|
| 1 | frame-budget coalescing — at most one rebuild per frame | rebuilds under a fast stream |
| 2 | block segmentation — only the growing tail is re-parsed | quadratic parse work |
| 3 | settled blocks cached by widget identity + `RepaintBoundary` | re-parse and repaint of finished content |

Fix 3 relies on a real Flutter behaviour rather than a trick: returning the
*identical* widget instance from a builder makes the framework skip that
subtree's rebuild entirely, so `MarkdownBody.build` — and therefore the parser —
never runs on settled content again.

## Layout

```
lib/
  corpus.dart           deterministic ~3,000-token Markdown stream (seeded)
  block_splitter.dart   settled-vs-growing boundary detection  ← the core algorithm
  renderers.dart        Strategy A and Strategy B
  metrics.dart          FrameTiming collection + parser workload counters
  main.dart             harness UI: run, compare, export JSON
test/
  block_splitter_test.dart  correctness — runs anywhere
  parse_cost_test.dart      parser workload — runs anywhere
```

## Running it

### Tier 1 — no device needed (Flutter SDK only)

Measures parser workload and proves the asymptotic claim. Runs on any machine.

```bash
cd bench/streaming_markdown && flutter pub get && flutter test
```

Expected output includes lines like `parse cost — naive: … incremental: … ratio: …x`.

### Tier 2 — real device required

Frame timings. **Profile mode, physical device.** Debug builds run the VM
unoptimised with assertions on, and a simulator does not have the target's GPU
or thermal behaviour — numbers from either are not evidence of anything.

```bash
flutter run --profile -d <device-id>
```

Tap **Run all 6** (2 strategies × 3 stream rates), then the copy button to export
results JSON.

## Pass criteria

P0 gate:

- [ ] Strategy B holds **≥ 55 fps average with < 1% severe jank** (frames > 33 ms) at 60 tok/s on a mid-range Android device
- [ ] Strategy B's parse cost is **linear**, and ≥ 10× below Strategy A's on the standard corpus
- [ ] Strategy B stays smooth **unthrottled**, where a fast local model would put it
- [ ] The splitter's invariant tests pass over every prefix of the corpus

**If B fails on a mid-range device, Flutter is the wrong bet** and Tauri v2
should be re-evaluated before P1 starts. That is the decision this spike exists
to inform — a negative result here is a successful spike.

## Reading the numbers

- **chars parsed** — the asymptotic claim. Device-independent.
- **rebuilds** — how much of the win comes from coalescing vs. from segmentation.
- **jank %** — frames over the 16.67 ms budget. This is what a user feels.
- **p95 / worst ms** — averages hide stutter; tails do not.

`FrameTiming.totalSpan` is used rather than build time alone: a strategy that
merely moves work from the UI thread to the raster thread has not made anything
faster for the user.

## Status

**Tier 1 passes** — 22/22 tests, `flutter analyze` clean, on Flutter 3.44.8.
Android, iOS, and macOS runners are generated.

**Tier 2 is blocked on hardware.** All three environments available here were
ruled out — macOS varies 9× run to run, the Android emulator's software GPU
imposes a ~75–130 ms frame floor, and Flutter cannot build profile mode for iOS
Simulators at all. Results and evidence in [`docs/BENCHMARKS.md`](../../docs/BENCHMARKS.md).

A physical mid-range Android phone is the only thing missing.

### Known follow-ups

- `IncrementalRenderer` stops flushing if frame production is suspended
  (`_framePending` latches while the window is minimised). Harmless in a
  benchmark; the real client needs a timer fallback so a backgrounded stream
  resumes cleanly.
- `splitMarkdown` is retained only as the reference implementation the
  differential test checks `IncrementalSplitter` against. Do not use it in the
  client — it is quadratic by design.
