# Profiling

How ToyStack measures itself. Everything is written to `browser.trace` (Chrome
Trace Event Format: `{"traceEvents": [...]}`) in the working directory.

There are two tools with different roles:

| Tool | File | Shape | For |
|---|---|---|---|
| `MeasureTime` | `Sources/Engine/MeasureTime.swift` | `B`/`E` spans + `C` | non-recursive phases (nesting and gaps are visible) |
| `Profiler` | `Sources/Engine/Profiler.swift` | accumulated metrics | recursive sub-phases (summed across calls) |

## When to use which

- **Spans** (`browser?.measure.start/stop`) for large, non-recursive phases, e.g.
  `tab.style`, `tab.layout`. They nest in the trace, so gaps in time are easy to
  spot.
- **Profiler** (`profiler.measure`/`count`) for work repeated inside recursion
  (e.g. `applyStyle`, `layout()` per node). Same-named nested spans would break
  the trace reader, whereas the Profiler accumulates them.

## Switch

`Profiler` is on by default; turn it off with the `--no-profile` argument
(`Sources/Engine/Profiler.swift:58-60`):

```bash
swift run -c release ToyStackHeadless \
  https://browser.engineering/visual-effects.html --screenshot /tmp/s.png
# no metrics, overhead is close to zero:
swift run -c release ToyStackHeadless <url> --no-profile
```

When off, `measure`/`count` are just `guard enabled else { return }` — no timer,
closure, or dictionary — and no `profile.*` events are emitted at all.

## Measurement windows

The Profiler holds one global `[String: ProfileMetric]`. Each window:
`profiler.reset()` at the start, `profiler.emitProfile(into:named:)` at the end.
Emission writes **one** `C` event named `profile.<phase>`.

| Event | Window | Contains |
|---|---|---|
| `profile.load` | `BrowserTab.swift:114-117` (around `parseHTML`) | `load.*`, `jsc.*` |
| `profile.style` | the `needsStyle` block | `style.*` |
| `profile.layout` | the `needsLayout` block | `layout.*`, `text.*` |
| `profile.paint` | the `needsPaint` block | `text.*` (from `DisplayCommand`) |

Because there is one global with a reset per window, measuring outside any window
is discarded when the next window resets.

## Units & format

- Stored as **nanoseconds**; emitted as **microseconds** with a `.us` suffix
  (1 ms = 1,000 µs). `us` is ASCII for `µs`.
- Every metric with a value > 0 produces `<name>.us`.
- Every metric produces `<name>.count` (number of calls/occurrences).
- `measure` adds a `count` of 1 per call; `count(name, by:)` adds `amount`.

## Naming convention

Hierarchical, dot-separated, shaped `<domain>.<part>`:

- `load.*` — `parseHTML` steps (once per load).
- `jsc.*` — `JSRuntime` initialization.
- `style.*` — the style cascade (`applyStyle`).
- `layout.*` — each layout type's own work.
- `text.*` — font/text measurement (used in layout and paint).

Rules of thumb:

- **Do not** put `measure` inside a per-item loop (e.g. per rule candidate, per
  word). If you need to count something in a loop, accumulate into a local
  variable and call `profiler.count(name, by: total)` **once** per node — like
  `style.matchesTrue`/`style.bodyWrites` in `DOMUtils.applyStyle`.
- One name, one meaning. Do not put the unit in the name (`.us`/`.ms` are added
  automatically).

## Current metrics

### `profile.load`

| Metric | Kind |
|---|---|
| `load.parse` | duration — `HTMLParser` |
| `load.checkboxes`, `load.title`, `load.resources`, `load.defaultCss` | duration |
| `load.jsInit` | duration — total `JSRuntime(tab:)` |
| `jsc.context`, `jsc.callbacks`, `jsc.runtimeHead`, `jsc.runtimeEval` | duration |

`jsc.*` are sub-parts **inside** `load.jsInit` (not additive to it).
`jsc.context` is ~40 ms only for the first `JSRuntime` in a process (JavaScriptCore
cold start); afterwards it is ~1.5 ms.

### `profile.style`

| Metric | Kind |
|---|---|
| `style.apply.reset`, `.flags`, `.scan`, `.test`, `.inline`, `.post`, `.push`, `.pop` | duration |
| `style.rules`, `style.nodes`, `style.elements` | count |
| `style.candidates`, `style.universalCandidates`, `style.descendantCandidates`, `style.descendantTrue`, `style.matchesTrue`, `style.bodyWrites` | count |

The sum of the eight phases ≈ `tab.style.apply`.

### `profile.layout`

| Metric | Kind |
|---|---|
| `layout.block.build`, `layout.line.place`, `layout.text` | duration — each type's own work |
| `text.measure` | duration — `CTLine` creation per cache miss |
| `text.font` | duration — `getFont` resolution |
| `text.words`, `text.fontNodes`, `text.fontRequests`, `text.measureCalls`, `text.measureMisses` | count |

`layout.block.build` **contains** part of `text.measure`/`text.font` (from
`addWord`), so do not simply add `layout.*` and `text.*` together. The sum of the
three `layout.*` phases ≈ `tab.layout`.

### `profile.paint`

| Metric | Kind |
|---|---|
| `text.measureCalls`, `text.measureMisses`, `text.measure` | count/duration |

Holds `font.measure` calls from `DisplayCommand.swift:112` while building the
display list. Compare with `profile.layout` to see the paint share.

## How to read `browser.trace`

The trace mixes event kinds:

- `{ "ph": "B"/"E", "name": "<span>" }` — `MeasureTime` spans.
- `{ "ph": "C", "name": "profile.<phase>", "args": { "<metric>.us": N, ... } }` —
  Profiler metrics.

Quick example in Python:

```python
import json
d = json.load(open("browser.trace"))
for e in d["traceEvents"]:
    if e.get("name", "").startswith("profile."):
        print(e["name"])
        for k in sorted(e["args"]):
            print(f"  {k} = {e['args'][k]}")
```

For a nested view, open `browser.trace` in a Chrome Trace viewer
(`chrome://tracing` or Perfetto) — spans appear as nested bars.

## Assumptions

- **Main thread.** `Profiler`, `MeasureTime`, and `fontCache` use
  `nonisolated(unsafe)` globals with **no lock** (`Profiler.swift:58`,
  `DOMUtils.swift:14`). All callers run on the main thread. If they are ever used
  from the raster worker, both need a lock.
- **Synchronous window.** A reset→measure→emit window must not be interrupted by
  an `await`. The `parseHTML` pattern is safe because it is synchronous; do not
  add an `await` in the middle of a window.

## Adding / removing measure points

- Use `profiler.measure("domain.part") { ... }` or `profiler.count(...)`.
- Pick names per the convention above.
- Points that turn out to be ~0 can be removed to keep the trace lean; metrics
  with long-term value (e.g. `text.fontNodes`, `style.candidates`) should stay.
