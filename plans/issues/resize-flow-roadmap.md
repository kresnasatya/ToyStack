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

### Step 2: incremental resize layout

- Skip layout when the effective content width of a subtree did not change.
- Reuse line plan and placement for unchanged inline contexts.
- Add a breakpoint path that updates text metrics without rebuilding every item.
- Target: 100-192 ms -> below 60 ms.

### Step 3: present budget

- Reduce layer count (start with 128 px -> 256 px tiles).
- Bind only layers whose image changed.
- Keep the old complete generation visible while a new one is uploading.
- Target: `view.commit` below 10 ms.

### Step 4: long-term pipeline

- Pending/active layout tree.
- Layout work outside the main thread for safe subtrees.
- A compositor loop that can scroll and resize without the main thread.

## Execution protocol

1. Read the current code and the latest trace before changing anything.
2. Change one step only; do not mix layout and presenter work.
3. Run `swift test` and `swift build` after the change.
4. Exercise the changed path with a headless screenshot or a GUI trace.
5. Update this file with measured before/after numbers.
6. If the change regresses visible output, revert it immediately and record why.
