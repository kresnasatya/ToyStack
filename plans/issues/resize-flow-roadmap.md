# Resize Flow Roadmap

Reference for executing the resize-flow work. One step at a time; update the
status after every measured change.

## Current state

| Area | Cost | Evidence |
|---|---|---|
| Scroll input | p95 0.64 ms | `browser.trace`, 230 `BrowserTab.scrollAt` |
| Scroll paint | up to 12.8 ms | `browser.trace` |
| Scroll present commit | up to 14.9 ms | `browser.trace` |
| Resize layout | 30.6-191.9 ms | frames 74-100 |
| Resize breakpoint | 211 ms frame, 191.9 ms layout | frame 90 |
| Resize present commit | 17.8-42.3 ms | 50-120 layers, up to 7.9 MP |
| Initial load | 414 ms | frame 46 |

## What is already done

- Preview is driven by the frame clock, not by every resize event.
- Content revision and present sequence are separate.
- Preview is idempotent from the base view size and uses a transform, so text is
  not distorted while the pointer moves.
- Width-only reflow has a fast path; lines are reused; child layout and the
  reachability sweep are skipped when possible.
- One text fragment per font run, line-owned inline widths, fragment reuse pool,
  shared `TextRun`, and font-only run reuse.
- Cheaper item placement and per-node font resolution.
- Scroll repaint has a complete compositor generation; a paint-window change
  forces a composite.
- Keyboard scroll is time-based.

Attempted and reverted:

- Fragment model without a reuse pool: wins on dense lines, loses on pages with
  two or three words per line.
- Deferred scroll repaint before the generation contract: missing list text.
- Removing the line text layout node is still unproven.

## Blockers

1. Preview presentation still waits for `animationTick` on the main thread.
   A long layout blocks the next preview.
2. Layout rebuilds all 1773 blocks on width changes; there is no pending
   layout tree and no incremental layout across a drag.
3. A media-query font-size flip is a cliff: style 43-48 ms, layout 192 ms,
   `field.set` 75k.
4. A new composite binds 50-120 CALayers at once; `view.commit` reaches 42 ms.
5. The engine has no independent compositor loop. `ContentPresenter` is on a
   separate queue, but present is still triggered from the main thread.

## Execution order

### Step 1: presentation-first resize

Status: **applied** (2026-11-06).

- `Browser.resize` calls `resizePreview.presentPreview` immediately and
  dispatches the scaled frame, instead of waiting for `animationTick`.
- The animation tick still owns the reflow deadline; because the policy marks
  the size as presented, the tick does not enqueue it again.
- Fast frames still skip the preview and lay out on the next tick.

Verification: `swift test` 247 tests / 41 suites, `swift build` succeeds, six
`ResizePreviewPolicyTests` pass.

GUI trace after the change (`browser.trace`, 138 frames, 229 resize events):

| Measure | Result |
|---|---|
| Resize layouts | 11 passes, **76.4-157.5 ms** |
| Layout frames | 111, 113, 115, 117, 119, 121, 123, 125, 127 |
| Preview frames | 110, 112, 114, 116, 118, 120, 122, 124, 126 |
| Previews in frame 110 | **143 `view.apply`**, 18.5 ms of `view.commit` |
| Preview gap after a layout | **96-149 ms** |

The preview is now enqueued from the resize event, but it is still not continuous
during a layout: the main thread owns both layout and resize delivery. The
158 ms worst frame still produces a 149 ms gap before the next preview. Also,
a burst of resize events can enqueue 143 previews in one frame; those should be
coalesced to the latest size.

Conclusion: Step 1 is applied but **not sufficient for the perceived goal**.
Keep it, add preview coalescing, and proceed to Step 2.

Preview geometry follow-up: the old complete frame was clipped when the window
shrank because only `contentLayer.frame` changed. `PreviewFit` now computes a
uniform fit from the previous view size to the new viewport, and the presenter
applies that scale to the old layers. Tests cover wide-to-narrow, height-room,
and invalid previous-size cases.

Async layout stale-result guard: a background pass started at an old width could
finish after another resize and be installed as new content at the new window
size, showing clipped old-width layout. `LayoutJobKey` records the width and
zoom; `finishAsyncLayout` discards a result whose key is stale and starts a new
pass for the current viewport. Tests cover width/zoom invalidation.

Preview policy follow-up: when background layout is enabled, every resize now
previews the last complete frame instead of waiting for a slow-frame estimate.
`PreviewFit` also refuses to magnify the old frame when the viewport grows
(`scale <= 1`). Tests cover async preview scheduling and no-magnify geometry.

Latest GUI trace after the preview fixes (563 frames):

| Measure | Result |
|---|---|
| `view.commit` | p95 4.5 ms, max 47.3 ms |
| `view.updateSublayers` | p95 0.41 ms |
| Main `animFrame` | p95 18.2 ms |
| Scroll input | p95 0.64 ms |
| Main layout | absent; background layout active |

Some stale content during a drag is the preview contract: the last complete
frame stays until the new layout and raster generation are ready. The preview is
now fitted and never magnified.

Continuous async layout **applied**: while async layout is enabled, the frame
clock no longer waits for the 120 ms preview deadline. It presents the fitted
preview and lets the next animation frame start a background layout for the
latest width. One job stays in flight; stale-width results are discarded. Sync
layout still waits for the preview deadline. Tests cover both policies; async
vs sync headless screenshots remain identical after rapid resizes. GUI trace is
still required.

### Step 1b: coalesce preview presents

Status: **superseded by Step 1c** (2026-11-06).

A run-loop-turn task did not coalesce the events: AppKit delivered 281 resize
events as 281 dispatches, and frame 79 still applied 144 previews. The trace
shows the event handler and the task alternate, not batch.

### Step 1c: throttle previews to the display rate

Status: **applied** (2026-11-06).

- A resize event updates only `windowSize`.
- At most one preview is presented per `FRAME_BUDGET` (1/60 s).
- If the interval has elapsed, the latest size presents immediately; otherwise
  one delayed task presents the latest size when the interval ends.
- A frame-clock layout or a switch back to the fast path cancels the pending
  preview with a generation token, so a preview cannot overwrite a fresh frame.
- Expected trace change: at most one `view.apply` per 16.7 ms instead of 281
  dispatches for 281 events. Verify in the next GUI trace.

Measured on the next GUI trace (158 frames, 212 resize events):

| Measure | Result |
|---|---|
| Resize event spacing | about **17 ms** |
| `present.main` dispatches | 326 |
| `view.commit` preview | median 0.10 ms, p95 3.49 ms |
| Resize layout | **79.1-149.4 ms** |
| Preview gap during layout | one frame is blocked for the whole layout |

The earlier "143 previews in one frame" was a trace artifact: a frame ID can
span 0.5-2.4 s while no animation tick runs, so it contained many 17 ms events.
At 17 ms spacing the throttle correctly allows one preview per event. The
remaining gap is not preview coalescing; it is the main-thread layout itself.

### Step 2: incremental resize layout

Status: **partially applied** (2026-11-06).

Applied sub-step: after a font/zoom-only inline refresh, keep the old line plan
and reuse lines whose item range is unchanged. Reused lines now refresh their
owned widths and text metrics in place; previously the plan was discarded and
every line was rebuilt.

Benchmark, release, 1000 paragraphs, resize 1000 <-> 700 across a font breakpoint:

| Build | Layout during resize |
|---|---:|
| Before | 77.5 ms |
| After | **73.4 ms** |
| Full rebuild | 183.6 ms |

Screenshots are byte-identical to the full rebuild; 247 tests pass. The win is
5%; the resize target of 60 ms is not met. Remaining on the same frames:
`layout.visit` 55-64 ms, `inputs.build` 10-17 ms, `inline.refresh` 9-10 ms,
`inline.place.items` 16-22 ms, sweep 4-12 ms.

Next sub-step: skip block visits whose effective width and inline plan did not
change, and reduce `layout.visit.children`.

GUI trace after the change (334 frames, 4 loads, 73 scroll events):

- heavy-page resize frames 62-72: **91-113 ms**
- font-breakpoint frames 64, 68: **113.5 / 110.3 ms** (previous trace:
  136-149 ms)
- later font-breakpoint frames 324, 328: **106.9 / 110.1 ms**
- a simpler page after frame 73: resize layouts **5-15 ms**
- `layout.visit` 49-65 ms, `inline.place` 27-42 ms, `inputs.build` 14-24 ms,
  sweep 5-10 ms
- `view.commit` p95 9.0 ms, max 37.6 ms

The line-plan reuse is a real win on font-breakpoint frames, but it does not
move the heavy page below 90 ms. `layout.visit` is now the target for Step 2b.

Step 2b investigation: the heavy page still reports `layout.visited.count` and
`layout.rebuilt.count` = **1773** on every resize, and
`layout.visit.geometry.count` = **1773**. The widths are not staying unchanged
for a subset that could be skipped; a simple per-block width guard would not
remove the traversal. The next viable step is a vertical subtree offset (so a
moved block does not visit its descendants), or moving layout off the main
thread. Do not add a width guard without measuring `layout.width.changed`.

### Step 3: present budget

Status: **reverted** (2026-11-06).

Tile size 128 -> 256 reduced the layer count from 48 to 12 for a 1000 x 700
layer and kept screenshots identical, but the GUI trace got worse: `view.commit`
rose from p95 6.3 ms / max 44.6 ms to p95 9.9 ms / max 59.3 ms. The larger
tiles upload more device pixels (up to 12.6 MP from 10.5 MP) because edges are
rounded to 512-device-pixel tiles. The optimization was reverted and its
layer-count test removed; layer count was not the limiting metric.

Applied: `PresentUploadBudget` caps a present at 4,000,000 pixels. A new
generation is now built on hidden pending layers behind the still-visible old
generation; only a fully bound generation is unhidden and swapped in. A single
oversized tile still makes progress. Tests cover the budget boundary and the
oversized-first-tile rule; full suite: 253 tests / 44 suites.

GUI trace after staging (574 frames):

| Measure | Result |
|---|---|
| Resize `view.commit`, first batch | about **16 ms** |
| Resize `view.commit`, completion batch | **7-13 ms** |
| `contentsPixels` per present | capped at **3.99 MP** |
| Deferred tiles | 18-60, completed by the next present |
| Main `animFrame` | p95 **13.8 ms** |

The cap works: no resize present exceeds the 4 MP budget, and the old frame
stays visible until the swap. The target below 10 ms is not met yet; the first
4 MP batch costs about 16 ms.

Budget lowered to **2,000,000 pixels** (`PresentUploadBudget.generationPixels`)
after a test-first change. Tests: 254 / 44 suites.

GUI trace after the 2 MP change (537 frames):

| Measure | Result |
|---|---|
| Tiles per batch | 30 |
| `contentsPixels` per present | 1.97 MP |
| `view.commit` first batch | **11-14 ms**, p95 12.4 ms |
| `view.commit` completion batch | 3-14 ms |
| Main `animFrame` | p95 13.1 ms |
| Scroll input | p95 0.51 ms |

The 4 MP -> 2 MP change reduced the first batch from about 16 ms to 12 ms,
not below 10 ms. The commit scales with layer count as well as pixels: 30 tiles
still cost roughly 0.4 ms each. Next: try a 1.2 MP budget (about 18 tiles), or
move the tile binding off the present commit path.

### Step 4: long-term pipeline

- Pending/active layout tree.
- Layout work outside the main thread for safe subtrees.
- A compositor loop that can scroll and resize without the main thread.

Thread-safety prerequisite **applied** (2026-11-06): the global font cache and
profiler now use locks. Background layout is integrated behind
`Browser.usesAsyncLayout`; the GUI enables it. The geometry/integration tests
are opt-in with `TOYSTACK_BACKGROUND_LAYOUT_TEST=1` because they record into the
process-wide profiler while other suites assert profiler counts. Full default
suite: 251 tests / 43 suites. Opt-in suite: 2 background tests pass.

GUI async trace (519 frames, 4 loads, 256 scroll events, resize bursts):

| Measure | Result |
|---|---|
| Main `BrowserTab.layout` spans | none; layout is on the worker |
| `BrowserTab.animFrame` | median 0.68 ms, p95 18.6 ms, max 138.7 ms |
| Paint | median 3.2 ms, p95 7.0 ms |
| `view.commit` | median 0.10 ms, p95 6.3 ms, max **44.6 ms** |
| Resize present commits | many frames at 26-40 ms |
| Scroll input | median 0.24 ms, p95 0.70 ms |

The main thread no longer runs the resize reflow. The remaining wall is the
present commit on resize: binding the new tile generation still takes tens of
milliseconds. Next: Step 3, present budget.

### Step 4 follow-up: a stale async result restarts the pass

Status: **applied** (2026-11-06).

Releasing the pointer mid-drag left the final width unlaid out. A tick consumed
the resize's render request while a job was in flight; when that job finished
stale, `finishAsyncLayout` only requested an animation frame. The clock ticked
with `needsRender == false`, so no new pass started and the presenter kept
showing the fitted previous frame until the pointer moved and
`setNeedsHoverCheck` revived the tree.

`finishAsyncLayout` now calls `setNeedsLayout()` instead of
`requestAnimationFrame()`, so the discarded result schedules the render pass the
clock actually reads. Tests: `AsyncResizeRestartTests` (opt-in with the other
background suites) fails with `restarted == false` before the change and passes
after; full default suite 281 tests / 50 suites pass.

Verification: `TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test` — 3 tests in the
two background suites pass.

### Step 5: a resize never throws away a finished layout

Status: **applied** (2026-11-08).

Problem: every resize event cancelled the running background pass. Events
arrive every 16.7 ms and a heavy page needs 45–65 ms, so passes almost never
finished. GUI trace: 963 of 1013 passes discarded (95%), 0–2 new layouts per
drag, the old picture stayed on screen for up to 1.74 s
(`plans/issues/resize-smoothness-audit.md`).

Change:

- `LayoutCancellation` is removed. A pass started for an older viewport runs to
  the end; `finishAsyncLayout` installs it as an intermediate layout, counts
  `layout.async.superseded`, and schedules a pass for the current viewport.
- `LayoutJobKey` holds the job's size (width and height) and zoom, so a
  height-only resize during a pass is also laid out afterwards.
- The installed tree is never marked while a pass runs. Viewport changes set
  `Frame.viewportGeometryPending`; the next pass marks the document geometry
  on its own copy (on the worker, so the main thread copies no node storage).
- `BrowserTab.runAnimationFrame` paints a newly installed tree while the next
  pass runs, if that pass only moves the viewport (`Frame.layoutBlocksPaint`:
  inputs reused and no document change since). Any document change still holds
  paint back until the pass finishes.
- Removed with the discard path: style-change requeue
  (`StyleFields.requeueLayoutChanges`) and `LayoutTree.markDocumentWidthDirty`.

Tests (`AsyncResizeRestartTests`): the pass for 400 is installed after a resize
to 300 and is followed by a pass for 300; a pass back at its starting width
needs no follow-up; the tab paints the 400 layout while the 300 pass runs; a
document change during a pass still holds paint back. The first three failed
before the change. `LayoutJobKeyTests` covers the height boundary.

Smoke (throwaway harness, debug build, 1500 paragraphs, 90 resizes 16.7 ms
apart, tab tick driven):

| Build | New layouts painted during drag | Longest without a new paint |
|---|---:|---:|
| Before | 0 | 1772 ms (whole drag) |
| After | 41 | 186 ms |

In that debug harness each intermediate paint costs about 86 ms on the main
thread.

GUI trace after the change (`browser.trace`, 45 drags, 27.3 s of dragging,
1326 resize events):

| Measure | Before (2026-11-07) | After |
|---|---:|---:|
| Passes thrown away | 963 of 1013 | 0 |
| Passes installed as intermediate layouts | 0 | 425 of 506 |
| New layouts painted during drags | 0–2 per drag | 407 (14.9 per second) |
| Resize event → its layout painted | — | median 86 ms, p95 126 ms, max 195 ms |
| Longest stretch without a new paint, per drag | up to 1.74 s | median 94 ms, max 320 ms (includes pointer pauses) |
| Final width painted after release | 39–84 ms | median 29 ms, max 70 ms |
| Paint per intermediate layout (main) | — | median 7.7 ms, p95 9.1 ms |

Event → painted latency splits into: waiting for the running pass to finish
(median 24 ms), the pass itself (median 42.5 ms), and finish → paint (median
15.6 ms; the install waits for the next 60 Hz timer tick, then paints).
Remaining walls: layout cost (Step 2b), the timer-tick wait after an install,
and breakpoint style on the main thread (21–38 ms in drags).

Trace note: in this trace `layout.async.document` spans appear on the
`browser.present` and `browser.raster.workers` lanes. `MeasureTime.noteStream`
stored the stream id in `Thread.current.threadDictionary` and nothing cleared
it, and `noteThread` named pooled threads permanently, so later work on the same
OS thread was reported under the old lane. **Fixed (2026-11-08):** lanes are
now scoped (`beginStream` / `beginThreadLane` → `TraceLane.end()`), and
background layout has its own `browser.layout` lane (`MeasureTimeLaneTests`;
see `profiling.md`, Threads and streams).

GUI trace after the lane fix (43 drags, 27.1 s, 1360 resize events):

- Lanes are clean: all 520 `layout.async.document` spans are on
  `browser.layout`; none on `browser.present` or `browser.raster.workers`; no
  `trace.warning`; no two layout jobs overlap.
- Same performance as the previous trace (only labels changed): 15.3 new
  layouts painted per second, resize event → painted median 84 ms (p95
  132 ms), final width painted median 31 ms after release.
- The tab paints the installed tree in the same tick that starts the next job
  (job start − paint start: median −0.1 ms), as designed.
- Layout costs about 40 ms at every width (390–1440 px buckets: 39–43 ms
  median). See "Layout cost measured" below for the breakdown.
- The background pass emits no `profile.layout`. The profiler is locked but
  has one global window: the worker records into the main thread's paint
  window, so `profile.paint` carries partial `layout.*` counts and the GUI
  trace cannot break the 40 ms down. Use a headless sync run for the breakdown.
- Every intermediate layout re-rasters every tile (median 60 misses, 0 hits per
  composite); worker raster is 8.1 s of CPU over 27 s of dragging. It is off the
  critical path (`composite_raster_and_draw` p95 10 ms).
- Breakpoint style runs 18 times during drags at 13–35 ms on main; the
  present gap around it grows to 21–64 ms (median gap in drags 16 ms).

Verification: `swift test` (297 tests) and
`TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test --no-parallel` (297 tests). The
background suites need `--no-parallel`: whether a pass may paint depends on
reused inputs, which are keyed on the process-wide `StyleRevision.epoch`, and
parallel suites bump it.

### Layout cost measured (2026-11-08)

Release headless, `www/bench/large.html` (1000 paragraphs, 2025 blocks), one
resize per tick. The page has no media queries, so this is layout alone.

| Drag | Passes | Wall per pass | Lines re-broken |
|---|---:|---:|---|
| 1000 → 644 px, 4 px steps, sync | 89 | median 18.7 ms, max 21.6 ms | never |
| 450 → 302 px, 2 px steps, sync | 70 | median 19.5 ms | no |
| same, the 4 passes that re-break | 4 | median 45.0 ms, max 73.1 ms | 1000 paragraphs → 2000 lines |
| 1000 → 644 px, async worker | 90 | median 21.5 ms | never |

Pass without a line change (median, wide drag):

| Stage | ms | Calls |
|---|---:|---:|
| `layout.document` | 18.7 | 1 |
| `layout.visit` (all block bodies) | 15.2 | 2025 |
| — `layout.visit.geometry` | 5.8 | 2025 |
| — `layout.inline.plan` | 2.1 | 2023 |
| — `layout.mode` | 0.9 | 2025 |
| — `layout.blockStyle` | 0.3 | 2025 |
| — rest of the block body (no own span) | ~6.1 | |
| outside block bodies (traversal, gates) | ~3.5 | |

Every block is visited on every pass (`layout.visited` = `layout.rebuilt` =
2025; 2023 inline blocks only update line widths). The cost is about 9 µs per
block before any line changes, so this page cannot fit 16.7 ms by trimming line
work; the visit itself has to be skipped for blocks whose geometry only moves.

Pass that re-breaks lines (median of the 4): `layout.document` 44.2 ms,
`layout.visit` 30.1 ms, `layout.inline.place` 16.2 ms (1000 calls),
`layout.line.place` 5.3 ms (2000), `inline.place.lineChildren` 3.7 ms,
`line.children.previous` 2.8 ms, `inline.children.deps` 1.6 ms, sweep 0.7 ms;
`layout.field.mark` 18,050 vs 4,050 without re-break.

The async worker costs about 2.8 ms (15%) more than the sync pass on the same
drag. [INFERENCE] The difference is the worker's copy of the node storage, which
the main thread still shares when the worker writes.

The GUI page from the last trace is not identified in the trace. It has about
1723 paint nodes and takes about 40 ms at every width; that matches the bench's
re-break passes (45 ms), not its no-change passes (19 ms). [INFERENCE] On that
page most passes re-break lines.

Option A from `plans/issues/layout-visit-cost.md` applied (2026-11-08): same
drag, `BrowserTab.layout` without profiler 15.8 → **5.8 ms**; re-break passes
43–57 → 23–31 ms; background `layout.async.document` 21.1 → **12.3 ms**.
Screenshots byte-identical. Details and steps are in that file.
Option A step 4 (line/text/embed/document payloads) applied the same day; on a
300-paragraph page where every pass re-breaks lines, layout went 16.0 → 7.95 ms
against `HEAD`. Remaining hot spots: `inlineTextLinePlan` (per-word copies),
`placeInlineItems`, `layoutLineBoxes`.

GUI trace after step 4 (same page, ~1726 paint nodes; 48 drags, 30.8 s, 1262
resize events, shorter drags: median 0.35 s): background layout in drags median
24.0 ms (p95 40.4) vs 23.1 ms after step 3; resize event → painted median 57 ms
(p95 91) vs 57 (88); final width after release median 23 ms. Step 4 is not
visible on this page, as in the headless `large.html` run. Breakpoint style ran
18 times during drags at 14–45 ms on main, with present gaps of 23–61 ms
around it.

GUI trace after step 1, Option B, the tree handoff, the cheap profiler, and the
job's own `profile.layout` (33 drags, 15.0 s, 889 resize events), compared with
the step 4 trace:

| Measure | After step 4 | Now |
|---|---:|---:|
| Background layout in drags (median / p95) | 24.0 / 40.4 ms | **13.3 / 29.4 ms** |
| New layouts painted per second | 19.4 | **37.1** |
| Resize event → painted (median / p95) | 57 / 91 ms | **45 / 71 ms** |
| Final width painted after release (median) | 23 ms | 16 ms |
| Present gap in drags (median / p95) | 15.0 / 33.1 ms | 9.7 / 19.9 ms |

First `profile.layout` from the app (576 jobs in drags, medians): every job
re-broke about 92 paragraphs (379 lines). `layout.document` 12.0 ms, of which
block bodies (`layout.visit`) 7.4 ms: `inline.place` 2.8, `visit.geometry` 2.3,
`mode` 0.7, `inline.plan` 0.7. Outside block bodies ~4.6 ms: 1548 line visits
(1379 only moved), height sums 0.7, and the reachability sweep 1.4 ms on every
job (`layout.sweep.reachability` 1.05 + `identify` 0.31). `layout.async.finish`
on main rose from ~0.5 to 1.6 ms median ([INFERENCE] the replaced installed tree
is now uniquely owned and freed on main). Breakpoint style still ran 11 times in
drags at 14–34 ms.

GUI trace after Option A (same page: ~1749 paint nodes vs ~1723; 21 drags,
25.7 s, 1253 resize events), compared with the trace after the lane fix:

| Measure | Before Option A | After |
|---|---:|---:|
| Background layout in drags (median / p95) | 41.1 / 62.9 ms | **23.1 / 36.4 ms** |
| New layouts painted per second | 15.3 | **23.6** |
| Resize event → painted (median / p95) | 84 / 132 ms | **57 / 88 ms** |
| Final width painted after release (median) | 31 ms | 21 ms |
| Layout worker busy during drags | 74% | 60% |

The 57 ms now splits into waiting for the running pass (16 ms), the pass
(25 ms), and finish → paint (13 ms: about 7 ms waiting for the next 60 Hz tick
plus 4.9 ms paint). About half of the latency is now scheduling, not layout.
Layout is still above one frame at every width (22–26 ms). Breakpoint style
still runs on main during drags (14 passes, 13–25 ms).

## Execution protocol

1. Read the current code and the latest trace before changing anything.
2. Change one step only; do not mix layout and presenter work.
3. Run `swift test` and `swift build` after the change.
4. Exercise the changed path with a headless screenshot or a GUI trace.
5. Update this file with measured before/after numbers.
6. If the change regresses visible output, revert it immediately and record why.
