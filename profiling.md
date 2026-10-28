# Profiling

How ToyStack measures itself. The output is a Chrome Trace Event Format file
(`{"traceEvents": [...]}`, events in microseconds) written while the browser
runs.

Two writers:

| Writer | File | Shape | Use for |
|---|---|---|---|
| `MeasureTime` | `Sources/Engine/Diagnostic/MeasureTime.swift` | `B`/`E` spans, `X` intervals, `C` counters | phases, frames, threads, async boundaries |
| `Profiler` | `Sources/Engine/Diagnostic/Profiler.swift` | one accumulated `profile.<phase>` counter | recursive work (per node, per rule, per word) |

`MeasureTime` is locked and is called from the main thread, the presenter, the
compositor, and raster workers. `Profiler` is a `nonisolated(unsafe)` global
with no lock; it is only called from the main thread.

## Deterministic runs

`ToyStackHeadless` drives the engine from an animation clock instead of a
`Timer`. Use it for anything you intend to compare:

```bash
swift build -c release
.build/release/ToyStackHeadless <url> \
  --trace /tmp/run.trace \
  --frame-limit 600 \
  --screenshot /tmp/run.png
```

Flags:

| Flag | Meaning |
|---|---|
| `--trace <path>` | write here instead of `./browser.trace` |
| `--screenshot <path>` | capture when the run ends |
| `--frame-limit <n>` | stop after `n` ticks on the 60 Hz clock |
| `--run-for <seconds>` | `seconds × 60` ticks; `--frame-limit` wins if both are given |
| `--screenshot-at <t> <path>` | capture after `t` seconds of animation time |
| `--scroll-at <t>:<x>:<y>:<dy>` | scroll at `t` seconds; `x`/`y` are viewport CSS pixels, `dy` is CSS pixels and negative scrolls down; repeatable |
| `--force-full-layout` | recreate the layout tree on every layout pass; the differential oracle |
| `--no-incremental-layout` | same switch, pre-0b spelling |
| `--no-profile` | keep spans and counters, drop `profile.*` |

One tick is one `Browser.advanceFrame()` call; between ticks the runner waits
for `Browser.isRenderIdle`. Time is animation time, not wall time:

- CSS durations are frame counts (`secondsPerFrame = 1/60`), so `--run-for 10`
  and `--frame-limit 600` produce the same trace.
- `setTimeout` and `asyncAfter` use wall time and do **not** advance with ticks.
- `--screenshot-at 1.0` and a run ending at `--frame-limit 60` produce identical
  pixels.
- A scroll or capture at tick N runs after N frames have completed; a scroll at
  tick N therefore affects frame N+1.

`--force-full-layout` is not only a debug switch. Run the same page twice, once
incremental and once with the flag, and require byte-identical screenshots: an
incremental layout that diverges from a full rebuild is an under-invalidated
field. `Tests/ToyStackTests/LayoutOracle.swift` does the same comparison over
geometry and paint commands, so a failing trace can be reproduced as a unit
test without a screenshot.

```bash
.build/release/ToyStackHeadless "file://$PWD/www/ch16/granular-style.html" \
  --trace /tmp/inc.trace --frame-limit 120 --screenshot /tmp/inc.png
.build/release/ToyStackHeadless "file://$PWD/www/ch16/granular-style.html" \
  --trace /tmp/full.trace --frame-limit 120 --force-full-layout \
  --screenshot /tmp/full.png
cmp /tmp/inc.png /tmp/full.png
```

`scripts/run-scenarios.sh` runs the frozen A–D set three times by default
(`REPEATS=1` for one), into `benchmark/<timestamp>/run-<n>/`:

| Scenario | Page | Input |
|---|---|---|
| A | `www/ch13/exercise-13-5-1.html` | width animation, 600 ticks |
| B | `www/ch13/exercise-13-5-2.html` | opacity animation, 600 ticks |
| C | `www/bench/large.html` | 360 scroll events over 300 ticks |
| D | `www/bench/large-animated.html` | no input; self-animating width, 600 ticks |

`benchmark/baseline/` holds the committed A–D screenshots. Compare a run
against it; a mismatch names the scenario and prints both hashes:

```bash
scripts/compare-scenarios.sh benchmark/baseline /tmp/bench/run-1
```

Regenerate the baseline only for an intentional rendering change:

```bash
REPEATS=1 scripts/run-scenarios.sh /tmp/bench
cp /tmp/bench/run-1/*.png benchmark/baseline/
```

Commit the new images with that change.

Counts and pixels are reproducible. Timings are not: a single large-page run can
vary by 50%. Compare medians of at least three runs, and never compare a run
made just after a build with one made on an idle machine.

`ToyStackHeadless` does not create `ContentPresenter`, so it emits no `view.*`
or presenter `present` counters. Those require a GUI run.

## Trace file

`MeasureTime.init` writes the metadata array and the closing `]}` immediately;
every later event is inserted before those last two bytes. The file is valid
JSON between writes. `Browser.stopAnimationTimer()` calls `MeasureTime.close()`,
which emits an `E` for any span still open (with `"clipped": 1`) and closes the
file.

`ts` is microseconds since the Unix epoch (wall-clock aligned). `dur` and span
durations are microseconds. The schema metadata says so explicitly:

```json
{"name": "trace.schema", "ph": "M", "cat": "__metadata",
 "args": {"version": 1, "durationUnit": "us", "counterUnit": "count", "frameKey": "frame"}}
```

`process_name` is always `Browser`. `thread_name` is emitted lazily, once per
`tid`, the first time that thread writes an event.

## Event kinds

| `ph` | Name in trace | Shape | Meaning |
|---|---|---|---|
| `M` | `process_name`, `trace.schema`, `thread_name` | metadata | process, schema, thread label |
| `B` | span start | `cat`, `tid`, `args.frame` | opens a span on one thread |
| `E` | span end | same `cat`, `tid`, `args.frame` | closes the most recent `B` on that `tid` |
| `X` | complete span | `ts`, `dur`, `args` | one event with duration; used when the interval crosses an asynchronous boundary |
| `C` | counter | `name`, `args` (all integers) | one sample at the point of emission; usually per frame, but `pool` can appear more than once per frame |
| `i` | `trace.warning` | `s: "t"`, `args.kind` | pairing problem |

`B`/`E` are a stack per thread. Every `B`, `E`, `X`, and `C` event carries the
frame id in `args.frame`; the metadata names it `frame`, so a reader should not
guess.

`X` is used for `composite_raster_and_draw` because the interval starts on the
main thread and ends in the compositor's main-thread completion. Its `dur`
therefore includes queue wait and the hop back to main; see
[Known distortions](#known-distortions).

`trace.warning` kinds:

- `unmatchedStop` — an `E` with no matching `B` on that thread.
- `nameMismatch` — `stop(name)` did not match the top `B`.

A healthy trace has zero warnings and zero clipped ends.

## Categories

`cat` is never empty or `_`:

| Category | Assigned to |
|---|---|
| `load` | `profile.load`, `BrowserTab.load*`, `load.*` |
| `style` | `profile.style`, `BrowserTab.style*`, `style.*` |
| `layout` | `profile.layout`, `BrowserTab.layout`, `layout.*` |
| `paint` | `profile.paint`, `BrowserTab.paint`, `paint.*` |
| `raster` | `raster.*`, `tiles`, `pool` |
| `present` | `view`, `view.*`, `present.main`, `present` |
| `frame` | `composite_raster_and_draw`, `BrowserTab.anim*`, `BrowserTab.raf` |
| `input` | `BrowserTab.scroll*` |
| `engine` | everything else, including accessibility timers |

Classification is prefix-based in `MeasureTime.category(for:)`, so a new name
must follow an existing prefix or be given an explicit category at the call
site. `BrowserTab.rebuildScrollTargets` currently falls through to `engine`;
treat it as layout work when reading a trace.

## Threads and streams

| `thread_name` | How it is made | Notes |
|---|---|---|
| `main` | `Browser.init` → `noteThread` | real `pthread_self` id |
| `browser.present` | `ContentPresenter.drain` → `noteStream` | GUI only; synthetic stable tid |
| `browser.compositor` | `RasterScheduler.drain/finish` → `noteStream` | synthetic stable tid |
| `browser.raster.workers` | each worker → `noteThread` | one tid per actual thread, all share the name |
| `worker` | fallback for an unnamed non-main thread | |

`noteStream` assigns a synthetic tid so asynchronous work stays on one trace
lane. `noteThread` labels a real thread. The number of `browser.raster.workers`
tids can exceed the pool size because OS threads are recreated; use the `pool`
counter's `workers` for the intended concurrency.

## Reading rules

1. Pair `B`/`E` per `tid`. Do not pair by name only; the same name can be open on
   several worker threads at once.
2. Load spans are wall-clock envelopes. `BrowserTab.load`,
   `BrowserTab.load.page`, `BrowserTab.load.styles`,
   `BrowserTab.load.scripts`, and `BrowserTab.load.images` contain `await`
   (`Sources/Engine/Core/Frame.swift:124`). Other main-thread work can run inside
   them, so their duration is not exclusive CPU and their nesting can mislead.
   Synchronous spans (`BrowserTab.style`, `layout`, `paint`, `raster.plan`) do
   not have this problem.
3. Use `profile.*` windows for recursive work. They are emitted once per pass,
   with the frame id of the pass.
4. A `profile.layout`/`profile.paint`/`profile.style` event with **no**
   `composite_raster_and_draw` for the same frame means the frame produced work
   but was replaced before rasterization. That is the coalescing signal in a
   headless trace. In a GUI trace, `present` with `coalesced > 0` is the same
   signal at the presenter (older notes call it `present.coalesced`).
5. A frame with `BrowserTab.layout` but no `BrowserTab.style` is an incremental
   layout driven by dirty flags or animation, not a style pass. A clean pass can emit
   `BrowserTab.layout` and no `layout.*` counters at all; it returned at the root gate.

## Measurement windows

The Profiler holds one global `[String: ProfileMetric]`. Each window calls
`profiler.reset()` first and `profiler.emitProfile(into:named:)` last. Anything
measured outside a window is discarded at the next reset.

| Event | Window | Contains |
|---|---|---|
| `profile.load` | `Frame.load`, around `parseHTML` (`Frame.swift:150-152`) | `load.*`, `jsc.*` |
| `profile.style` | `Frame.render`, `needsStyle` block (`Frame.swift:697-698`) | `style.*` |
| `profile.layout` | `Frame.render`, `needsLayout` block (`Frame.swift:809-810`) | `layout.*`, `text.*`, `scrollTargets.reused`, `scrollTargets.rebuilt` |
| `profile.paint` | `Frame.paint` (`Frame.swift:864-865`) | `paint.*`, canvas `text.font*` |

A window must not contain an `await`; the reset→emit pair would then include
unrelated work. The `parseHTML` window is synchronous. `BrowserTab.load` itself
is not a profiler window because it awaits.

Metric storage is nanoseconds; emission writes:

- `<name>.us` for every metric whose value is > 0;
- `<name>.count` for every metric that has calls/occurrences.

## Vocabulary

### `profile.load` — durations

| Metric | Work |
|---|---|
| `load.parse` | `HTMLParser` |
| `load.checkboxes` | checkbox state initialization |
| `load.title` | title extraction |
| `load.resources` | resource URL collection |
| `load.defaultCss` | default stylesheet parse |
| `load.jsInit` | whole `JSRuntime` construction |
| `jsc.runtime`, `jsc.context`, `jsc.callbacks`, `jsc.runtimeHead`, `jsc.runtimeEval` | sub-parts inside `load.jsInit` |

`jsc.context` is ~40 ms only for the first runtime in a process; later runtimes
pay ~1.5 ms. The `jsc.*` values are inside `load.jsInit`, not additional to it.

### `profile.style` — durations and counts

| Metric | Kind | Meaning |
|---|---|---|
| `style.apply.reset`, `.flags`, `.test`, `.inline`, `.post`, `.push`, `.pop` | duration | phases of `applyStyle` |
| `style.nodes` | count | nodes in the pass |
| `style.elements` | count | elements (vs text nodes) |
| `style.rules` | count | sorted rules |
| `style.candidates` | count | rules that passed the selector pre-filter |
| `style.universalCandidates` | count | universal-rule candidates |
| `style.descendantCandidates`, `style.descendantTrue` | count | descendant matching work |
| `style.matchesTrue` | count | selectors that matched |
| `style.bodyWrites` | count | declarations applied |
| `style.applied` | count | nodes whose style was applied |
| `style.scope.direct`, `style.scope.rules`, `style.flipped.queries` | count | reusable-style scope |

The seven `style.apply.*` phases are the measured subset; the enclosing
`BrowserTab.style` span also contains rules, snapshot, scope, keyframes, and
invalidation.

### `profile.layout` — durations and counts

| Metric | Kind | Meaning |
|---|---|---|
| `layout.visit` | duration | one `BlockLayout.layout` body; the skip gate is outside |
| `layout.visited` | count | `BlockLayout.layout` bodies entered |
| `layout.skipped` | count | `BlockLayout` visits returned by the `layoutNeeded()` gate |
| `layout.height` | duration | height accumulation |
| `layout.mode` | duration | `layoutMode()` |
| `layout.inline.refresh`, `layout.inline.place` | duration | inline item rebuild and placement |
| `layout.line.place` | duration | line layout |
| `layout.text` | duration | text layout |
| `layout.rebuilt` | count | `BlockLayout` bodies that ran; equals `layout.visited` |
| `layout.children.rebuilt` | count | block-mode child lists rebuilt (inline reflow is not counted) |
| `layout.dirtyDescendants` | count | gate checks that returned because a descendant field was dirty |
| `layout.field.set` | count | layout field writes that changed the value |
| `layout.field.mark` | count | layout field transitions from clean to dirty |
| `scrollTargets.rebuilt` | count | layout pass that rescanned the tree for scrollable blocks and iframes |
| `scrollTargets.reused` | count | layout pass that reused the target list and only refreshed rects |
| `layout.mode.block`, `layout.mode.inline` | count | layout modes taken |
| `layout.lines.total` | count | lines placed |
| `text.measureCalls`, `text.measureMisses` | count | font width calls and cache misses |
| `text.measure` | duration | `CTLine` creation per miss |
| `text.fontRequests`, `text.font` | count/duration | font resolution |
| `text.words` | count | words emitted by inline item construction |

Rules:

- **Use `layout.rebuilt` for "boxes laid out".** `layout.visited` counts entries;
  `layout.skipped` counts block gate returns. `visited` and `rebuilt` stay equal:
  both count a body that ran, while a gate return increments only `skipped`. A fully
  clean pass returns in `DocumentLayout` and emits no block counters at all; assert
  `layout.visited` is absent or `0`, not `layout.skipped == 1`.
- `layout.dirtyDescendants` is the coarse path: a block entered because an ancestor
  flag was set, not because its own fields were dirty. It costs one gate per clean
  branch but does not rebuild anything.
- `layout.field.set` and `layout.field.mark` only count layout fields (style fields
  have no DOM node and are excluded). They are reset with the layout window, so a
  style-driven mark is not included in the next layout's count.
- `layout.children.rebuilt` only covers block-mode child lists. An inline block
  rebuilds its lines in `placeInlineItems` without bumping it; use
  `layout.inline.place` and `layout.lines.total` to see inline reflow.
- The `layout.*` durations nest and overlap; do not add them. `layout.visit`
  contains `layout.height` and the line/text work.
- `text.measure` is `CTLine` creation per cache miss; `text.font` is font
  resolution, called before the word is measured. Both sit inside
  `layout.visit`, so do not add `layout.*` and `text.*` as independent buckets.

### `profile.paint` — durations and counts

| Metric | Kind | Meaning |
|---|---|---|
| `paint.nodes` | count | layout objects visited by `paintTree` |
| `paint.own.items` | count | display items produced by the node itself |
| `paint.cache.hit.blocks`, `paint.cache.store.blocks` | count | block cache hits and stores |
| `paint.cache.hit.lines`, `paint.cache.store.lines` | count | line cache hits and stores |
| `paint.scroll` | count | scroll containers painted |
| `paint.range.copy` | duration | `Array(displayList[childStart...])` allocation in `PaintTree` |
| `paint.effect.check`, `paint.effect.wrap` | duration | visual-effect detection and wrapping |

Layout text does no font work during paint: `DrawText` carries the font resolved
in layout. Canvas painting is the exception and can emit `text.font*` while
resolving a canvas font.

### Spans outside `profile.*`

| Span | Where | Use |
|---|---|---|
| `BrowserTab.animFrame`, `.raf`, `.animScan` | main frame | animation entry and scan |
| `BrowserTab.style*` | main | style pass and its sub-parts |
| `BrowserTab.layout`, `.rebuildScrollTargets` | main | layout pass |
| `BrowserTab.paint` | main | display-list build |
| `BrowserTab.scrollAt`, `.scrollBy` | main | input dispatch |
| `BrowserTab.load*` | main, awaits | load envelope |
| `raster.queueWait` | `X` | enqueue → `raster.plan` start |
| `raster.plan`, `raster.composite`, `raster.effect` | compositor | plan work |
| `raster.composite.copy`, `.flatten`, `.layers` | compositor | display-list copy + parent links, flatten + filter, layer merge |
| `raster.plan.tiles`, `raster.install.tiles` | compositor | tile bookkeeping |
| `raster.install`, `raster.bitmap` | compositor | tile install and bitmap composition |
| `raster.installWait` | `X` | `raster.install` end → main-thread completion start |
| `raster.strip` | worker | one span per strip; runs on a worker thread |
| `present.main` | main | presented-frame dispatch |
| `view.apply`, `view.commit`, `view.updateSublayers` | presenter (GUI) | Core Animation work |
| `composite_raster_and_draw` | `X` | enqueue → main-thread install completion |

### Counters outside `profile.*`

Every `C` event is one sample for one frame.

`layout.animation.fallback` (`nodes`): an animated layout property dirtied no
layout field, so the animation loop marked the nearest block as a fallback.
Non-zero is a missing dependency edge and traps in debug builds.

`tiles`: one sample per composite, reset by `TileStore.beginComposite`.

| Arg | Unit | Meaning |
|---|---|---|
| `scroll` | CSS px | scroll offset at plan time (the only non-count arg) |
| `hits` | count | tile found and reused |
| `misses` | count | all misses, equal to the three reasons below |
| `missNew` | count | no slot for this `(layer, index, scale)` |
| `missStale` | count | slot exists, content hash changed |
| `missEvicted` | count | slot exists, same content, image evicted by budget |
| `entries` | count | tiles currently retained |
| `pixels` | pixels | retained pixel budget in use |
| `layers` | count | layers in the plan |
| `flat` | count | layers using the flat effect strategy |

`pool` (`workers`, `strips`): `workers` is
`min(activeProcessorCount, 4)` (`RasterWorkerPool.defaultWorkerCount`), the
intended concurrency, not the number of OS threads; `strips` is the batch size.
The number of worker tids is not the worker count.

`present` (`coalesced`): GUI only. Count of pending frames replaced while the
presenter was busy. A headless trace has no `present` counter; use rule 4 in
[Reading rules](#reading-rules).

`view` (`placements`, `added`, `removed`, `kept`, `hidden`, `unhidden`,
`purged`, `pool`, `sublayers`): GUI only, layer placement per presented frame.

| Arg | Meaning |
|---|---|
| `placements` | placements in this frame |
| `added` | new layer keys created |
| `removed` | keys hidden this frame |
| `kept` | keys present before and after |
| `hidden` | total hidden slots after this frame |
| `unhidden` | hidden keys returned this frame |
| `purged` | slots destroyed after the grace period |
| `pool` | slots retained (visible + hidden) |
| `sublayers` | `contentLayer.sublayers.count` |

`unhidden` is a policy number, not a health check: the presenter keeps removed
layers for 10 frames (`ContentPresenter.graceFrames`), while the tile set
oscillates over 120–240 frames, so a removed key is normally purged before it
returns.

`view.usesSublayersFlips` (`flip`, `sublayers`): GUI only. `flip` is 1 when the
strategy changed on this frame; `sublayers` is the current strategy.

## Known distortions

- **`raster.composite` splits into `copy`, `flatten`, and `layers`.** The sub-spans nest inside the total; their sum is approximately the total, and the remainder is sampling between spans.
- **`composite_raster_and_draw` is a total, not CPU work.** It starts at enqueue and ends in the main-thread completion. Split it with `raster.queueWait`, `raster.plan`, worker raster time, `raster.install`, and `raster.installWait`; the remainder is the main-thread completion. The parts are sampled between spans, so the sum is approximate. `raster.strip` covers worker work but runs concurrently, so do not sum those spans either.
- **`layout.visit` is a duration, not a count.** Box counts are `layout.visited`, `layout.skipped`, and `layout.rebuilt`.
- **Headless has no presenter.** A/B/C/D cannot answer layer churn, `view.commit`,
  or presenter coalescing.
- **D is a load trace.** `www/bench/large.html` has no animation, so a 600-tick
  run produces two browser frames and one layout. It measures first-layout
  cost, not steady state.
- **Single-run timings are noisy.** Counts and pixels repeat; multi-millisecond
  passes can vary by tens of percent between runs.

## Assumptions

- **Locks.** `MeasureTime` has an `NSLock` and is called from main, compositor,
  and workers. `Profiler` and `fontCache` are unlocked `nonisolated(unsafe)`
  globals (`Profiler.swift:58`, `BrowserFont.swift:47`) and must stay on the
  main thread.
- **Tracing is always on.** There is no compile-time switch. `--no-profile` only
  disables the `Profiler`; spans and counters still run.
- **Close the trace.** Call `Browser.stopAnimationTimer()` before the process
  exits. Without it, open spans stay unpaired (the file is still valid JSON).
- **One trace path per process.** `MeasureTime` truncates the file at init.

## Adding / removing measure points

- Spans (`measure.start/stop`, `measure.span`) for large, non-recursive phases.
- `measure.interval` for an interval that crosses an async boundary; it emits
  `X` with the frame id and extra integer args.
- `measure.counter` for per-frame integers. All args must be `Int`; put units in
  the documentation, not the name.
- `profiler.measure` / `profiler.count` inside recursion only.
- Do not `measure` inside a per-item loop. Accumulate and call `count(name, by:)`
  once, as `style.matchesTrue` does.
- One name, one meaning. Do not overload args either: `tiles.scroll` is pixels,
  every other tile arg is a count.
- Update this file whenever a span or counter is added, renamed, or removed.
