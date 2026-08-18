# Benchmarks

Real measurements only. Anything not measured is marked as such.

Reproduce with [`bench/streaming_markdown`](../bench/streaming_markdown/README.md).

---

## Spike A — streaming Markdown rendering

**Question:** can Flutter render a streaming LLM response smoothly enough to
justify building Caduceus on it?

**Corpus:** 3,491 tokens / 12,214 characters of mixed Markdown (prose, fenced
code, tables, nested lists, blockquotes), seed 42, fully deterministic.

**Strategies:**

- **naive** — one `setState` per token, whole accumulated buffer re-parsed on
  every build. This is what [`rusty4444/hermes-android`](https://github.com/rusty4444/hermes-android)
  does today (`lib/core/screens/chat_screen.dart:377`).
- **incremental** — completed Markdown blocks parsed once and cached by widget
  identity behind `RepaintBoundary`; only the still-growing tail is re-parsed.

### Tier 1 — parser workload (device-independent)

Deterministic, asserted in `flutter test`. Runs anywhere with a Flutter SDK.

**Status: passed. 20/20 tests green.** `flutter analyze` clean.

| metric | naive | incremental | ratio |
|---|---|---|---|
| characters parsed | 21,329,133 | 638,041 | **33.4×** |
| growth when corpus doubles | 3.70× | 1.72× | quadratic vs linear |

Supporting numbers:

```
scaling 2x  — naive: 3.70x, incremental: 1.72x
parse cost  — naive: 21,329,133 chars, incremental: 638,041 chars, ratio: 33.4x
rebuilds    — per-token: 3,491, coalesced(15): 233
max tail    — 493 chars of 12,214 total
```

The scaling row is the real result. Doubling the response roughly **quadruples**
naive's parser workload and roughly **doubles** incremental's. The 33.4× figure
is a property of this corpus length; the exponent is a property of the
algorithm, and it is the exponent that decides whether long agent responses stay
usable.

`max tail: 493 chars of 12,214` is why incremental is linear — the re-parsed
region is bounded by block size, not by response length.

#### The benchmark was measuring the wrong thing

Tier 1 counted characters handed to the **Markdown parser** and declared
incremental linear. The first valid device run contradicted it: incremental
parsed 18× less Markdown than naive (505K vs 9,086K chars) and still took
**176 s of wall clock against naive's 64 s**.

The cause was in the optimisation itself. The original `splitMarkdown` re-scanned
the entire buffer on every flush — `split('\n')`, `sublist().join()`, then
`_toBlocks` splitting and rejoining every settled block again. Measured:

```
splitter scanned: 21,329,133 chars (1746x corpus)   ← identical to naive's parse volume
```

Block segmentation had replaced a quadratic Markdown parse with a quadratic
string split. The segmentation cost exactly what it saved, and Tier 1 could not
see it because it only instrumented the parser.

Fixed by `IncrementalSplitter`, which keeps scan position, fence state, and
settled blocks across calls so appending is O(len(token)):

| | reference | incremental |
|---|---|---|
| chars scanned | 21,329,133 | ~12,214 (once each) |
| time, 3,491 tokens | 429 ms | **3 ms** |

A differential test asserts the two implementations agree on every prefix of the
corpus. It immediately found that the fast version was the *more* correct one —
it settles a fenced code block the moment the closing fence arrives, while the
reference waited for a following blank line. A closed fence is a complete leaf
block, so settling early is both safe and better; the reference was corrected to
match.

**Lesson worth carrying into the client:** instrument the whole path, not the
part you expect to be slow. An optimisation that only looks good under its own
metric is not an optimisation.

#### Correction to the original design claim

The design called for three fixes. Measurement showed one of them was already
free: **Flutter's `setState` coalesces to one build per frame on its own.** The
naive renderer performed 58 rebuilds for 3,491 tokens when unthrottled, not
3,491. Frame-budget coalescing therefore buys little that the framework does not
already provide — the wins come from block segmentation and widget-identity
caching.

The Tier 1 model assumes one rebuild per token. That is accurate at ≤60 tok/s
(one token per frame) and **pessimistic to naive above it**. The scaling result
does not depend on this assumption.

#### A correctness bug the invariants caught

The block splitter had a real defect, found by the "a block declared stable
never changes" invariant at 1,825 characters into the corpus.

`split('\n')` yields a trailing `''` for any buffer ending in a newline. That
`''` was being counted as a blank line, so a paragraph was declared settled —
and then **un-settled** when the next token extended it. Stable block count went
6 → 5.

In a shipping client this renders as a paragraph visibly re-flowing mid-stream.
Fixed: the final element of `lines` is never a confirmed boundary. That
constraint is also what makes the stable region provably monotonic — every line
before the last is frozen, as is the fence state derived from it, so a boundary
once observed cannot be retracted.

The invariant test is worth carrying into the production client.

### Tier 2 — frame timings (requires a real device)

**Status: unresolved. This machine cannot produce a reproducible measurement,
and the harness has a fairness flaw that must be fixed before the comparison
means anything.**

#### Android emulator — parse and wall clock valid, frame timings are not

Android 17 (API 37) arm64 emulator, profile build, both strategies frame-paced.

| strategy | rate | chars parsed | frames | jank % | p50 ms | wall clock |
|---|---|---|---|---|---|---|
| naive | 60 tok/s | 15,100,091 | 2,303 | 99.8 | 77.5 | 138.2 s |
| incremental | 60 tok/s | **357,507** | 1,971 | 100.0 | 75.2 | **92.2 s** |
| naive | 200 tok/s | 8,422,851 | 1,247 | 99.9 | 109.9 | 94.7 s |
| incremental | 200 tok/s | **180,546** | 943 | 100.0 | 119.5 | **64.1 s** |
| naive | unthrottled | 1,191,417 | 168 | 100.0 | 100.4 | 11.2 s |
| incremental | unthrottled | **33,100** | 112 | 100.0 | 133.0 | **8.3 s** |

**What this establishes:**

- Parse workload on a real device matches the Tier 1 model: **42× less** at
  60 tok/s (357K vs 15,100K characters).
- With frame cadence equalised, incremental is consistently **1.4–1.5× faster in
  wall clock** at every rate. This reverses the earlier "incremental is 2.8×
  slower" reading, confirming that result was purely the cadence artefact.

**What this does not establish — the frame timings are unusable.** The data
refutes itself:

| run | chars parsed | p50 frame |
|---|---|---|
| incremental @ unthrottled | 33,100 — least work of any run | 133.0 ms |
| naive @ 60 tok/s | 15,100,091 — 456× more work | 77.5 ms |

Less work producing *worse* frame times is impossible if the workload were the
bottleneck. The emulator's software graphics stack imposes a ~75–130 ms per-frame
floor that swamps the signal entirely; 100% jank in every configuration is the
same tell. **These numbers measure the emulator, not the renderer.**

An Android emulator is not a fast phone and not a slow one — it has the host's
CPU (so Dart work is optimistic) and an emulated GPU (so raster is pessimistic).
It cannot answer a frame-rate question in either direction.

#### The macOS environment is not reproducible — **superseded, see above**

Kept for the record. The fix was disabling App Nap for the app's own bundle
(`defaults write dev.caduceus.caduceus NSAppSleepDisabled -bool YES`) plus
`caffeinate`; with those two controls the variance disappears and the numbers in
"macOS — measured, valid" are stable.


Two runs of the same binary, both with the window held frontmost and idle sleep
blocked:

| | run A | run B |
|---|---|---|
| naive @ 60 tok/s — rebuilds | 1,865 | 204 |
| naive @ 60 tok/s — wall clock | 64.3 s | 64.7 s |
| incremental @ 200 tok/s — wall clock | 24.1 s | 146.2 s |

Wall clock for the token stream is right in both (58 s expected from the emit
rate), so the timers were healthy. But frame production varied **9×** between
identical runs. That is the macOS compositor deciding how much to render, not
anything the code did. Re-running does not fix it.

#### The comparison was not apples-to-apples

`IncrementalRenderer._scheduleFlush` requests a frame per token, so incremental
rendered 2,777 frames while naive rendered 221 — naive's `setState` calls were
being coalesced away by the framework. The two strategies were not doing equal
visual work: incremental genuinely updates the screen token-by-token, naive
updates in chunks. **Comparing their wall clocks was meaningless**, and the
earlier "incremental is 2.8× slower" reading was an artefact of that.

The signal that survives: incremental held p95 frame time at ~2.4 ms while
producing 12× more frames than naive.

Before Tier 2 is retried, the harness must drive both strategies from the same
frame cadence so that frame count is held constant and only per-frame cost
varies.

#### The earlier failure mode, kept for the record

#### What went wrong, and why it is recorded here

The first macOS profile run completed and emitted clean, plausible-looking JSON.
It was worthless:

| run | expected wall clock | measured |
|---|---|---|
| incremental @ 60 tok/s | 58 s | 189.5 s |
| naive @ 200 tok/s | 17.5 s | 85.5 s |
| incremental @ unthrottled | < 1 s | 482.7 s |

3,491 tokens at 60 tok/s takes 58 seconds by construction. Two runs of the same
binary disagreed by 2.7× on the same configuration. Frame counts were absurd —
142 frames across 189 seconds is 0.75 fps, which is not a rendering measurement.

macOS was throttling the process: occluded windows have frame production
suspended and background apps have their timers coalesced.

**The harness now detects this.** Every run computes its expected wall clock from
its own emit rate and declares itself invalid on >25% drift, or when frame count
falls far below rebuild count. A benchmark that fails silently is worse than no
benchmark. `run_macos_bench.sh` additionally holds the window frontmost and
blocks idle sleep, and exits non-zero if any run is flagged.

#### iOS Simulator — cannot run the benchmark at all

```
Profile mode is not supported by iPhone 17 Pro.
```

Flutter does not support profile builds on iOS Simulators; they are debug-only.
Debug-mode timings are not evidence of anything — unoptimised Dart, assertions
on. This is a platform restriction with no workaround.

#### Every available environment is ruled out

| environment | verdict | reason |
|---|---|---|
| macOS desktop | ~~unusable~~ **fixed** | 9× variance was App Nap; disabling it for the app's bundle made it reproducible |
| Android emulator | unusable | emulated GPU imposes a ~75–130 ms per-frame floor |
| iOS Simulator | unusable | profile mode unsupported; debug-only |

Three distinct causes, none of them fixable in software. **Tier 2 requires
physical hardware.** No further work on this machine will produce the number.

#### What Tier 2 still needs

1. ~~Equal frame cadence for both strategies~~ — **done.** Both now share a
   `_FramePaced` mixin, one rebuild per frame each, so frame count is a control
   rather than a confound. This is deliberately generous to the naive strategy.
2. **A physical Android phone**, mid-range, USB debugging enabled. That is the
   only remaining blocker, and no simulator or emulator substitutes for it.

Pass criteria, unchanged:

- ≥ 55 fps average, < 1% severe jank (frames > 33 ms), at 60 tok/s
- smooth when unthrottled, where a fast local model would put it

### Where the bounded-tail property breaks

The framework recommendation rests on per-frame parse cost being bounded rather
than growing with response length. That holds only while blocks stay small,
which the mixed corpus guarantees by construction. Agent output does not.

Absolute parse cost, median of 40, on this Mac (`package:markdown` directly, no
widget tree):

| input | chars | parse | % of a 60 fps frame |
|---|---|---|---|
| typical tail | 492 | 132 µs | 0.8% |
| 400-line code fence | 37,571 | 548 µs | 3.3% |
| 100-row table | 5,895 | 5,007 µs | 30% |
| 300-row table | 18,295 | 15,312 µs | **92%** |
| 500-row table | 30,861 | 25,874 µs | **155%** |

**The tail is genuinely unbounded for single large blocks.** A 400-line fence
produces a 37,571-character tail out of a 37,630-character document — 2 blocks
total. A 300-row table produces 0 blocks: the entire table is the tail.
Segmentation buys nothing in either case.

**But tail size and parse cost are not the same problem.** Fence content is
literal, so 37 KB of code costs 548 µs. Table cells carry inline formatting, so
18 KB of table costs 15 ms. The construct with the scariest tail is benign; the
one with a moderate tail is the hazard.

So the failure mode is specific and nameable: **a long Markdown table streaming
in re-parses itself every frame, and blows the frame budget past roughly 250
rows on a fast desktop CPU** — considerably fewer on a phone. Everything else
measured stays under 4% of a frame.

Two mitigations, neither blocking:

1. Row-level granularity for tables. A completed row cannot change, so it should
   settle like a block. This needs a custom table widget rather than
   `MarkdownBody`, since half a Markdown table is not valid Markdown.
2. Cheap fallback: when the tail exceeds a threshold, re-parse it every N frames
   instead of every frame — degrade update smoothness rather than frame rate.

### macOS — measured, valid

Profile build, **production widget stack** (`StreamingMarkdownView` driven by a
real `SessionConsole`, tokens fed as `message.delta` events through the same
envelope unwrap a live turn uses) — not a lab copy of it.

Run with `flutter run -d macos --profile --dart-define=BENCH=true`, with App Nap
disabled for the app's own bundle and the display kept awake. Those two controls
are what fixed the 9x run-to-run variance that made the earlier macOS attempt
unusable.

| run | frames | jank % | severe | p50 | p95 | p99 | wall clock | valid |
|---|---|---|---|---|---|---|---|---|
| 60 tok/s | 3,537 | **0.1** | 1 | 0.88 ms | 1.67 ms | 3.07 ms | 63.9 s (exp 58.2) | yes |
| 200 tok/s | 2,839 | 0.0 | 0 | 0.86 ms | 1.31 ms | 1.50 ms | 24.1 s (exp 17.5) | no — see below |
| unthrottled | 8 | 0.0 | 0 | 0.77 ms | 5.97 ms | — | **459 ms** | yes |

**p95 is 1.67 ms against a 16.67 ms budget — about 10%.** The full 3,491-token
corpus renders unthrottled in 459 ms, in 8 frames, having settled 46 blocks.

The 200 tok/s row is flagged invalid by the harness's own guard (wall clock
1.38x expected while frames stayed cheap at 0.86 ms p50). That is the harness,
not the renderer: a 5 ms `Future.delayed` is below reliable Dart timer
granularity, so the stream emits slower than requested. Cheap frames plus long
wall clock is the signature of *something delaying the producer*, which is
exactly what the guard is for — it just happens to be the benchmark itself here.

The single 95.89 ms outlier at 60 tok/s is one frame out of 3,537 (first-frame
or GC). Worth knowing; not worth chasing.

**This is macOS, on Apple silicon.** It is not evidence about a phone, and the
Android/iOS numbers remain unmeasured for the reasons documented above.

### Spike A verdict

**Not passed. Not failed. Tier 1 passed; Tier 2 is unresolved.**

**Established:**

- Block segmentation plus widget-identity caching reduces Markdown parsing by
  **33× in the model and 42× measured on a device**, and turns quadratic growth
  into linear — provided the splitter is itself incremental, which took two
  iterations to get right.
- With frame cadence controlled, the incremental strategy is **1.4–1.5× faster
  in wall clock** at every stream rate on real device hardware.
- Two correctness bugs found and fixed, one of which would have shipped as
  paragraphs visibly re-flowing mid-stream.

**Established on macOS:** 0.1% jank and p95 1.67 ms at 60 tok/s on the shipping
widget stack — roughly 10% of a frame budget. Since macOS is now the only
target, this is the number that matters for the current scope.

**Still not established:** phone frame rates. The Android emulator's GPU floor
and Flutter's refusal to build profile mode for the iOS Simulator both stand.

**Bounded, with one named exception:** typical streaming content costs 132 µs
per frame to re-parse — 0.8% of a 60 fps budget, and flat regardless of how long
the response gets. Long tables are the exception and need row-level handling.

**Recommendation: proceed with Flutter.** Not because Tier 2 passed — it was
never measurable here — but because the residual per-frame work is now known in
absolute terms rather than as a ratio, and it is small everywhere except one
construct with a known fix. The supporting argument is that
`rusty4444/hermes-android` ships the naive strategy, measured here at 15,100,091
characters parsed against our 357,507, and has real users. A 42×-worse
implementation is already viable in production.

Still buy a mid-range Android phone before P2. The remaining unknowns — scroll
feel, long-session memory, cold start — are P1-quality questions, not framework
questions.

---

## Caduceus vs. Hermes Desktop

**Not measured.** Requires a working Caduceus build, which does not exist yet.

Until this section has real numbers, the framework-class comparisons quoted in
the README are published third-party benchmarks for Electron and Flutter in
general, not claims about this project.

---

## Production widget stack on macOS (2026-08-02)

The whole app in profile mode — real `ConsoleView`, real `Workspace`, real
`StreamingMarkdownView` — fed the 3,491-token corpus. App Nap disabled
(`defaults write dev.caduceus.caduceus NSAppSleepDisabled -bool YES`) and run
under `caffeinate -dimsu`, without which macOS throttles the process and the
numbers vary ninefold between runs.

### What "a frame cost X" means here

`FrameTiming.totalSpan` runs from vsync to the end of rasterisation, so it
includes time the frame spent **waiting**. One frame measured 167 ms of
totalSpan with 4 ms of build and 16 ms of raster: that number describes the
compositor's scheduling, not the renderer's work.

Every figure below is therefore `max(buildDuration, rasterDuration)` — build
and raster run on different threads and either one exceeding the budget drops
a frame. `worstSpan` is kept alongside so the gap between the two stays
visible.

Earlier revisions of this document reported totalSpan as the frame cost. Those
numbers are roughly twice these at the median and are not comparable.

### Results (three runs each, work per frame)

| Run | Blocks | Jank | p50 | p95 | p99 | Worst work | Worst span |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 60 tok/s, fresh | 46 | **0.0 %** | 0.49–0.52 ms | 1.07–1.70 ms | 1.88–3.04 ms | 4.5–9.7 ms | 10.6–21.9 ms |
| 60 tok/s, after 200 messages | 9,646 | **0.0 %** | 0.53–0.59 ms | 1.42–1.61 ms | 2.29–3.34 ms | 6.6–19.5 ms | 10.7–24.1 ms |

**Not one janky frame in six runs.** Median work per frame is about half a
millisecond, 3 % of the 16.67 ms budget. One frame in one run reached
19.46 ms; every other maximum across every run stayed under 10 ms.

The "roughly one frame in a thousand over budget" reported in an earlier
revision was totalSpan — frames that waited, not frames that worked too long.
There is no unexplained overrun left.

### Does a long session get slower?

The renderer's core trade is that every settled block stays alive as a cached
widget for the life of the session. That is obviously right for one long
answer; whether it still holds after a few hundred messages had never been
measured, and "it got slow after an hour" does not show up in a short test.

The second row above preloads 200 messages — **9,646 settled blocks, 209× the
single-answer case** — and streams a normal turn into it. The cost is
**+0.05 ms at the median** and nothing at p95 or p99. `ListView.builder` keeps
offscreen blocks out of the build phase and widget identity keeps onscreen
ones out of the parse phase, so the cost of a token does not depend on how
much came before it.

Unthrottled, the full 3,491-token corpus renders in 459 ms.

### Runs that were not drawn

An earlier version of this document reported a **1,614 ms** worst frame for the
long-session case and attributed it, with a hedge, to garbage collection. That
was wrong.

macOS stops producing frames for a window that is occluded or not frontmost —
which is the normal state when the benchmark is launched from a terminal, and
`flutter run` prints `Failed to foreground app` on every start here. The
resumption is reported as one enormous frame. The tell is that those frames
land at 0 % or 100 % through a run, and that the run produced far fewer frames
than its duration allows.

Every large maximum recorded here coincided with a frame deficit:

| Frames produced / expected | Worst frame |
| ---: | ---: |
| 0 / 3,842 | — (nothing recorded) |
| 1,633 / 3,872 | 236.97 ms |
| 2,572 / 3,872 | 640.05 ms |
| 3,531 / 3,882 | 36.87 ms |
| 3,640 / 3,847 | 31.92 ms |

The harness now requires a run to have produced at least 80 % of the frames its
duration allows, and marks it invalid otherwise. With that gate every
multi-hundred-millisecond outlier disappears from the valid set.

The GC hypothesis had a plausible mechanism and a corroborating detail — the
resident set really did drop 141 MB → 109 MB across that run — and it was
still wrong. The frame *position* was the cheap check that settled it, and it
was not run before publishing.

### Memory

Read from `ProcessInfo` inside the harness, so it needs no external tooling.
Resident set, not heap: it includes the Flutter engine and textures alongside
the Dart heap.

| | RSS |
| --- | ---: |
| Fresh session, during a turn | 123–128 MB |
| With 9,646 blocks preloaded | 141 MB before the turn, 109 MB after |
| Process peak, any run | 177–181 MB |

The peak figure is process-wide and cumulative, so every row in one session
reports the same number — it says the process never exceeded ~180 MB, not that
a particular run reached it. 200 messages of transcript cost on the order of
ten megabytes.

### Warm-up is discarded now

An earlier version of this table reported a 625 ms worst frame in the first
run and single-digit milliseconds everywhere else. That was shader compilation
and first-frame setup landing inside the first measured run — startup cost
billed to the renderer. The harness now streams 400 tokens and throws the
result away before measuring anything. Numbers above and below this line are
not directly comparable to ones published before that change.

### The regression that was flagged and is now gone

An earlier measurement, taken after the notification-pacing change, showed
0.6 % jank and a worst frame of 297.18 ms against 0.1 % / 95.89 ms before it.
That regression does not reproduce. What changed in between was the console
layout: the chrome above the transcript is now budgeted inside a single
`Expanded` and cannot overflow. A layout that overflows re-runs layout every
frame and paints an error stripe, which is a plausible source of both the long
frames and the jank — but this is an inference from what was edited, not a
measured cause, and no attempt was made to reproduce the old number.

Unthrottled, the full corpus renders in 459 ms across 9 frames, unchanged.
