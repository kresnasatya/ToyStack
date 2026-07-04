# Bugfix Plan: One-Frame Flicker After Every Click (Transforms Dropped)

## What the videos show

Both recordings (`Screen Recording 2026-07-04 at 11.42.00.mov` and
`11.46.33.mov`, exercise-13-9 page) contain the same glitch. Frame-by-frame
extraction pins it down precisely:

- Video 11.42.00, around t=5.1s: the frame before is correct, then for
  **exactly one frame (~16ms)** every `transform: translate(...)` on the page
  is ignored — box 2 (blue) jumps from its translated spot back to x=0,
  box 3 (yellow) loses both its parent's and its own offset, box 5 (salmon)
  snaps back under box 4 (gray). The next frame is correct again.
- Video 11.46.33, at t=1.483s and t=8.467s: same single-frame jump.
  The per-frame luma-difference metric shows the signature clearly: two large
  spikes 16ms apart (change + change back), silence around them.
- The glitch fires right after **every click** — even a click on empty space
  that changes no content.

So: one frame where the whole draw pass runs **without any transform
wrappers**, sandwiched between two correct frames.

## Why it happens

Three pieces interact. Each is fine alone; together they produce the flicker.

### Piece 1: ancestor pointers in the effect tree are weak

Every paint pass wraps each block in fresh effect objects:
`Transform(children: [Blend(children: cmds)])` — see `paintVisualEffects`
(`Sources/Engine/DOMUtils.swift:476-511`, the wrap at line 508-510).

- A paint command holds a **strong** reference to its direct parent effect
  (`parentEffect: VisualEffect?` on each command struct).
- But an effect's pointer to *its* parent is **weak**
  (`Sources/Engine/VisualEffect.swift:8`).

So a `CompositedLayer` (which stores paint commands) keeps only the direct
parent `Blend` alive. The `Transform` above it — and everything higher — is
kept alive **only by the display-list array itself**.

### Piece 2: draw-only frames rebuild the effect chain by walking those weak pointers

`Browser.computePaintDrawList` (`Sources/Engine/Browser.swift:278-324`)
rebuilds the draw list for each layer by climbing from
`layer.displayItems[0].parentEffect` upward via `parent = p.parent`
(line 310). If an ancestor has been freed, the weak pointer is `nil`, the
climb **stops silently**, and the layer is drawn with no `Transform` /
`Blend` wrappers at all — content appears at untransformed coordinates.
No crash, no log. Exactly what the flicker frame shows.

### Piece 3: the commit loop pairs *new* display list with *old* layers for one frame

Timeline of a click:

1. **Tick A** — `Tab.click` calls `setNeedsRender()` (`Tab.swift:837,889`).
   `runAnimationFrame` (`Tab.swift:427-504`) runs `render()`, which builds a
   **brand-new display list with brand-new effect objects**
   (`Tab.swift:416-422`), then commits with `compositedUpdates = nil`
   (full composite, `Tab.swift:494-495`).
2. `Browser.commit` (`Browser.swift:104-121`) replaces
   `activeTabDisplayList` with the new list. **The old display list array is
   released here** — the old `Transform` objects deallocate (only the direct
   `Blend`s survive, held by the old layers). It submits the full-composite
   job (call it job 1) to the raster thread, and — line 118 — re-arms
   `needsAnimationFrame = true`.
3. **Tick B, ~16ms later** — nothing is dirty, but `runAnimationFrame`
   commits unconditionally every tick (`Tab.swift:496-503`). This time
   `compositedUpdates = [:]` (non-nil) → `setNeedsDrawOnly()` → a
   **draw-only job** (job 2) is submitted. Its inputs snapshot
   `previousLayes: compositedLayers` (`Browser.swift:143`) — and because
   job 1's completion (a `Task { @MainActor }`, `Browser.swift:171-181`)
   usually hasn't landed yet, these are still the **old layers**.
4. Job 2 runs `computePaintDrawList` on old layers whose ancestor chains
   were freed in step 2. Weak `parent` pointers are `nil` → transforms
   dropped → wrong draw list → **one wrong frame on screen** (it applies
   after job 1's correct one, because the raster queue is serial and
   completions land in order).
5. **Tick C** — another idle commit; by now `compositedLayers` are the new
   layers from job 1, whose ancestors are alive inside
   `activeTabDisplayList`. Correct frame. Flicker over.

This also explains the no-click flicker at t=1.48 in the second video: any
full re-render (clicking empty space also calls `setNeedsRender()`) triggers
the same A/B/C sequence.

### Related hazard found on the way (worth fixing, not the flicker itself)

`RasterThread.submit` drops a *pending* job when a newer one arrives
(`Sources/Engine/RasterThread.swift:20`, "newest wins"). But
`scheduleRasterAndDraw` clears `needsComposite/needsRaster/needsDraw`
*at submit time* (`Browser.swift:148-150`). If a full-composite job is
dropped while still pending, its work is lost — the new display list is
never composited and the screen can keep showing stale layers until the next
interaction.

## The fix

The core defect: **a composited layer does not keep its own ancestor effects
alive**, yet the draw pass depends on them. (The Python original from
browser.engineering never hits this — Python references are all strong, so
the old display list stays alive as long as the layers point into it.)

### Files that change and why

| File | Why |
|---|---|
| `Sources/Engine/CompositedLayer.swift` | Option A: store the ancestor chain strongly |
| `Sources/Engine/Browser.swift` | Build the chain during composite; walk it (instead of weak pointers) in `computePaintDrawList`; optional flag-loss guard |

### Option A — each layer owns its ancestor chain (recommended)

Add a strong array to `CompositedLayer`; fill it during `computeComposite`
(while the display list is guaranteed alive); make `computePaintDrawList`
iterate that array instead of climbing weak pointers.

Pro: a layer snapshot is self-sufficient — no ordering between commits,
completions, and ticks can ever free its ancestors. Con: a few extra lines.

### Option B — Browser keeps the source display list alive

Keep a `layersSourceDisplayList: [Any]` property on `Browser`, assigned in
the raster completion whenever `compositedLayers` is replaced, so the old
tree can't deallocate while its layers are still in use.

Pro: ~3 lines. Con: a subtle cross-thread window remains — the main thread
can replace that property (freeing the old tree) while a draw-only job is
still walking the weak pointers on the raster thread. Small, but the same
bug class survives.

**Recommendation: Option A.** It removes the weak-pointer dependency
entirely instead of narrowing the window.

## Steps (each leaves the project building)

### Step 1 — store the chain on the layer

`Sources/Engine/CompositedLayer.swift` (near line 7):

```swift
var cachedImage: CGImage? = nil
// NEW: strong references to this layer's ancestor effects (nearest first).
// Without this, only the display-list array keeps ancestors alive, and
// draw-only frames after a repaint would find freed (nil) weak parents.
var ancestorChain: [VisualEffect] = []
```

### Step 2 — fill it at composite time

`Sources/Engine/Browser.swift`, end of `computeComposite` (before
`return compositedLayers`, line 251):

```swift
for layer in compositedLayers {
    var chain: [VisualEffect] = []
    var effect = layer.displayItems.first?.parentEffect
    while let e = effect {
        chain.append(e)
        effect = e.parent
    }
    layer.ancestorChain = chain
}
```

This runs right after `addParentPointers` (line 202) set the pointers, while
the display list is alive, so the chain is complete.

### Step 3 — walk the stored chain in `computePaintDrawList`

`Sources/Engine/Browser.swift:286-315`. Old vs new:

Old (weak-pointer climb):

```swift
var currentEffect: Any = DrawCompositedLayer(layer: layer)
var parent: VisualEffect? = layer.displayItems[0].parentEffect
while let p = parent {
    let newParent = getLatest(p, in: inputs.compositedUpdates)
    let newParentKey = ObjectIdentifier(newParent)
    if let existing = newEffects[newParentKey] {
        existing.children.append(currentEffect)
        currentEffect = existing
        break
    } else {
        // ... clone switch ...
        newEffects[newParentKey] = cloned
        currentEffect = cloned
        parent = p.parent          // weak pointer: nil once old tree freed
    }
}
if parent == nil {
    drawList.append(currentEffect)
}
```

New (iterate the strong chain; same clone logic inside):

```swift
var currentEffect: Any = DrawCompositedLayer(layer: layer)
var mergedIntoExisting = false
for p in layer.ancestorChain {
    let newParent = getLatest(p, in: inputs.compositedUpdates)
    let newParentKey = ObjectIdentifier(newParent)
    if let existing = newEffects[newParentKey] {
        existing.children.append(currentEffect)
        mergedIntoExisting = true
        break
    }
    // ... clone switch, unchanged ...
    newEffects[newParentKey] = cloned
    currentEffect = cloned
}
if !mergedIntoExisting {
    drawList.append(currentEffect)
}
```

(`mergedIntoExisting` mirrors the old `parent != nil` exit: when the layer
was grafted into an already-built chain, its root is already in `drawList`.)

### Step 4 (optional hardening) — don't lose composite work when a pending job is dropped

This step is not part of the flicker fix. It closes the separate hazard
described in "Related hazard found on the way" above.

#### The problem in plain words

`RasterThread` keeps at most **one** waiting job. If a new job is submitted
while an older one is still waiting its turn, the older one is silently
thrown away (`Sources/Engine/RasterThread.swift:20`, the
`pending = job  // newest wins` line). Normally that is fine — the newer
job carries newer inputs, so the older job's output would be obsolete anyway.

The trap is *when* the dirty flags get cleared. `scheduleRasterAndDraw`
clears them at **submit time**, not at completion time
(`Sources/Engine/Browser.swift:149-151`):

```swift
needsComposite = false
needsRaster = false
needsDraw = false
```

So the moment a composite job is handed to the raster thread, the Browser
believes "compositing is taken care of." If that job is later dropped
before it runs, nobody sets `needsComposite` back to `true` — the new
display list is never turned into layers, and the screen keeps showing the
old layers until some future interaction happens to request a full
composite again.

Bad timeline, step by step:

1. A commit arrives with a new display list → `scheduleRasterAndDraw`
   submits **job 1** with `needsComposite: true`, then clears the flags.
2. Before the raster thread picks job 1 up, another commit arrives (say a
   cheap draw-only one) → **job 2** is submitted. `RasterThread` replaces
   the pending job: **job 1 is gone, and with it the only request to
   composite the new display list.**
3. Job 2 runs with `needsComposite: false`, so it reuses
   `inputs.previousLayes` — the **stale** layers built from the *old*
   display list (`Sources/Engine/Browser.swift:161-163`).
4. Result: stale content on screen, no error, until the next interaction.

#### The fix idea

Keep a single Bool that means: **"a composite was submitted, but its result
has not come back to the main thread yet."** While that Bool is `true`,
every job we submit asks for a composite again. So if the original
composite job gets dropped, the very next job — whatever kind it was going
to be — redoes the composite, and nothing is lost.

Three small changes, all in `Sources/Engine/Browser.swift`:

#### 4a — add the field

Next to the other dirty flags (`needsComposite` etc.):

```swift
private var compositeInFlight = false
```

#### 4b — in `scheduleRasterAndDraw`, ask for the composite while one is unresolved

Compute the effective "should this job composite?" value once, then use it
both for the job's inputs and to raise the flag. Around lines 141-151:

Old:

```swift
let inputs = RasterInputs(
    displayList: activeTabDisplayList, scroll: activeTabScroll,
    interestTop: activeTabInterestTop, interestBottom: activeTabInterestTop + 4 * HEIGHT,
    compositedUpdates: compositedUpdates, previousLayes: compositedLayers,
    darkMode: darkMode, needsComposite: needsComposite, needsRaster: needsRaster,
    needsDraw: needsDraw, hoveredBounds: hoveredA11yNode?.bounds
)

needsComposite = false
```

New:

```swift
let wantsComposite = needsComposite || compositeInFlight

let inputs = RasterInputs(
    displayList: activeTabDisplayList, scroll: activeTabScroll,
    interestTop: activeTabInterestTop, interestBottom: activeTabInterestTop + 4 * HEIGHT,
    compositedUpdates: compositedUpdates, previousLayes: compositedLayers,
    darkMode: darkMode, needsComposite: wantsComposite, needsRaster: needsRaster,
    needsDraw: needsDraw, hoveredBounds: hoveredA11yNode?.bounds
)

if wantsComposite { compositeInFlight = true }
needsComposite = false
```

Read `wantsComposite` as: "composite if the Browser is dirty, **or** if an
earlier composite was submitted but hasn't reported back yet."

#### 4c — in the completion closure, lower the flag when a composite result lands

The completion already branches on whether the job produced layers
(`Sources/Engine/Browser.swift:175`). `output.compositedLayers` is non-nil
only when the job really ran the composite (see the `RasterOutput` built at
lines 168-170), so that branch is exactly the "composite finished" signal:

Old:

```swift
if let layers = output.compositedLayers {
    self.compositedLayers = layers
```

New:

```swift
if let layers = output.compositedLayers {
    self.compositeInFlight = false  // composite result arrived; debt paid
    self.compositedLayers = layers
```

#### Trade-off

There is a window between "job 1 submitted" and "job 1's completion runs on
the main thread." Any job submitted inside that window sees
`compositeInFlight == true` and re-composites even though job 1 was not
dropped. That is one redundant composite per such overlap — off the main
thread, and rare. Correct beats cheap here.

## Verification

1. `swift build` then run, open `http://localhost:3000/exercise-13-9`.
2. Click each box several times, and click empty space. Record the screen;
   step through frames around each click (QuickTime: arrow keys). Before the
   fix there is exactly one frame with boxes 2/3/5 at untransformed spots;
   after the fix there must be none.
3. Regression check the animation paths (they use the same
   `computePaintDrawList` with `compositedUpdates`): ch13 transition /
   keyframe demos in `www/ch13/` must still animate smoothly.
4. Regression check scrolling and exercise-13-8 (short-display-list layers
   draw via the fallback path in `DrawCompositedLayer.execute`,
   `Sources/Engine/PaintCommand.swift:198-208` — they too rely on the
   rebuilt effect chain, so they were flickering as well and must be fixed
   by the same change).
