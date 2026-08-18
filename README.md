<div align="center">

<img src="flutter_app/assets/images/logo.png" width="128" height="128" alt="Caduceus Logo" />

# Caduceus

**All platforms. A high-performance native client for Multi Agent Systems, like [Hermes Agent](https://github.com/NousResearch/hermes-agent) and [OpenClaw](https://openclaw.ai).**

macOS · iOS · Android · Windows

[![Status](https://img.shields.io/badge/status-alpha-orange.svg)](#roadmap)
[![License](https://img.shields.io/badge/License-MIT%20with%20Commons%20Clause-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20Android%20%7C%20Windows-555555.svg?logo=apple&logoColor=white)](#)
[![Tests](https://img.shields.io/badge/tests-890%2B%20passed-success.svg?logo=github-actions&logoColor=white)](#)
[![Architecture](https://img.shields.io/badge/architecture-multi--agent%20seam-8A2BE2.svg)](docs/ARCHITECTURE.md)
[![Design](https://img.shields.io/badge/design-Liquid%20Glass-FF69B4.svg)](docs/DESIGN.md)
[![Streaming Jank](https://img.shields.io/badge/streaming%20jank-0.0%25-brightgreen.svg)](docs/BENCHMARKS.md)
[![Code Style](https://img.shields.io/badge/code%20style-flutter__lints-00A4D3.svg)](https://pub.dev/packages/flutter_lints)

</div>

---

## What is Caduceus?

[Hermes Agent](https://hermes-agent.nousresearch.com/) is Nous Research's open-source, self-hosted AI agent with persistent memory and tool use. [OpenClaw](https://openclaw.ai) is an autonomous multi-modal agent gateway.

**Caduceus** is a native, cross-platform client designed to drive these long-running AI agents without compromise — named after the herald's staff Hermes carries.

---

## Why Caduceus?

Existing agent clients typically excel on only one platform while remaining unavailable on the others:

| Client | Platforms | Technology Stack | Scope |
|---|---|---|---|
| Hermes Desktop (official) | macOS, Windows, Linux | Electron + React | Desktop only |
| `rusty4444/hermes-android` | Android | Flutter | Mobile only (Chat subset) |
| `uzairansaruzi/hermex` | iOS | SwiftUI | iOS only |
| `Yasuui/hermes-mobile` | iOS | Native iOS | iOS only |
| `abhibansal-sg/hermes-ios` | iOS | Native iOS | iOS only |
| `ChloeVPin/hermes-web` | Web | Browser UI | Web only |
| **Caduceus** | **macOS, iOS, Android, Windows** | **Flutter Native + C FFI Engine** | **Full Multi-Agent Console** |

If you drive an agent from your phone on the go and from a workstation at your desk, Caduceus provides **one unified experience, one memory ledger, and coherent multi-agent management**.

---

## Roadmap

- [x] **1. Core Apple Platforms Support**
  - [x] **macOS**: Liquid Glass 3-column workspace, PanelRail, ⌘K command overlay, shader effects, Apple Silicon optimizations
  - [x] **iOS**: Adaptive phone layout, bottom-nav (Sessions / Panels / Connect / Settings), swipeable sheets, Keychain security
- [x] **2. Multi-Agent Gateway Support**
  - [x] **Hermes Agent**: Complete control plane (`tui_gateway` JSON-RPC over WebSocket) & data plane integration
  - [x] **OpenClaw**: Gateway pairing, Ed25519 identity handshake, session subscriptions, live reasoning streams & tool calls
  - [x] Capability gating architecture with 26+ discrete capabilities
- [ ] **3. Extended Agent Harnesses**
  - [ ] Support for **Pi** and other emerging autonomous agent harnesses
  - [ ] Extensible adapter interface for custom REST/WebSocket agent backends
- [ ] **4. Cross-Platform Expansion**
  - [ ] **Windows**: Native desktop build, window chrome styling, MSIX packaging
  - [ ] **Android**: Phone & tablet adaptive layouts with Material elevation parity
- [ ] **5. Comprehensive Resource & Context Sharing**
  - [ ] Unified **Skill** synchronisation and cross-agent installation
  - [ ] Bi-directional **Memory** synchronization, auto-drift detection, and dispute arbitration
  - [ ] Universal **MCP (Model Context Protocol)** server sharing & tool proxying across all connected agents
- [ ] **6. Cross-Agent Inter-Scheduling & Autonomous Delegation (跨 Agent 调度)**
  - [ ] Fleet-wide task handoff and sub-agent delegation
  - [ ] Dynamic workflow orchestration across heterogeneous agents

---

## Performance & Benchmarks

Rendering 3,000+ token streaming responses with live tool calls and reasoning channels without UI hitching is Caduceus's core design benchmark. Detailed measurement methodologies and reproduction steps are in [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).

### 1. Incremental Markdown Parser vs. Naive Rebuilding

Naive implementations re-parse the entire accumulated Markdown buffer on every received token, creating quadratic $O(N^2)$ overhead. Caduceus implements an **`IncrementalSplitter`** with widget-identity block caching behind `RepaintBoundary`:

| Metric (3,491 tokens / 12,214 chars corpus) | Naive Streaming Parser (`rusty4444`) | Caduceus Incremental Parser | Advantage |
|---|---|---|---|
| **Total Characters Parsed** | 21,329,133 chars | **638,041 chars** | **33.4× less workload** |
| **Device Workload (60 tok/s profile)** | 15,100,091 chars | **357,507 chars** | **42.2× less workload** |
| **Scaling Exponent (Corpus 2×)** | **3.70× ($O(N^2)$ quadratic)** | **1.72× ($O(N)$ linear)** | **Scales cleanly to 10k+ tokens** |
| **Splitter Scan Duration** | 429 ms | **3 ms** | **143× faster** |
| **Real-Device Stream Duration** | 138.2 s | **92.2 s** | **1.5× faster end-to-end** |

### 2. Production Frame Work & Jank Rate (macOS Apple Silicon)

Measured in profile mode on the production widget stack (`ConsoleView` + `StreamingMarkdownView` under `caffeinate` with App Nap disabled):

| Scenario | Total Blocks | Jank Rate (>16.67 ms) | p50 Frame Work | p95 Frame Work | p99 Frame Work | Max Work Time |
|---|---:|---:|---:|---:|---:|---:|
| **Fresh Session (60 tok/s)** | 46 | **0.0%** | **0.49–0.52 ms** | 1.07–1.70 ms | 1.88–3.04 ms | < 9.7 ms |
| **Long Session (200 msgs)** | **9,646** | **0.0%** | **0.53–0.59 ms** | 1.42–1.61 ms | 2.29–3.34 ms | < 19.5 ms |
| **Unthrottled Stream (3,491 tok)** | 46 | **0.0%** | **0.77 ms** | 5.97 ms | — | **459 ms total** |

> **Key Takeaway**: In a 200-message long conversation (9,646 settled blocks, a **209× increase** in history size), median frame work only increases by **+0.05 ms** (from ~0.50 ms to ~0.55 ms). The cost of rendering a token is independent of prior conversation length.

### 3. Resource Footprint: Flutter Native vs. Electron Desktop

| Metric / Dimension | Official Hermes Desktop (Electron) | Caduceus (Flutter Native) | Architectural Difference |
|---|---|---|---|
| **Idle Memory (RSS)** | ~180 MB – 300+ MB | **~90 MB** | Skips bundled Chromium process & Node.js runtime |
| **App Bundle Size** | ~165 MB+ | **~25–45 MB** | Ahead-of-Time (AOT) compiled native binary |
| **UI Threading** | Single-threaded JS event loop | **Dedicated UI + Raster Threads** | Dart VM isolate handles I/O while Skia/Impeller renders |
| **Multi-Platform** | Desktop only (macOS/Win/Linux) | **Desktop + Mobile** | Unified codebase across 4 platforms |

### 4. Native C Acceleration Engine (`packages/caduceus_native`)

Computationally intensive operations (text cleaning, cryptography, JSON field slicing, SIMD vector math, and edit distance) are offloaded to an optimized C library through **Dart FFI**:

| Computational Task | Workload Profile | Pure Dart | Native C Engine (FFI) | Speedup / Advantage |
|---|---|---|---|---|
| **Markdown Fingerprint Cleaning** | 30,000 ops / multi-line prose | 19.55 µs/op | **1.44 µs/op** | 🚀 **13.5× faster** (Zero regex backtracking, single-pass pointer scan) |
| **Levenshtein String Edit Distance** | 5,000 ops / 110 chars diff | 48.14 µs/op | **17.80 µs/op** | 🚀 **2.7× faster** (Compact cache-friendly single row buffer) |
| **SHA-256 Crypto Hashing** | 50,000 ops / 70B handshake | 1.99 µs/op | **0.94 µs/op** | 🚀 **2.1× faster** (>1,060,000 ops/sec hardware bitwise operations) |
| **1536-dim Vector Cosine Similarity**| 20,000 ops / embedding | 2.59 µs/op | **2.16 µs/op** | 🚀 **1.2× faster** (ARM NEON SIMD parallel acceleration) |
| **JSON In-situ Field Extraction** | 30,000 ops / 300B frame | 2.05 µs/op | **1.66 µs/op** | 🚀 **1.2× faster** (Zero Dart heap `Map`/`List` GC allocations) |

---

## Key Architecture & Features

### 1. Multi-Agent Backend Seam
- **Hermes Agent Support**: Complete control plane (`tui_gateway` JSON-RPC over WebSocket) & data plane support.
- **OpenClaw Gateway Support**: Device pairing, Ed25519 identity handshake, session subscriptions, tool calls, and thinking replays.
- **Capability Gating**: Over 26 discrete capabilities gating bespoke UI panels dynamically depending on what the connected gateway supports.

### 2. Cross-Agent Bridges
- **Memory Bridge ([`docs/MEMORY_BRIDGE.md`](docs/MEMORY_BRIDGE.md))**: A unified ledger recording memories across agents with non-destructive block splicing and manual or guided rulings.
- **Shared Memory ([`docs/SHARED_MEMORY.md`](docs/SHARED_MEMORY.md))**: A curated canonical knowledge base with live drift detection.
- **Skills Bridge ([`docs/SKILLS_BRIDGE.md`](docs/SKILLS_BRIDGE.md))**: Cross-agent inventory of installed tools, plugins, and skills.
- **Fleet Graph ([`docs/AGENT_GRAPH.md`](docs/AGENT_GRAPH.md))**: Topology and relationship view showing which agents know what, divergence indicators, and memory pushing.

### 3. Liquid Glass Design System ([`docs/DESIGN.md`](docs/DESIGN.md))
- Content plane is solid (`Palette.slate`), and chrome floats above it as liquid glass with shader-driven highlights.
- **Desktop Layout**: 3-column workspace with collapsible 48px icon rail / sidebar, center console, and right `PanelRail`.
- **Mobile Layout**: Bottom navigation (**Sessions / Panels / Connect / Settings**), swipeable drawer, and modal sheets.
- **Full Accessibility**: Contrast verified to WCAG 2.1 4.5:1, dynamic text scaling (1.0×–2.0×), VoiceOver/TalkBack tooltips and status semantics.

---

## Project Structure

```
Caduceus/
├── docs/                        # Technical specifications & architecture docs
│   ├── ARCHITECTURE.md          # Multi-agent architecture & backend seam
│   ├── AGENT_GRAPH.md           # Fleet relationship layer & topology
│   ├── DESIGN.md                # Liquid Glass design system
│   ├── MEMORY_BRIDGE.md         # Cross-agent memory bridge
│   ├── SHARED_MEMORY.md         # Shared knowledge base & drift detection
│   ├── SKILLS_BRIDGE.md         # Cross-agent skill library
│   ├── BENCHMARKS.md            # Detailed performance measurements
│   └── PROTOCOL.md              # Hermes wire protocol reference
├── packages/
│   ├── caduceus_native/         # High-performance C core & SIMD FFI extensions (9 tests)
│   ├── agent_core/              # Pure domain abstractions, sessions, memory, graph (147 tests)
│   ├── hermes_protocol/         # Hermes JSON-RPC wire client (35 tests)
│   ├── openclaw_protocol/       # OpenClaw Ed25519 identity & gateway client (33 tests)
│   ├── streaming_markdown/      # Incremental markdown parser & block splitter (49 tests)
│   └── markdown/                # Core Markdown tokenizer
├── flutter_app/                 # Flutter application for macOS, iOS, Android, Windows (619 tests)
│   ├── lib/backends/            # Backend adapters (Hermes & OpenClaw)
│   ├── lib/design/              # Liquid Glass theme, shaders & widgets
│   └── lib/domain/              # Domain models & transcript engines
└── bench/                       # Reproducible benchmark harnesses
```

---

## Documentation

The repository is self-documenting. Recommended reading order:

| Document | What it covers |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Why there is a backend seam, what is core vs. capability, and how OpenClaw differs from Hermes. |
| [`docs/MEMORY_BRIDGE.md`](docs/MEMORY_BRIDGE.md) | Cross-agent memory ledger, non-destructive block splicing, and ruling controls. |
| [`docs/SHARED_MEMORY.md`](docs/SHARED_MEMORY.md) | Shared knowledge base and automatic drift detection across agents. |
| [`docs/SKILLS_BRIDGE.md`](docs/SKILLS_BRIDGE.md) | Unified skill library and discovery across agents. |
| [`docs/AGENT_GRAPH.md`](docs/AGENT_GRAPH.md) | Fleet relationship view, cross-agent connections, and topology. |
| [`docs/DESIGN.md`](docs/DESIGN.md) | Liquid Glass design system, color tokens, and layout non-negotiables. |
| [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md) | Deterministic performance measurements, parser workloads, and frame timings. |
| [`docs/PROTOCOL.md`](docs/PROTOCOL.md) | Hermes wire details, method catalog, and connection diagnostic rules. |

---

## Testing & Quality

All components are strictly unit, widget, and integration tested:

```bash
# Run tests across core packages
cd packages/caduceus_native && dart test
cd packages/agent_core && dart test
cd packages/openclaw_protocol && dart test
cd packages/hermes_protocol && dart test
cd packages/streaming_markdown && flutter test

# Run Flutter app tests & static analysis
cd flutter_app
flutter analyze
flutter test

# Run native vs pure Dart performance benchmarks
cd packages/caduceus_native
dart run benchmark/native_benchmark.dart
```

Current test suite status: **890+ tests passing, 0 analysis issues**.

---

## Acknowledgements

- **Nous Research** for [Hermes Agent](https://github.com/NousResearch/hermes-agent).
- **[rusty4444/hermes-android](https://github.com/rusty4444/hermes-android)** for early Flutter exploration.
- The authors of **hermex**, **hermes-mobile**, and **hermes-ios** for mobile UX inspirations.

---

## License
 
MIT License with Commons Clause 1.0. Free for personal and non-commercial use; commercial sale or charging for products deriving value substantially from the software requires a commercial license. See [LICENSE](LICENSE).
