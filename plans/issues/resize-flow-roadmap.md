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

Remaining: bind only pixels that changed, and stage a new generation while the
old complete frame stays visible. Measure uploaded pixels, not layer count.

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

## Execution protocol

1. Read the current code and the latest trace before changing anything.
2. Change one step only; do not mix layout and presenter work.
3. Run `swift test` and `swift build` after the change.
4. Exercise the changed path with a headless screenshot or a GUI trace.
5. Update this file with measured before/after numbers.
6. If the change regresses visible output, revert it immediately and record why.
