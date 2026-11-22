# ToyStack

A toy browser engine with Swift. Motivated from [Browser Engineering book](https://browser.engineering).

This project comes from curiosity to make a browser engine with Swift programming language. Mostly, we use browsers that engine build with C/C++ programming language in real-world use case. In 2012 (according to Wikipedia), there's new browser engine called Servo is built in Rust programming language.

There are three reasons why I want to make the toy browser engine with Swift programming language:

1. Curiousity and learning how hard it is make the browser engine.

2. Getting familiar with Swift programming language and it's paradigm. Then, use it to build browser engine.

3. SwiftUI

To show the result of the browser engine that build with Swift, we need to wrap it into the desktop app. Luckily, I’m using Apple product like MacBook (macOS) and it has access to the SwiftUI. I don’t need to waste my time to seeking the GUI desktop engine. :)

## What It Covers

The ToyStack follows the Browser Engineering chapters. I have made the project called [Brownie](https://github.com/kresnasatya/brownie). It's a browser engine with Python (the code provided by Browser Engineering book - I just follow and make some fixes). Thanks to the Artificial Intelligence - LLM, I can port the Python code into Swift much easier step by step.

The process divided into 4 chapters:

- [x] ch01-10 - It covers Chapter 1 (Downloading Web Pages) to Chapter 10 (Keeping Data Private)

- [x] ch11-14 - It covers Chapter 11 (Adding Visual Effects) to Chapter 14 (Making Content Accessible)

- [x] ch15 - It covers Chapter 15 (Supporting Embedded Content)

- [x] ch16 - It covers Chapter 16 (Reusing Previous Computation)

## Domain Architecture

- **Core**: App facing controllers + frame bookkeeping + shared primitives.
- **Parsing**: Turns text into trees.
- **Style**: `ComputedStyle` parsing and cascade, media features, inline style, text direction, whitespace, forced colors.
- **Style/Selectors**: It holds the matching machinery (tag/class/id/descendant/has/RuleIndex).
- **Layouts**: Geometry/layout: block, inline, line, text, input, button layout + arena storage (`LayoutTree`, `LayoutRef`) + `LayoutMetrics`.
- **Display**: `DisplayOp` construction, typed colors, effect scopes, PaintTree, scrollbar, focus ring.
- **Raster**: Turning display list into pixels: compositing layers, tiles/tile store, raster scheduler + worker pool, budgets, invalidation.
- **Presentation**: The public hand-off of a finished frame to the UI.
- **Animation**: `AnimatedValue` interpolation, keyframe/numeric/color/transform animations, style transitions, frame timing.
- **Accessibility**: A11y tree, highlight bounds, and the speech thread.
- **Networking**: Fetching from network.
- **Platform**: OS/renderer abstraction: `Renderer` protocol + `CGRenderer` Core Graphics implementation, `BrowserFont`, `LayerOptions`, `JSRuntime`.
- **Scheduling**: Work execution.
- **Diagnostic**: Instrumentation: `MeasureTime` (trace spans), `Profiler`
- **Resources** Bundle assets

Rough flow: **Networking** -> **Parsing** -> **Style** -> **Layouts** -> **Display** -> **Raster** -> **Presentation**, with **Core** orchestrating, **Animation/Accessibility** feeding in, and **Platform/Scheduling/Diagnostic** supporting.

## How to Run?

To run this project, build with command `swift build` then use command `swift run ToyStack` to launch ToyStack browser.

### ToyStackHeadless

`ToyStackHeadless` runs the same engine without a window. It loads a page, plays it on a fixed 60 frames-per-second clock, then writes a trace and (optionally) a screenshot. Use it to check how a page looks, or to compare runs, because every run of the same command gives the same result.

```bash
swift run ToyStackHeadless <url> [options]
```

The `<url>` can be a web page or a local file. For files in `www`, use an absolute `file://` URL:

```bash
swift run ToyStackHeadless "file://$PWD/www/ch11/index.html" --screenshot /tmp/ch11.png
```

Without `--frame-limit` or `--run-for`, it runs every timed (`--*-at`) event first, then stops once the page has not changed for 30 frames (half a second). If the page never settles, it stops after 10 seconds of page time, or just after the last timed event if that comes later. Without `--screenshot` or `--screenshot-at`, it only writes the trace (default `./browser.trace`).

Common options:

| Option | What it does |
|---|---|
| `--screenshot <path>` | Save a PNG when the run ends |
| `--screenshot-at <t> <path>` | Save a PNG after `t` seconds of page time |
| `--trace <path>` | Write the trace here instead of `./browser.trace` |
| `--frame-limit <n>` | Stop after `n` frames (60 frames = 1 second) |
| `--run-for <seconds>` | Stop after this many seconds of page time |
| `--width <px>` / `--height <px>` | Window size (default 800 × 600) |
| `--scale <n>` | Screen pixel density (default 2) |
| `--zoom <n>` | Page zoom (default 1) |
| `--scroll-at <t>:<x>:<y>:<dy>` | Scroll at `t` seconds; negative `dy` scrolls down; repeatable |
| `--click-at <t>:<x>:<y>` | Click at `t` seconds; repeatable |
| `--type-at <t>:<text>` | Type `text` starting at `t` seconds, one key per frame; repeatable |
| `--resize-at <t>:<w>:<h>` | Resize the window at `t` seconds; repeatable |
| `--force-full-layout` | Rebuild the whole layout on every pass, to compare with the normal (incremental) layout |
| `--no-profile` | Keep the trace but leave out profiler counters |

Example: scroll a page twice and take a screenshot after each scroll.

```bash
swift run ToyStackHeadless "file://$PWD/www/bench/large.html" \
  --scroll-at 0.5:400:300:-600 --screenshot-at 1.0 /tmp/scroll-1.png \
  --scroll-at 1.5:400:300:-600 --screenshot-at 2.0 /tmp/scroll-2.png
```

For timing numbers, build in release mode first (`swift build -c release`) and run `.build/release/ToyStackHeadless` directly. See [profiling.md](profiling.md) for how to read the trace.
