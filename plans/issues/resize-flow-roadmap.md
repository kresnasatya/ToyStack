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

Verification: `swift test` (297 tests) and
`TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test --no-parallel` (297 tests). The
background suites need `--no-parallel`: whether a pass may paint depends on
reused inputs, which are keyed on the process-wide `StyleRevision.epoch`, and
parallel suites bump it.

## Execution protocol

1. Read the current code and the latest trace before changing anything.
2. Change one step only; do not mix layout and presenter work.
3. Run `swift test` and `swift build` after the change.
4. Exercise the changed path with a headless screenshot or a GUI trace.
5. Update this file with measured before/after numbers.
6. If the change regresses visible output, revert it immediately and record why.
