# Exercise 13-3: Composited and threaded animations

Goal: make **transform** animations go through the composited fast path (no
raster), and make **scrolling** on a page that is mid-animation also avoid
raster. A simultaneous `transform` + `opacity` animation must run without any
raster; scrolling that page must not raster either.

The HTML proof lives in `www/ch13/exercise-13-3.html`. It already references
two files that do **not** exist yet — you said you would add them:

- `www/ch13/example13-transform-transition.css`
- `www/ch13/example13-transform-transition.js`

I list their required contents at the bottom so the proof actually runs.

---

## What already works

- `opacity` has a fast path in `Tab.runAnimationFrame` (Tab.swift:420-424): it
  writes the new value into `node.style`, stores *something* in
  `compositedUpdates`, and sets only `needsPaint` (not `needsCompositeForPaint`).
- `Browser.commit` (Browser.swift:111-115) treats a non-nil
  `compositedUpdates` as "draw-only" → `setNeedsDrawOnly()` → no raster.
- `Browser.computePaintDrawList` (Browser.swift:254-300) walks each
  `CompositedLayer`'s parent-effect chain and calls `getLatest` to swap in the
  updated effect via `clone(child:)`. `Blend`, `Transform`, `BlurFilter`, and
  `ScrollEffect` all already support `clone(child:)`.
- Scrolling already calls `applyScroll` (Tab.swift:545,552), which calls
  `setNeedsDrawOnly()` (Browser.swift:323-326). That sets only `needsDraw`,
  not `needsRaster`. So plain scrolling on a static page already skips raster.

So the threaded-scrolling half of the exercise is **mostly already done**. The
real work is the transform half.

---

## Bug 1 — transform animation forces a full composite+raster

### Root cause

`Tab.runAnimationFrame` handles `transform-x` / `transform-y` like this
(Tab.swift:411-419):

```swift
if property == "transform-x" || property == "transform-y" {
    node.style[property] = value
    if let x = node.style["transform-x"],
        let y = node.style["transform-y"]
    {
        node.style["transform"] = "translate(\(x)px, \(y)px)"
    }
    needsCompositeForPaint = true   // ← forces full composite
    needsPaint = true
}
```

`needsCompositeForPaint = true` flows downstream (Tab.swift:456):

```swift
let updates: [ObjectIdentifier: VisualEffect]? =
    (needsComposite || needsCompositeForPaint) ? nil : compositedUpdates
```

`nil` → `Browser.commit` runs `setNeedsComposite()` (Browser.swift:111-112) →
`needsRaster = true` (Browser.swift:302-306). Every animation frame rasterises
the whole page. That is exactly what the exercise says must stop.

The opacity branch right below it already does the right thing and was clearly
intended as the template (the hint says so: "for transforms, it just requires
following the same pattern as for opacity").

### Sub-bug 1a — the value stored for opacity is a dead cast

Even the opacity branch has a latent bug (Tab.swift:422-423):

```swift
compositedUpdates[ObjectIdentifier(node)] =
    node.layoutObject as? Engine.VisualEffect
```

`node.layoutObject` is a `BlockLayout` (BlockLayout.swift:36, TextLayout.swift:28,
InputLayout.swift:28). `BlockLayout` conforms to `LayoutObject`, a protocol
(Layouts/LayoutObject.swift:6). It is **not** a `VisualEffect`. So the cast
always produces `nil`, and `compositedUpdates` ends up holding
`[key: nil]` entries — which is why `getLatest` (Browser.swift:249) still finds
the key and returns `compositedUpdates[key]!` … a `nil` wrapped in `Optional`.
In Swift this would crash on force-unwrap; that it doesn't crash means the
opacity path is effectively no-op today and opacity animations have been
relying on `needsPaint`→`setNeedsPaint`→`render()`→full repaint. In other
words, opacity "works" by accident, via raster, not via the fast path.

The fix: rebuild the visual-effect subtree from the node's **current** style
and store *that*. `paintVisualEffects` (DOMUtils.swift:409-444) already does
exactly this — it reads `opacity`, `transform`, `blur`, `border-radius`,
`mix-blend-mode` off `node.style` and returns `[Transform]` (Transform wraps
Blend wraps the content). It is the same function used during `render()`'s
paint pass, so the shape is guaranteed to match what `computePaintDrawList`
expects to clone.

### Sub-bug 1b — `getLatest` only swaps `Blend`, never `Transform`

Browser.swift:243-252:

```swift
nonisolated private static func getLatest(
    _ effect: Engine.VisualEffect,
    in compositedUpdates: [ObjectIdentifier: Engine.VisualEffect]
) -> Engine.VisualEffect {
    guard let node = effect.node else { return effect }
    let key = ObjectIdentifier(node)
    guard compositedUpdates[key] != nil else { return effect }
    guard effect is Blend else { return effect }   // ← Transform skipped
    return compositedUpdates[key]!
}
```

`paintVisualEffects` returns `[Transform(… children: [Blend(…)])]`. The outer
effect walked by `computePaintDrawList` is the `Transform`, not the `Blend`.
So even with a correct value stored, `getLatest` returns the *old* Transform
and the animation never shows. The `Blend`-only guard must be removed (or
broadened to every `VisualEffect` subclass that supports `clone(child:)`).

---

## Fix 1 — transform on the composited fast path

### Files touched

| File | Change | Why |
|------|--------|-----|
| `Sources/Engine/Tab.swift` | Rewrite the `transform-x/transform-y` and `opacity` branches in `runAnimationFrame` | Stop setting `needsCompositeForPaint`; store a freshly-built `VisualEffect` instead |
| `Sources/Engine/Browser.swift` | Drop the `effect is Blend` guard in `getLatest` | Let `Transform` (and any other effect) be swapped too |

No other files change. `Transform.clone(child:)` already exists
(Transform.swift:28-30). `computePaintDrawList` already clones `Transform`
(Browser.swift:275-276). `Blend` and `Transform` already have `node` set
(DOMUtils.swift:441-442), so `getLatest`'s `ObjectIdentifier(node)` keying
works for both.

### Step 1 — `Tab.runAnimationFrame`, replace lines 411-424

Old (Tab.swift:411-424):

```swift
if property == "transform-x" || property == "transform-y" {
    node.style[property] = value
    if let x = node.style["transform-x"],
        let y = node.style["transform-y"]
    {
        node.style["transform"] = "translate(\(x)px, \(y)px)"
    }
    needsCompositeForPaint = true
    needsPaint = true
} else if property == "opacity" {
    node.style[property] = value
    compositedUpdates[ObjectIdentifier(node)] =
        node.layoutObject as? Engine.VisualEffect
    needsPaint = true
}
```

New:

```swift
if property == "transform-x"
    || property == "transform-y"
    || property == "opacity"
{
    node.style[property] = value
    if property == "transform-x" || property == "transform-y" {
        if let x = node.style["transform-x"],
            let y = node.style["transform-y"]
        {
            node.style["transform"] = "translate(\(x)px, \(y)px)"
        }
    }
    // Rebuild the effect subtree from current style so the compositor
    // can swap it in without re-rastering. paintVisualEffects returns
    // [Transform(children: [Blend(children: [content])])]; the outer
    // Transform is what computePaintDrawList walks via parentEffect.
    if let rect = (node.layoutObject as? BlockLayout)?.selfRect(),
        let effect = paintVisualEffects(node: node, cmds: [], rect: rect).first
            as? VisualEffect
    {
        compositedUpdates[ObjectIdentifier(node)] = effect
    }
    // NOTE: no needsCompositeForPaint, no needsPaint. compositedUpdates
    // is enough; commit() will setNeedsDrawOnly().
}
```

Why `selfRect()` and not `obj.bounds`: `paintVisualEffects`'s `rect` argument
is the element's own border-box, the same value passed during the real paint
pass (see DOMUtils.swift:224-238 where `ScrollEffect` is built from
`block.selfRect()`). `BlockLayout.selfRect()` already exists and is used
there.

**Caveat — empty `cmds`:** `paintVisualEffects` wraps `cmds` inside the effect
chain. We pass `[]` because `computePaintDrawList` does not use the stored
effect's children — it calls `clone(child: currentEffect)` and replaces them
with the real composited-layer content (Browser.swift:272-287). So the empty
children list is throwaway. This matches what `Blend.clone` / `Transform.clone`
already do: they rebuild with a single new child.

### Step 2 — `Browser.getLatest`, drop the Blend-only guard

Old (Browser.swift:243-252):

```swift
nonisolated private static func getLatest(
    _ effect: Engine.VisualEffect,
    in compositedUpdates: [ObjectIdentifier: Engine.VisualEffect]
) -> Engine.VisualEffect {
    guard let node = effect.node else { return effect }
    let key = ObjectIdentifier(node)
    guard compositedUpdates[key] != nil else { return effect }
    guard effect is Blend else { return effect }
    return compositedUpdates[key]!
}
```

New:

```swift
nonisolated private static func getLatest(
    _ effect: Engine.VisualEffect,
    in compositedUpdates: [ObjectIdentifier: Engine.VisualEffect]
) -> Engine.VisualEffect {
    guard let node = effect.node else { return effect }
    let key = ObjectIdentifier(node)
    guard let updated = compositedUpdates[key] else { return effect }
    // Match by type: paintVisualEffects returns [Transform(children: [Blend])]
    // for one node, so both the old Transform and old Blend share `node`.
    // We must swap each old effect for the *same-typed* effect inside the
    // updated subtree, otherwise the parent chain collapses (Blend gets
    // replaced by a Transform and the tree shape is destroyed).
    if type(of: effect) == type(of: updated) {
        return updated
    }
    // Walk the updated subtree's children to find a same-typed descendant.
    var stack: [VisualEffect] = [updated]
    while let candidate = stack.popLast() {
        if type(of: candidate) == type(of: effect) {
            return candidate
        }
        for child in candidate.children {
            if let ve = child as? VisualEffect {
                stack.append(ve)
            }
        }
    }
    return effect
}
```

#### Why the naive fix (the first version of this step) is wrong

The first version of this fix was simply:

```swift
return compositedUpdates[key] ?? effect
```

That broke both `exercise-13-2` (flicker, no transition) and `exercise-13-3`
(no visible change). Reason:

`paintVisualEffects` (DOMUtils.swift:441-442) returns a **two-level** subtree
for any element with both `transform` and `opacity`:

```swift
let blend = Blend(opacity: opacity, blendMode: blendMode, node: node, children: effectCmds)
let transform = Transform(translation: translation, rect: rect, node: node, children: [blend])
return [transform]
```

Both `Blend` and `Transform` carry the **same** `node`. During composite,
`addParentPointers` (DOMUtils.swift:488-490) sets each `PaintCommand`'s
`parentEffect` to its **innermost** VisualEffect parent — i.e. the `Blend`,
not the `Transform`. So in `computePaintDrawList` the walk is:

```
layer.displayItems[0].parentEffect   →  old Blend      (step 1)
old Blend.parent                      →  old Transform  (step 2)
old Transform.parent                  →  nil            (stop)
```

With the naive `getLatest`, **both** steps look up the same key
`ObjectIdentifier(node)` and get back the **single** stored `Transform`. So:

- Step 1 swaps the old `Blend` for the new `Transform` (wrong type). The
  `if let blend = newParent as? Blend` branch (Browser.swift:271) fails; the
  `else if let transform = newParent as? Transform` branch (Browser.swift:273)
  runs and clones a `Transform` whose child is `DrawCompositedLayer`. The
  `Blend` layer of opacity is gone.
- Step 2 looks up the same key, gets the same new `Transform`, finds it
  already in `newEffects` (Browser.swift:265), and **appends a second child**
  to it (Browser.swift:266). The tree now has one `Transform` with two
  `DrawCompositedLayer` children and no `Blend` at all.

The draw list is structurally wrong, so the canvas paints garbage or nothing —
hence the flicker in 13-2 and the dead-still page in 13-3.

The original `guard effect is Blend else { return effect }` avoided this
collapse but only ever swapped `Blend`, so a `Transform` animation never
updated (Bug 1b). The real fix is to match **by type within the updated
subtree**: the old `Blend` maps to the new `Blend` (found by descending
`updated.children`), and the old `Transform` maps to the new `Transform`
(the stored root itself). That preserves the two-level shape while updating
both levels' parameters.

#### Why the type-match walk is sufficient

`paintVisualEffects` produces a fixed, shallow shape:
`Transform → Blend → [BlurFilter] → content`. There is at most one effect of
each type per node, and the depth is bounded (≤3 effect levels). A DFS over
`updated.children` therefore finds the matching type in at most two hops and
cannot loop (the updated subtree has no cycles — it is freshly built from
`paintVisualEffects`, which never reuses nodes). If no same-typed descendant
exists (e.g. the node lost its `transform` so the new subtree is just
`Blend`), we return `effect` unchanged — the old `Transform` stays, which is
harmless because on the *next* composite pass `addParentPointers` will rebuild
the chain from the new display list.

### Step 3 — verify the `needsPaint` removal is safe

The new branch sets neither `needsPaint` nor `needsCompositeForPaint`. Trace:

1. `runAnimationFrame` finishes with `needsPaint == false`, `needsRender ==
   false`, `compositedUpdates` non-empty.
2. Lines 437-439 (`if needsPaint { setNeedsPaint() }`) skipped. Good — no
   `render()`, no display-list rebuild.
3. Lines 441-449 (`if needsRender`) skipped.
4. Line 456: `needsComposite` false (no style/layout), `needsCompositeForPaint`
   false → `updates = compositedUpdates` (non-nil).
5. `browser.commit` receives non-nil `compositedUpdates` → `setNeedsDrawOnly()`
   (Browser.swift:113-114) → `needsDraw = true` only.
6. `scheduleRasterAndDraw`: `needsComposite` false → reuse `previousLayes`;
   `needsDraw` true → `computePaintDrawList` rebuilds the draw list with the
   swapped effects. **No raster.**

This is the same path opacity was *supposed* to take.

### Step 3a — Bug 6: box snaps back when the animation ends

#### Symptom

After Fix 1 + Fix 2, `exercise-13-2` animates correctly while running: click
"Run", the five boxes slide 400px over 2s. But the instant the animation
finishes, the boxes **jump back to 0px**. Click "Reset" and they slide back
to 0px, then jump forward to 400px at the end. The final frame is lost.

#### Root cause

`runAnimationFrame`'s animation loop (Tab.swift:408-437) has two branches:

- `if let value = animation.animate()` — animation still running. Writes the
  interpolated value to `node.style`, stores a fresh effect in
  `compositedUpdates`, sets neither dirty flag. This is the Fix 1 fast path.
- `else` (Tab.swift:433-435) — animation finished. Only does
  `node.animations.removeValue(forKey: property)`. **No style write, no dirty
  flag, no composited update.**

The last `animate()` that returned a value wrote `node.style["transform-x"]`
to the final value (e.g. `"400"`), and stored a `compositedUpdates` entry
holding `translate(400,0)`. That frame committed draw-only and the box was
drawn at 400px. So far so good.

On the **next** frame, `animate()` returns `nil`. The `else` branch runs:
the animation is removed, `compositedUpdates` stays empty (nothing was added
this frame), `needsPaint`/`needsRender`/`needsCompositeForPaint` all false.
`updates` at line 457 becomes `compositedUpdates` = `[:]` — an **empty but
non-nil** dict. `Browser.commit` (Browser.swift:111-115) treats non-nil as
draw-only: `setNeedsDrawOnly()`. `computePaintDrawList` runs with an empty
`compositedUpdates`, so every `getLatest` call falls through to the old
effect stored in `previousLayes`. And `previousLayes` was last rebuilt at the
composite that happened **before the animation started** — when the box was
at `translate(0,0)`. So the draw list now paints the box at 0px. The box
snaps back.

In other words: the fast path never updates `previousLayes`. While the
animation runs, `compositedUpdates` papers over the stale layers each frame.
The instant the animation stops, the papering stops, and the stale layers
show through.

The pre-Fix-1 code did not have this bug because it set
`needsCompositeForPaint = true` on **every** animation frame, including the
last one. That forced `updates = nil` → `setNeedsComposite()` →
`computeComposite` rebuilt `previousLayes` from the current `displayList`,
baking the final transform into the layers. The cost was a raster per frame.
Fix 1 removed that per-frame raster, which exposed the end-of-animation hole.

#### Fix 6 — force one composite when an animation ends

When `animate()` returns `nil`, set `needsCompositeForPaint = true` and
`needsPaint = true` so the final value gets baked into `previousLayes`.
This is a **one-time** cost at animation end, not a per-frame cost — exactly
the right tradeoff: cheap fast path while running, one composite to settle
at the end.

##### File touched

| File | Change | Why |
|------|--------|-----|
| `Sources/Engine/Tab.swift` | In the `else` branch of the animation loop (line 433-435), set `needsCompositeForPaint = true` and `needsPaint = true` before removing the animation | Bake the final animated value into `previousLayes` so the box does not snap back when the animation stops |

##### Old (Tab.swift:433-435)

```swift
} else {
    node.animations.removeValue(forKey: property)
}
```

##### New

```swift
} else {
    // Animation finished. The fast path never updated previousLayes,
    // so the compositor still holds the pre-animation effect. Force one
    // composite to bake the final value (already written to node.style
    // by the last non-nil animate() call) into the layer tree. This is
    // a one-time cost at end-of-animation, not a per-frame cost.
    node.animations.removeValue(forKey: property)
    needsCompositeForPaint = true
    needsPaint = true
}
```

##### Why this is safe for the background-color branch too

The `else` branch is shared by all animated properties. The
background-color path (the `else` inside the `if let value` branch,
Tab.swift:427-432) already sets `needsCompositeForPaint = true` and
`needsPaint = true` on every frame, so when its animation ends, forcing
another composite is just one more repaint of the same kind — no change in
correctness, only a harmless extra frame. For transform/opacity, this is the
new behavior that fixes the snap-back.

##### Why not instead keep the last compositedUpdate around

One might try to avoid the end-of-animation composite by leaving the final
`compositedUpdates` entry in place forever. That does not work because
`compositedUpdates` is cleared at the end of every `runAnimationFrame`
(Tab.swift:464). Letting it persist would require restructuring the commit
protocol, and even then the *next* style change (e.g. another click of
"Run"/"Reset") would trigger a composite that rebuilds `previousLayes` from
`displayList` — at which point the stale-final-entry would be discarded
anyway. A single composite at end-of-animation is simpler and matches how
real browsers settle an animation.

### Step 4 — simultaneous transform + opacity

Both properties now hit the same branch. `paintVisualEffects` reads both
`node.style["opacity"]` and `node.style["transform"]` in one call, so the
single stored `Transform` reflects both. `compositedUpdates` ends up with one
entry per node, holding the combined effect. No extra work needed.

One ordering note: `node.animations` is a Dictionary, so the iteration order
of `transform-x`, `transform-y`, `opacity` is unspecified. Each iteration
writes to `node.style` and then rebuilds the effect. The last write wins in
`compositedUpdates`, but because every rebuild reads all three style values
(`transform`, `opacity`, plus blur/radius/blend which are static), every
intermediate rebuild is already consistent. Final stored effect is correct
regardless of order.

### Step 5 — Bug 7: `needsCompositeForPaint` latches true and breaks the next animation

#### Symptom

After Fix 6, the first "Run" click works: boxes animate to 400px and stay.
Click "Reset": boxes stay at 400px (no animation), then **jump** to 0px.
Click "Run" again: boxes **jump** to 400px with no animation. Every
subsequent animation is broken — no transition, just a snap.

#### Root cause

`needsCompositeForPaint` is declared at Tab.swift:44 and set `true` in two
places:

- Tab.swift:430 — background-color animation frame (the `else` inside the
  `if let value` branch).
- Tab.swift:435 — Fix 6's end-of-animation `else` branch.

It is read at Tab.swift:460:

```swift
let updates: [ObjectIdentifier: VisualEffect]? =
    (needsComposite || needsCompositeForPaint) ? nil : compositedUpdates
```

**It is never reset to `false`.** Search the codebase: the only writes are
the two `= true` assignments. There is no `needsCompositeForPaint = false`
anywhere. Compare with `needsComposite` and `needsRaster`, which
`Browser.scheduleRasterAndDraw` clears after consuming them
(Browser.swift:148-150).

The latch works like this:

1. First "Run" ends. Fix 6 sets `needsCompositeForPaint = true`. Frame
   commits with `updates = nil` → full composite → `previousLayes` rebuilt
   from `displayList` holding `translate(400,0)`. Box baked at 400px.
   Correct so far. **Flag stays true.**
2. "Reset" click. `setAttribute("style", "translate(0,0)")` →
   `setNeedsRender()` → `render()` → `diffStyles` creates transform-x/y
   animations (400→0). `render()` also sets `needsPaint` false at the end of
   its paint block (Tab.swift:397).
3. Next `runAnimationFrame`. The transform/opacity branch (Fix 1) writes
   interpolated values, stores `compositedUpdates`, sets **no** dirty flag.
   But line 460 sees `needsCompositeForPaint == true` (latched from step 1!)
   → `updates = nil`. `compositedUpdates` is **discarded**.
4. `Browser.commit` gets `nil` → `setNeedsComposite()` → full composite +
   raster. `computeComposite` rebuilds `previousLayes` from `displayList`.
   But `displayList` was last rebuilt during step 2's `render()`, before any
   animation frame — it holds `translate(400,0)` (the value `diffStyles`
   wrote back as `oldVal` at DOMUtils.swift:344). So the composite bakes
   `translate(400,0)` into the layers. `computePaintDrawList` runs with
   empty `compositedUpdates` → `getLatest` returns the old effects → box
   drawn at 400px.
5. Every subsequent animation frame repeats step 4: `compositedUpdates`
   discarded, composite from stale `displayList`, box stuck at 400px. The
   animation values are computed and thrown away.
6. Animation ends. Fix 6 fires again, composite runs, `displayList` still
   holds 400px (never refreshed because `needsPaint`/`needsRender` stayed
   false during the fast path). Box jumps to... actually it stays at 400px,
   until the *next* `render()` finally refreshes `displayList` and the box
   snaps to the new attribute value.

Net effect: after the first animation ends, `needsCompositeForPaint` is
permanently true, so the composited fast path never runs again. Every
animation either snaps or freezes. This is exactly what you observed.

Pre-Fix-6 this was invisible because the background-color branch set the
flag on every frame, so it was always true during any animation and the
composite path was the only path. Fix 6 made the flag *conditional*
(end-of-animation only), which exposed the missing reset.

#### Fix 7 — reset `needsCompositeForPaint` after it is consumed

Reset it at the same place `compositedUpdates` is cleared — the end of
`runAnimationFrame`, after `updates` has been computed and handed to
`commit`. By that point the flag has done its job (it forced `updates = nil`
for this frame) and must not leak into the next frame.

##### File touched

| File | Change | Why |
|------|--------|-----|
| `Sources/Engine/Tab.swift` | After line 464 (`compositedUpdates = [:]`), add `needsCompositeForPaint = false` | Clear the latch so the next animation frame can use the composited fast path |

##### Old (Tab.swift:457-465)

```swift
let updates: [ObjectIdentifier: VisualEffect]? =
    (needsComposite || needsCompositeForPaint) ? nil : compositedUpdates
let data = CommitData(
    url: url!, scroll: scroll, height: docHeight, displayList: displayList,
    compositedUpdates: updates, accessibilityTree: accessibilityTree, focus: focus,
    interestTop: interestTop
)
compositedUpdates = [:]
browser?.commit(tab: self, data: data)
```

##### New

```swift
let updates: [ObjectIdentifier: VisualEffect]? =
    (needsComposite || needsCompositeForPaint) ? nil : compositedUpdates
let data = CommitData(
    url: url!, scroll: scroll, height: docHeight, displayList: displayList,
    compositedUpdates: updates, accessibilityTree: accessibilityTree, focus: focus,
    interestTop: interestTop
)
compositedUpdates = [:]
needsCompositeForPaint = false   // consume the flag; do not let it latch
browser?.commit(tab: self, data: data)
```

One line added. The flag now lives for exactly one frame when an animation
ends (Fix 6), forces one composite to bake the final value, and is cleared
before the next frame. Subsequent animations run on the fast path again.

##### Why this belongs here and not in `Browser.commit`

`needsCompositeForPaint` is a `Tab`-private field (Tab.swift:44). `Browser`
has its own `needsComposite`/`needsRaster`/`needsDraw` flags which it resets
in `scheduleRasterAndDraw` (Browser.swift:148-150). The two layers do not
cross: `Tab` decides what kind of commit to send, `Browser` decides what
raster work to do from the commit. Resetting `needsCompositeForPaint` inside
`Browser` would require exposing it, breaking that separation. Resetting it
in `Tab.runAnimationFrame` right next to the `compositedUpdates` clear keeps
the bookkeeping local to where the flag is produced and consumed.

##### Verification against the symptom

After Fix 7:

1. First "Run" → animation runs on fast path, ends, Fix 6 sets flag, one
   composite bakes 400px, Fix 7 clears flag. Box stays at 400px.
2. "Reset" → `render()` creates 400→0 animations. `runAnimationFrame` fast
   path runs (flag is false now) → `compositedUpdates` non-nil → draw-only
   → box animates smoothly to 0px. Ends → Fix 6 bakes 0px, Fix 7 clears.
3. "Run" again → same as step 1, animates 0→400. Repeat indefinitely.

The latch is gone. Each animation is independent.

---

## Bug 8 — `lightgreen` renders black

### Symptom

In `exercise-13-3.html`, the second `<div>` (line 13, `background-color:
lightgreen`) renders **black** in the toy browser. The first div
(`lightblue`) renders correctly.

### Root cause

`exercise-13-3.html` line 13 uses `background-color: lightgreen`. The color
maps live in `Sources/Engine/PaintCommand.swift`:

- `cssColorToRGB` (PaintCommand.swift:3-31) — used by `ColorAnimation` for
  background-color transitions (DOMUtils.swift:346-347).
- `Color(cssName:)` (PaintCommand.swift:36-70) — used by `DrawRect` and
  friends to resolve a color string to a SwiftUI `Color`.

Both maps list `lightblue` (PaintCommand.swift:25, 64) but **neither lists
`lightgreen`**. `cssColorToRGB` returns `nil` for unknown names
(PaintCommand.swift:29); `Color(cssName:)` falls through to
`default: self = .black` (PaintCommand.swift:69). So `lightgreen` becomes
solid black.

This is not a transition bug — it is a missing color in the lookup table.
It shows up in 13-3 (and not in 13-2, which uses `steelblue`... also missing,
but 13-2's boxes have no visible background issue because `steelblue` falls to
black too and the user did not flag it). The fix is to extend both tables.

### Fix 8 — add `lightgreen` (and `steelblue`) to the color maps

#### Files touched

| File | Change | Why |
|------|--------|-----|
| `Sources/Engine/PaintCommand.swift` | Add `lightgreen` and `steelblue` cases to `cssColorToRGB` and to `Color(cssName:)` | Resolve these named colors instead of falling through to black |

#### Old — `cssColorToRGB` switch (PaintCommand.swift:17-30, partial)

```swift
switch name {
case "white": return (255, 255, 255)
case "black": return (0, 0, 0)
// …
case "lightblue": return (173, 216, 230)
case "lightgray", "lightgrey": return (211, 211, 217)
case "yellow": return (255, 255, 0)
case "purple": return (128, 0, 128)
default: return nil
}
```

#### New

```swift
switch name {
case "white": return (255, 255, 255)
case "black": return (0, 0, 0)
// …
case "lightblue": return (173, 216, 230)
case "lightgreen": return (144, 238, 144)   // CSS named color
case "steelblue": return (70, 130, 180)     // CSS named color
case "lightgray", "lightgrey": return (211, 211, 217)
case "yellow": return (255, 255, 0)
case "purple": return (128, 0, 128)
default: return nil
}
```

#### Old — `Color(cssName:)` switch (PaintCommand.swift:56-69, partial)

```swift
switch cssName.lowercased() {
case "white": self = .white
case "black": self = .black
// …
case "lightblue": self = Color(red: 0.68, green: 0.85, blue: 0.90)
case "lightgray", "lightgrey": self = Color(red: 0.83, green: 0.83, blue: 0.85)
case "transparent": self = .clear
case "yellow": self = .yellow
case "purple": self = .purple
default: self = .black
}
```

#### New

```swift
switch cssName.lowercased() {
case "white": self = .white
case "black": self = .black
// …
case "lightblue": self = Color(red: 0.68, green: 0.85, blue: 0.90)
case "lightgreen": self = Color(red: 0.56, green: 0.93, blue: 0.56)
case "steelblue": self = Color(red: 0.27, green: 0.51, blue: 0.71)
case "lightgray", "lightgrey": self = Color(red: 0.83, green: 0.83, blue: 0.85)
case "transparent": self = .clear
case "yellow": self = .yellow
case "purple": self = .purple
default: self = .black
}
```

RGB triples are the CSS3 named-color values (e.g. `lightgreen` = `#90EE90`
= `(144, 238, 144)`). Both maps must stay in sync: `cssColorToRGB` feeds
`ColorAnimation` (DOMUtils.swift:346), `Color(cssName:)` feeds `DrawRect`
and friends. Adding to only one would make a `background-color` transition
to/from `lightgreen` crash on the `nil` return, or render the start/end
frame black while interpolating.

---

## Bug 9 — multi-line `transition:` shorthand does not parse

### Symptom

After Fixes 1-7, `exercise-13-2` (single-line `transition: transform 2s
linear;`) animates correctly, but `exercise-13-3` (multi-line `transition:`
in `example13-transform-transition.css`) shows **no transition at all**. The
div jumps between its two states with no interpolation.

### Root cause

`example13-transform-transition.css` writes the transition shorthand across
multiple lines:

```css
div {
    transition:
        transform 2s,
        opacity 2s;
}
```

After the CSS parser consumes this, the value string passed to
`parseTransition` (DOMUtils.swift:300) is (whitespace shown as `·` and `↵`):

```
↵        transform 2s,↵        opacity 2s
```

`parseTransition` splits on `,` via `splitTopLevel` (DOMUtils.swift:258-279),
giving two items: `"\n        transform 2s"` and `"\n        opacity 2s"`.
Each item is then split on a single space
(`splitTopLevel(trimmed, separator: " ")`, DOMUtils.swift:305). But
`splitTopLevel` only splits on the **exact** separator character; it does
not treat runs of whitespace or newlines as a single delimiter. So the
tokens for the first item are:

```
["\n        transform", "2s"]
```

— the property token is `"\n        transform"`, **not** `"transform"`.
`parseTransition` stores this under the key `"\n        transform"` in its
output dict (DOMUtils.swift:315). Later, `diffStyles` (DOMUtils.swift:325)
iterates that dict and compares `property` against the literal strings
`"opacity"`, `"transform"`, `"background-color"` (DOMUtils.swift:331, 335,
345). None match `"\n        transform"`, so **no `NumericAnimation` is
created**. The transition never starts. The next `render()` simply applies
the new inline `transform`/`opacity` directly → the div snaps.

`exercise-13-2` works because its CSS is single-line:

```css
#linear { transition: transform 2s linear; }
```

The value string is `"transform 2s linear"` with no embedded newlines.
`splitTopLevel(·, separator: " ")` yields `["transform", "2s", "linear"]`
and `tokens[0]` is exactly `"transform"`. The match succeeds.

So the bug is whitespace handling inside `parseTransition`, exposed by
multi-line CSS. Two equivalent fixes exist; pick one.

### Fix 9 — collapse whitespace in `parseTransition` before tokenizing

#### File touched

| File | Change | Why |
|------|--------|-----|
| `Sources/Engine/DOMUtils.swift` | In `parseTransition`, normalize each comma-split item's whitespace before splitting on space | Make `tokens[0]` be `"transform"` regardless of newlines/indentation in the CSS source |

#### Design decision — Option A vs Option B

**Option A — normalize in `parseTransition` (recommended).** Collapse all
runs of whitespace (including newlines) in each comma-item to a single
space, then split on space. Localized: only the transition parser changes.
Risk: low. Matches how real browsers tokenize CSS values.

**Option B — make `splitTopLevel` split on any whitespace.** Change
`splitTopLevel` to treat `CharacterSet.whitespacesAndNewlines` as the
delimiter when `separator == " "`. Broader: affects every caller of
`splitTopLevel` (transition parsing, CSS body parsing, etc.). Risk: higher
— could change tokenization of other CSS values that currently rely on
exact-space splitting. More correct in principle but a larger blast
radius.

**Recommendation: Option A.** It fixes the symptom with the smallest change
and does not risk regressions in other CSS parsing. Option B is the
"proper" long-term fix but belongs in a separate refactor with its own test
sweep.

#### Old (DOMUtils.swift:300-318)

```swift
func parseTransition(_ value: String) -> [String: TransitionSpec] {
    var properties: [String: TransitionSpec] = [:]
    guard !value.isEmpty else { return properties }
    for item in splitTopLevel(value, separator: ",") {
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        let tokens = splitTopLevel(trimmed, separator: " ").filter({
            !$0.isEmpty
        })
        guard tokens.count >= 2 else { continue }
        let property = tokens[0]
        let durationStr = tokens[1]
        guard durationStr.hasSuffix("s"), let seconds = Double(durationStr.dropLast())
        else { continue }
        let numFrames = Int(seconds / REFRESH_RATE_SEC)
        let easing = tokens.count >= 3 ? parseEasing(tokens[2]) : .ease
        properties[property] = TransitionSpec(numFrames: numFrames, easing: easing)
    }
    return properties
}
```

#### New (Option A)

```swift
func parseTransition(_ value: String) -> [String: TransitionSpec] {
    var properties: [String: TransitionSpec] = [:]
    guard !value.isEmpty else { return properties }
    for item in splitTopLevel(value, separator: ",") {
        // Collapse all whitespace runs (including newlines) to single spaces
        // so multi-line CSS like:
        //     transition:
        //         transform 2s,
        //         opacity 2s;
        // tokenizes to ["transform", "2s"] and ["opacity", "2s"] instead of
        // ["\n        transform", "2s"].
        let normalized = item.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let tokens = splitTopLevel(normalized, separator: " ").filter({
            !$0.isEmpty
        })
        guard tokens.count >= 2 else { continue }
        let property = tokens[0]
        let durationStr = tokens[1]
        guard durationStr.hasSuffix("s"), let seconds = Double(durationStr.dropLast())
        else { continue }
        let numFrames = Int(seconds / REFRESH_RATE_SEC)
        let easing = tokens.count >= 3 ? parseEasing(tokens[2]) : .ease
        properties[property] = TransitionSpec(numFrames: numFrames, easing: easing)
    }
    return properties
}
```

`String.split(whereSeparator:)` with `$0.isWhitespace` splits on any run of
whitespace (space, tab, newline) and drops empty results, so
`"\n        transform 2s"` becomes `["transform", "2s"]`. The subsequent
`splitTopLevel(·, separator: " ")` is now redundant for whitespace but is
kept for safety (it still respects parentheses for any future easing token
that contains spaces inside `cubic-bezier(...)` — although
`parseEasing` handles that separately).

#### Why `cubic-bezier` still works

`exercise-13-2`'s `#custom` rule uses
`transition: transform 2s cubic-bezier(0.68, -0.55, 0.27, 1.55)`. The comma
inside `cubic-bezier(...)` must NOT be split as a top-level comma.
`splitTopLevel(·, separator: ",")` tracks paren depth (DOMUtils.swift:264-269)
so it keeps the `cubic-bezier(...)` argument intact. Fix 9 only changes how
whitespace *within* a comma-item is collapsed; it does not touch paren-aware
comma splitting. After the fix, the `#custom` item normalizes to
`"transform 2s cubic-bezier(0.68, -0.55, 0.27, 1.55)"`, splits on space to
`["transform", "2s", "cubic-bezier(0.68, -0.55, 0.27, 1.55)"]`, and
`parseEasing` (DOMUtils.swift:281-298) parses the cubic-bezier as before.

#### Verification

After Fix 9, `parseTransition("\n        transform 2s,\n        opacity 2s")`
returns `["transform": …, "opacity": …]`. `diffStyles` then matches both
properties, creates `transform-x`, `transform-y`, and `opacity`
`NumericAnimation`s, and the fast path (Fixes 1+2+6+7) runs them without
raster.

---

## Bug 10 — CSSParser drops comma-separated values in shorthand properties

### Symptom

After Fix 9, `exercise-13-3` **still** showed no transition. Fix 9 made
`parseTransition` whitespace-tolerant, but the value string it receives never
contained the second property to begin with.

### Root cause

`CSSParser.pair()` (CSSParser.swift:232-258) reads a declaration's value
with `word()` (CSSParser.swift:193-207):

```swift
private func word() throws -> String {
    let start = i
    while i < chars.count {
        let c = chars[i]
        if c.isLetter || c.isNumber || "#-.%".contains(c) {
            i += 1
        } else {
            break
        }
    }
    guard i > start else { throw CSSParseError.parseError }
    return String(chars[start..<i])
}
```

`word()` accepts only letters, digits, `#`, `-`, `.`, `%`. It stops at
**spaces, commas, semicolons** — everything else. So for:

```css
transition: transform 2s, opacity 2s;
```

`pair()` reads `prop = "transition"`, then `val = word() = "transform"` (stops
at the space after "transform"). The function-argument handler
(CSSParser.swift:240-256) only kicks in when the next char is `(`, so it is
skipped here. `pair` returns `("transition", "transform")`.

Because `transition` is listed in `isShortHand` (CSSParser.swift:339), the
token-collection loop runs (CSSParser.swift:351-357):

```swift
if CSSParser.isShortHand(prop) {
    skipWhitespace()
    while i < chars.count && chars[i] != ";" && chars[i] != "}" {
        guard let t = try? word() else { break }
        tokens.append(t)
        skipWhitespace()
    }
}
```

The loop calls `word()` repeatedly to gather the rest of the value. It
collects `"2s"`, then `skipWhitespace()` lands on the `,`. `word()` is called
again — `,` is not a word character, so `word()` throws, the `guard` fails,
and the loop **breaks**. The comma and everything after it (`opacity 2s`) is
never collected. `tokens = ["transform", "2s"]`.

`expand(shorthand: "transition", …)` returns `nil` (no case for
`transition` in the switch at CSSParser.swift:264-272), so control falls to
the `else` (CSSParser.swift:374-376):

```swift
let fullVal = tokens.joined(separator: " ")
```

`fullVal = "transform 2s"`. That is stored as `node.style["transition"]`.
**The `opacity` transition is lost at parse time.** No amount of fixing
`parseTransition` can recover it — the string it receives has only one
property.

`exercise-13-2` works because its CSS is single-property per rule:
`transition: transform 2s linear;`. No comma → the loop collects
`["transform", "2s", "linear"]` → `fullVal = "transform 2s linear"` →
`parseTransition` sees one property and works.

### Fix 10 — make the shorthand token loop comma-aware

The loop already stops at `;` and `}` (the real declaration terminators).
It must also **not** stop at `,`, which is a value-internal separator for
multi-value properties like `transition: a 1s, b 2s`. When `word()` fails
because the current char is `,`, consume the comma as a literal token and
continue.

#### File touched

| File | Change | Why |
|------|--------|-----|
| `Sources/Engine/CSSParser.swift` | In the `isShortHand` token loop (line 351-357), handle `,` by appending it as a token and continuing instead of breaking | Preserve comma-separated values so `transition: a 1s, b 2s` is not truncated to `a 1s` |

No change to `word()` itself — it is shared by selector parsing, where `,`
means selector grouping (`a, b {}`) and must remain a delimiter. The fix is
local to the value-collection loop.

#### Old (CSSParser.swift:350-357)

```swift
if CSSParser.isShortHand(prop) {
    skipWhitespace()
    while i < chars.count && chars[i] != ";" && chars[i] != "}" {
        guard let t = try? word() else { break }
        tokens.append(t)
        skipWhitespace()
    }
}
```

#### New

```swift
if CSSParser.isShortHand(prop) {
    skipWhitespace()
    while i < chars.count && chars[i] != ";" && chars[i] != "}" {
        // Commas separate multiple values in shorthands like
        // `transition: transform 1s, opacity 2s`. word() stops at `,`
        // (it is not a word char), so consume it explicitly and keep
        // collecting. Without this, the loop would break on the comma
        // and every property after the first would be silently dropped.
        if chars[i] == "," {
            tokens.append(",")
            i += 1
            skipWhitespace()
            continue
        }
        guard let t = try? word() else { break }
        tokens.append(t)
        skipWhitespace()
    }
}
```

After this, `transition: transform 2s, opacity 2s;` produces
`tokens = ["transform", "2s", ",", "opacity", "2s"]`. `expand` returns `nil`
(no `transition` case), so `fullVal = tokens.joined(separator: " ")` =
`"transform 2s , opacity 2s"` (spaces around the comma). That string is
stored in `node.style["transition"]`.

#### Why the spaces around the comma are harmless

`parseTransition` (with Fix 9 applied) splits on `,` via `splitTopLevel`,
giving `["transform 2s ", " opacity 2s"]`. Fix 9's
`item.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")`
collapses each item to `"transform 2s"` and `"opacity 2s"` respectively.
`tokens[0]` is `"transform"` / `"opacity"` — exact matches for the
property-name comparisons in `diffStyles`. The extra spaces around the comma
never reach the token comparison.

#### Why not fix `word()` instead

`word()` is called by `parseSimpleSelector` (CSSParser.swift:403-421 via
:428), `parseCompoundSelector`, `mediaQuery`, and `pair`. In selector
parsing, `,` is the **group selector** delimiter (`a, b { … }` means "a or
b"). If `word()` included `,`, `parseSimpleSelector` would read `a,` as one
token and break selector grouping everywhere. The comma handling must stay
out of `word()` and live in the specific loops that need it. The shorthand
token loop is one such place.

#### Interaction with Fix 9

Fix 9 and Fix 10 are **both required** for multi-property `transition:`:

- Without Fix 10: CSSParser truncates the value to `"transform 2s"`.
  `parseTransition` never sees `opacity`. No opacity animation.
- Without Fix 9: CSSParser preserves the full value
  `"transform 2s , opacity 2s"`, but `parseTransition`'s `splitTopLevel(·,
  separator: " ")` produces `tokens[0] = "transform"` only by luck (the
  newline-indented case produces `"\n        transform"` and fails). For
  single-line multi-property CSS (`transition: a 1s, b 2s;`) Fix 9 is not
  strictly needed, but the proof CSS is multi-line, so Fix 9 is needed too.

Apply both. They are independent and commute.

#### Verification

After Fix 10 + Fix 9, the full chain works:

1. CSSParser parses `example13-transform-transition.css` →
   `node.style["transition"] = "transform 2s , opacity 2s"`.
2. `parseTransition` splits on `,` → two items → normalizes →
   `["transform": …, "opacity": …]`.
3. `diffStyles` matches both → creates `transform-x`, `transform-y`, and
   `opacity` `NumericAnimation`s.
4. `runAnimationFrame` fast path (Fix 1+2) ticks them. `paintVisualEffects`
   rebuilds a `Transform(children: [Blend])` reflecting both animated values.
5. `getLatest` (Fix 2 type-match) swaps both levels. Draw list updates. No
   raster.
6. Animation ends → Fix 6 bakes final value → Fix 7 clears latch.

---

## Bug 2 — scrolling during an animation must not raster

### Current state

`Tab.scrollDown` (Tab.swift:541-547):

```swift
public func scrollDown() {
    let maxY = max((document?.height ?? 0) + 2 * VSTEP - tabHeight, 0)
    scroll = min(scroll + SCROLL_STEP, maxY)
    if !checkInterestRegion() {
        browser?.applyScroll(scroll)
    }
}
```

`browser.applyScroll` (Browser.swift:323-327):

```swift
public func applyScroll(_ scroll: CGFloat) {
    activeTabScroll = scroll
    setNeedsDrawOnly()
    scheduleRasterAndDraw()
}
```

`setNeedsDrawOnly` sets only `needsDraw` (Browser.swift:313-315).
`scheduleRasterAndDraw` (Browser.swift:135-192) then runs with
`needsComposite == false` and `needsRaster == false`:

- `inputs.needsComposite ? computeComposite : previousLayes` → reuses layers
  (line 160-162). No composite.
- `inputs.needsDraw ? computePaintDrawList : nil` → rebuilds draw list
  (line 163-166). No raster.
- The actual scroll offset is applied in the view: `ToyStack.swift:48`
  `c.translateBy(x: 0, y: offset - app.activeTabScroll)`.

So **plain page scrolling already skips raster**. The exercise's scroll hint
("it requires setting fewer dirty flags in handle_down") is already
satisfied for the `scrollDown`/`scrollUp` path. Two leftover concerns:

### Concern 2a — `checkInterestRegion` triggers layout on region exit

`checkInterestRegion` (Tab.swift:621-630):

```swift
private func checkInterestRegion() -> Bool {
    let interestBottom = interestTop + 4 * HEIGHT
    if scroll < interestTop || scroll + tabHeight > interestBottom {
        interestTop = max(0, scroll - HEIGHT)
        setNeedsLayout()      // ← layout, then paint, then composite
        return true
    }
    return false
}
```

When the user scrolls *outside* the current interest region, this calls
`setNeedsLayout()`, which cascades into a full style→layout→paint→composite
cycle. That is by design — rasterising new content off-screen is the whole
point of the interest region. It is **not** a bug and the exercise does not
ask to remove it. Within the interest region (the common case during an
animation), `checkInterestRegion` returns false and we stay on the
`applyScroll` fast path.

### Concern 2b — `scrollElementDown` / `scrollElementUp` use `setNeedsRender`

`Tab.scrollElementDown` (Tab.swift:603-611) and `scrollElementUp`
(Tab.swift:613-619) call `setNeedsRender()`, which sets `needsStyle` and
`needsRender` (Tab.swift:879-882) → full `render()` → repaint → composite.
This is for `overflow: scroll` *elements*, not the page. The exercise's
scrolling requirement is about page scroll, so these can stay as-is for 13-3.
(If you later want element-scroll to be threaded too, that is a separate
exercise — it would require `ScrollEffect` to take a composited update like
Blend/Transform do.)

### Conclusion for Bug 2

No code change needed for scrolling. Verify by running the proof page (see
"Verification" below): once Bug 1 is fixed, press Down arrow during the
animation; `measure.start/stop("composite_raster_and_draw")` (Browser.swift:152,
178) will report only the draw-list rebuild, no raster.

---

## Bug 3 — `node.style = "…"` silently ignored

### Symptom

After applying Fix 1 + Fix 2, loading `exercise-13-3.html` showed **no
transition at all**. The div sat at its initial transform/opacity and never
moved.

### Root cause

The proof JS (`www/ch13/example13-transform-transition.js`) starts the
animation by assigning a whole style string:

```js
div.style =
  "background-color:lightblue;transform:translate(0px,0px);opacity:0.1";
```

But `Node.prototype.style` in `runtime.js` is defined with a **getter only**
that returns a `Proxy` (runtime.js:164-177):

```js
Object.defineProperty(Node.prototype, "style", {
  get: function () {
    var handle = this.handle;
    return new Proxy(
      {},
      {
        set: function (target, attr, value) {
          __styleSet__(handle, attr, value.toString());
          return true;
        },
      },
    );
  },
});
```

Two levels of "set" are easily confused here:

- The `Proxy`'s `set` trap handles **`node.style.prop = value`** (writing one
  property *on* the style object). It routes to `__styleSet__` →
  `JSRuntime.__styleSet__` (JSRuntime.swift:414-426), which writes
  `node.style[attr] = value` and calls `setNeedsRender()` + `render()`.
- The **property descriptor's** `set` would handle **`node.style = "string"`**
  (replacing the style object wholesale). There is no such `set`, so the
  assignment is a silent no-op in sloppy mode. The string never reaches Swift,
  `diffStyles` never sees a change, no `NumericAnimation` is created, and
  `runAnimationFrame` has nothing to animate.

`exercise-13-2` works because its JS uses
`box.setAttribute("style", "…")` (exercise-13-2.html JS line 91), which routes
through `_setAttribute` → `elt.attributes["style"] = value` → `setNeedsRender()`
(JSRuntime.swift:101-110). The inline-style string is then parsed by
`applyStyle` (DOMUtils.swift:142-148) during the next `render()`.

### Fix 3 — add a `set` to the `style` descriptor

Add a property-descriptor `set` that routes the whole-string form through the
same `_setAttribute` path as `setAttribute("style", …)`. No new Swift bridge
needed — `_setAttribute` already exists and already calls `setNeedsRender()`.

#### File touched

| File | Change | Why |
|------|--------|-----|
| `Sources/Engine/Resources/runtime.js` | Add `set` to the `Node.prototype.style` descriptor | Make `node.style = "…"` route to `_setAttribute(handle, "style", …)` instead of no-op'ing |

No Swift change. `_setAttribute` (JSRuntime.swift:101-110) already does
`elt.attributes["style"] = value` + `setNeedsRender()`, and `applyStyle`
(DOMUtils.swift:142-148) already parses the inline-style string via
`CSSParser(inlineStyle).body()`.

#### Old (runtime.js:163-177)

```js
// CSS style property setter - bridges node.style.prop = value to Swift
Object.defineProperty(Node.prototype, "style", {
  get: function () {
    var handle = this.handle;
    return new Proxy(
      {},
      {
        set: function (target, attr, value) {
          __styleSet__(handle, attr, value.toString());
          return true;
        },
      },
    );
  },
});
```

#### New

```js
// CSS style property - bridges both node.style.prop = value and
// node.style = "prop:val;…" to Swift.
Object.defineProperty(Node.prototype, "style", {
  get: function () {
    var handle = this.handle;
    return new Proxy(
      {},
      {
        set: function (target, attr, value) {
          __styleSet__(handle, attr, value.toString());
          return true;
        },
      },
    );
  },
  set: function (value) {
    // Whole-string form: same path as setAttribute("style", …).
    // _setAttribute writes attributes["style"] and calls setNeedsRender();
    // applyStyle then parses the string during render().
    _setAttribute(this.handle, "style", value.toString());
  },
});
```

The getter is unchanged, so `node.style.prop = value` still works exactly as
before. The new `set` only fires for `node.style = <not a function call>` —
i.e. replacing the style object wholesale. The two paths do not collide
because the descriptor `set` runs *instead of* the getter when you assign to
the property itself.

#### Why a full `render()` here is correct

`_setAttribute` → `setNeedsRender()` triggers a full style→layout→paint pass
(Tab.swift:879-882). That is the **start** of the animation, not a per-frame
cost. `render()` runs `diffStyles` (DOMUtils.swift:320-355), which compares the
old inline style against the new one and creates the `transform-x`,
`transform-y`, and `opacity` `NumericAnimation`s on the node. From then on,
`runAnimationFrame` ticks those animations on the composited fast path (Fix 1)
— no raster per frame. So Bug 3 is about getting the animation to *start*;
Fix 1 is about keeping it *raster-free* while it runs. They are complementary.

#### Equivalence check

After this fix, these two are equivalent for starting a transition:

```js
div.style = "transform: translate(0px,0px); opacity: 0.1";
// same as
div.setAttribute("style", "transform: translate(0px,0px); opacity: 0.1");
```

Both write `attributes["style"]`, both trigger `setNeedsRender()`, both let
`diffStyles` see the change. The per-property form remains separate and
incremental:

```js
div.style.transform = "translate(0px,0px)";  // → __styleSet__, no attribute parse
```

This writes `node.style["transform"]` directly (JSRuntime.swift:421) and calls
`setNeedsRender()`. It does **not** update `attributes["style"]`, so a
subsequent `render()` would re-derive `node.style` from the (stale) attribute
and clobber the change. That is a pre-existing limitation of the per-property
form, not something Bug 3 introduces. For transitions that must survive a
re-render, prefer the whole-string form (`div.style = "…"`) or
`setAttribute("style", "…")` — both of which now work.

---

## Bug 4 — `document.querySelectorAll` returns array of `undefined`

### Symptom

After Fix 1, Fix 2, and Fix 3, the proof page still showed **no transition**.
Build was clean, `runtime.js` had the `set` on `Node.prototype.style`, but
nothing animated.

### Root cause

The proof JS gets its div via:

```js
var div = document.querySelectorAll("div")[0];
```

`document.querySelectorAll` is defined in `runtime.js:10-15`:

```js
document = {
  querySelectorAll: function (s) {
    var handles = _querySelectorAll(s);
    return handles.map(function (h) {
      return Node(h);      // ← BUG: missing `new`
    });
  },
  // …
};
```

`Node` is a constructor (runtime.js:37-39):

```js
function Node(handle) {
  this.handle = handle;
}
```

Calling a constructor **without `new`** runs it with `this` bound to the
global object (in sloppy mode) and returns `undefined`. So the `.map`
produces `[undefined, undefined, …]`. `querySelectorAll("div")[0]` is
`undefined`. The very next line, `div.style = "…"`, throws
`TypeError: Cannot set property 'style' of undefined`. `JSContext`'s
exception handler (JSRuntime.swift:22-24) prints it and swallows it, so the
page looks frozen with no visible error.

Compare the two sibling methods right below it — both correct:

```js
getElementById: function (id) {
  // …
  return new Node(handle);     // line 20 — correct
},
createElement: function (tag) {
  var handle = _createElement(tag);
  return new Node(handle);     // line 24 — correct
},
```

Only `querySelectorAll`'s map callback forgot `new`. That is why
`exercise-13-2` (which uses `getElementById`) works, while `exercise-13-3`
(which uses `querySelectorAll`) does not.

### Fix 4 — add `new` to the `querySelectorAll` map callback

#### File touched

| File | Change | Why |
|------|--------|-----|
| `Sources/Engine/Resources/runtime.js` | `return Node(h);` → `return new Node(h);` (line 13) | Construct a `Node` instead of returning `undefined` |

No Swift change. `_querySelectorAll` (JSRuntime.swift:63-74) already returns
the correct handle array; the bug is purely in the JS wrapper.

#### Old (runtime.js:10-15)

```js
querySelectorAll: function (s) {
  var handles = _querySelectorAll(s);
  return handles.map(function (h) {
    return Node(h);
  });
},
```

#### New

```js
querySelectorAll: function (s) {
  var handles = _querySelectorAll(s);
  return handles.map(function (h) {
    return new Node(h);
  });
},
```

One word added. After this, `document.querySelectorAll("div")[0]` is a real
`Node`, `div.style = "…"` routes through Fix 3's `set` → `_setAttribute` →
`setNeedsRender()` → `render()` → `diffStyles` creates the `transform-x`,
`transform-y`, and `opacity` animations → Fix 1 + Fix 2 run them on the
composited fast path.

#### Why this hid for so long

The four bugs stack:

1. Bug 4 (`querySelectorAll`) — `div` is `undefined`, JS throws before
   touching style. **First thing to break.**
2. Bug 3 (`node.style = "…"`) — even with a real `Node`, the whole-string
   assignment no-op'd. Fixed so the assignment reaches Swift.
3. Bug 1 (`runAnimationFrame` transform branch) — even with style changing,
   each animation frame forced a full composite+raster. Fixed so it uses the
   composited fast path.
4. Bug 2 (`getLatest` Blend-only) — even on the fast path, `Transform` was
   never swapped. Fixed so the new transform actually shows.

Fix 3 alone is not enough because Bug 4 kills the JS before Fix 3's code path
runs. Fix 4 alone is not enough because Bug 3 then swallows the assignment.
All four are required for the proof to animate. Fix in order 4 → 3 → 1 → 2
(or any order, since they are independent), then rebuild.

---

## Why this works — the data flow after the fix

Animation frame:

```
JS RAF callback mutates element.style.transform / .opacity
        │
        ▼
Tab.runAnimationFrame
   ├─ node.style["transform"] = "translate(x,y)"
   ├─ effect = paintVisualEffects(node, [], rect).first   ← fresh Transform
   ├─ compositedUpdates[node] = effect                    ← keyed by DOMNode
   └─ (no needsPaint, no needsCompositeForPaint)
        │
        ▼  CommitData(compositedUpdates: non-nil)
Browser.commit
   └─ setNeedsDrawOnly()                                  ← needsDraw = true only
        │
        ▼
rasterThread.submit
   ├─ needsComposite? NO  → reuse previousLayes           ← no composite
   └─ needsDraw? YES      → computePaintDrawList          ← rebuild draw list
        │
        ▼
computePaintDrawList
   for each CompositedLayer:
     parent = layer.displayItems[0].parentEffect          ← the OLD Transform
     while parent:
       newParent = getLatest(parent, compositedUpdates)   ← the NEW Transform
       cloned = newParent.clone(child: currentEffect)     ← swap in layer content
       parent = parent.parent
        │
        ▼
drawList = [Transform(children: [Blend(children: [DrawCompositedLayer])])]
        │
        ▼  back on main
ToyStack.body.Canvas
   for item in drawList:
     ve.execute(context:)                                  ← applies translate + opacity
```

No `CompositedLayer.raster` call (CompositedLayer.swift:36-44) anywhere in
this path. The only thing recomputed per frame is the draw list — a cheap
tree of effect wrappers, no pixel work.

---

## Verification

Build then load the proof page:

```text
swift build
# run ToyStack, open file://…/www/ch13/exercise-13-3.html
```

Expected behaviour:

1. On load, the two `<div>`s sit at their initial transforms. Page is tall
   enough to scroll (50+ `<br>` lines).
2. The JS calls `requestAnimationFrame` and mutates `transform` and `opacity`
   on the first div (see file below). The div should slide and fade
   simultaneously over ~1s.
3. While the animation is running, press Down arrow. The page should scroll
   smoothly. The animation should continue uninterrupted.
4. Console / frame-time readout should show no raster spike on scroll — only
   the per-frame draw-list rebuild. (If you have the `measure` instrumentation
   wired to a label, `composite_raster_and_draw` stays near the animation-only
   cost; a raster would be visibly larger.)

Negative test: revert Bug 1's `Tab.swift` change only. Animation still plays
(via the old `needsCompositeForPaint` path) but each frame rasterises; scroll
during animation also rasterises because the pending composite forces it.
Restore the fix to confirm the difference.

---

## Missing proof files

`www/ch13/exercise-13-3.html` (which you wrote) links to:

```html
<link rel="stylesheet" href="example13-transform-transition.css">
<script src="example13-transform-transition.js"></script>
```

Neither exists in `www/ch13/` yet. Create them so the proof runs.

### `www/ch13/example13-transform-transition.css`

```css
body {
    font-family: monospace;
    font-size: 14px;
}

#mover {
    width: 120px;
    height: 120px;
    background-color: lightblue;
    /* initial transform set inline in the HTML; JS swaps it so diffStyles
       sees a real change and starts the transition. */
    transition:
        transform 1s linear,
        opacity   1s linear;
}

#static {
    width: 120px;
    height: 120px;
    background-color: lightgreen;
}
```

### `www/ch13/example13-transform-transition.js`

```js
// Wait one RAF tick so ToyStack has recorded the initial inline
// transform/opacity, then swap them. diffStyles sees the change and
// creates transform-x, transform-y, and opacity animations that all
// run together on the composited fast path.
window.addEventListener("load", function () {
    requestAnimationFrame(function () {
        var mover = document.getElementById("mover");
        mover.setAttribute(
            "style",
            "transform: translate(200px, 100px); opacity: 0.3;",
        );
    });
});
```

The HTML already has the tall `<br>` stack (lines 3-58) so the page scrolls,
`scroll-behavior: smooth` on `<body>` (line 2), the `#mover` div with initial
`transform: translate(50px,50px); opacity: 0.999` (line 7), and a `#static`
div (line 8). The JS animates `#mover` to `translate(200px,100px)` and
`opacity: 0.3` simultaneously — exactly the "simultaneous transform and
opacity animation" the exercise asks for.

---

## Summary of code changes

| # | File:lines | Change | Effect |
|---|------------|--------|--------|
| 1 | Tab.swift:411-424 | Merge transform + opacity into one branch; rebuild effect via `paintVisualEffects`; drop `needsCompositeForPaint` and `needsPaint` | Transform animation uses composited fast path; opacity fast path actually works for the first time |
| 2 | Browser.swift:243-252 | Rewrite `getLatest` to match by **type within the updated subtree** (not blindly by node) | Both `Blend` and `Transform` levels of the same node get swapped correctly; preserves the two-level `Transform→Blend` shape |
| 3 | runtime.js:163-180 | Add `set` to the `Node.prototype.style` descriptor routing to `_setAttribute(handle, "style", …)` | `node.style = "…"` starts transitions instead of silently no-op'ing |
| 4 | runtime.js:13 | `return Node(h);` → `return new Node(h);` | `querySelectorAll` returns real `Node`s instead of `[undefined, …]` |
| 6 | Tab.swift:433-435 | In the `else` (animation-finished) branch, set `needsCompositeForPaint = true` and `needsPaint = true` | Bake final animated value into `previousLayes` so the box does not snap back when the animation ends |
| 7 | Tab.swift:464 | After `compositedUpdates = [:]`, add `needsCompositeForPaint = false` | Clear the latch so the next animation can use the composited fast path instead of being forced through full-composite every frame |
| 8 | PaintCommand.swift:17-30, 56-69 | Add `lightgreen` and `steelblue` to `cssColorToRGB` and `Color(cssName:)` | These named colors render correctly instead of falling through to black |
| 9 | DOMUtils.swift:300-318 | In `parseTransition`, collapse whitespace runs (incl. newlines) before tokenizing | Multi-line `transition:` tokenizes to `["transform", "2s"]` not `["\n        transform", "2s"]` |
| 10 | CSSParser.swift:350-357 | In the shorthand token loop, consume `,` as a token and continue instead of breaking | Preserve comma-separated values so `transition: a 1s, b 2s` is not truncated to `a 1s` at parse time |

No Swift change for #3 or #4. No new files under `Sources/`. The two files
under `www/ch13/` are proof fixtures, not engine code.

## Ordering

1. **runtime.js line 13** — add `new` to `querySelectorAll` map. Without this,
   the proof JS throws before anything else runs. Rebuild.
2. **runtime.js `Node.prototype.style`** — add the `set` so `div.style = "…"`
   reaches Swift. Rebuild.
3. **Browser.swift `getLatest`** — type-match rewrite. Build clean.
4. **Tab.swift `runAnimationFrame` transform/opacity branch** — the main
   composited-fast-path fix. Build clean.
5. **Tab.swift `runAnimationFrame` else (animation-finished) branch** —
   Fix 6, bake final value into layers. Build clean.
6. **Tab.swift `runAnimationFrame` end-of-function reset** —
   Fix 7, clear `needsCompositeForPaint` after consume. Build clean.
7. **CSSParser.swift shorthand token loop** — Fix 10, comma-aware
   collection so multi-property `transition:` is not truncated. Build clean.
8. **DOMUtils.swift `parseTransition`** — Fix 9, whitespace collapse so
   multi-line CSS tokenizes. Build clean.
9. **PaintCommand.swift color maps** — Fix 8, add `lightgreen`/`steelblue`.
   Build clean.
10. **Create `example13-transform-transition.css` + `.js`** — proof fixtures.
11. **Run the proof page.** Confirm animation + simultaneous scroll without
    raster.

> Note on step 3 vs the earlier version: the original "drop the Blend-only
> guard" fix is **wrong** and must be replaced with the type-match version.
> If you already applied the naive `?? effect` form, revert it to the
> type-match form in step 3 before testing — otherwise 13-2 and 13-3 will
> flicker or freeze as described in "Why the naive fix is wrong" above.
>
> Fix 6 and Fix 7 are a pair: 6 sets the flag at animation end, 7 clears it
> after the frame commits. Applying 6 without 7 causes the latch bug
> (every animation after the first snaps instead of animating). Applying 7
> without 6 causes the snap-back bug (box returns to start when animation
> finishes). Both are required.
>
> Fix 9 and Fix 10 are a pair: 10 preserves the comma-separated value at
> parse time, 9 tokenizes it correctly in `parseTransition`. Without 10,
> the value is truncated before `parseTransition` ever sees it. Without 9,
> multi-line CSS produces malformed tokens. Both are required for the
> proof's multi-line, multi-property `transition:` rule.

---

## Bug 11 — `__styleSet__` calls `render()` immediately, clobbering the style mid-frame

### Symptom

After applying Fixes 1-10, `exercise-13-2` animates correctly, but
`exercise-13-3` shows **no transition at all**. The div sits at its initial
position and never moves. The `setTimeout` callback never fires a second
time.

### Diagnostic evidence

Adding `print` statements to `Tab.runAnimationFrame` and `Tab.render` reveals:

```
RAF: needsStyle=true needsLayout=false needsRender=true
RAF: node.animations count=0
RAF: needsStyle=true needsLayout=false needsRender=true
RAF: node.animations count=0
RENDER: div oldTransform=nil newTransform=translate(50px, 50px) oldOpacity=nil newOpacity=0.999 transition=transform 2s , opacity 2s animations=0
RENDER: div oldTransform=nil newTransform=translate(0px, 0px) oldOpacity=nil newOpacity=nil transition=transform 2s , opacity 2s animations=0
RAF: needsComposite=true needsCompositeForPaint=false updates=nil
RAF: needsStyle=false needsLayout=false needsRender=false
RAF: node.animations count=0
… (repeats forever, animations=0)
```

Two key observations:

1. **`oldOpacity=nil` on the second RENDER line.** The first `render()` set
   `node.style["opacity"] = "0.999"`, but by the time the second `render()`
   runs, the old style has lost `opacity`. This means `node.style` was reset
   **between** the two renders — `applyStyle` ran an extra time and clobbered
   the previously-computed style.

2. **`newOpacity=nil` on the second RENDER line.** The JS sets
   `div.style = "background-color:lightblue;transform:translate(0px,0px);opacity:0.1"`,
   but `opacity` is missing from the new style. Only `transform` survived.

3. **`animations=0` on both RENDER lines.** Because `oldOpacity` is `nil`,
   `diffStyles`'s `guard let oldVal = oldStyle[property]` fails for `opacity`.
   And because `oldTransform` is `nil`, the same guard fails for `transform`.
   **No `NumericAnimation` is ever created.** The transition never starts.

### Root cause

`Fix 3` added a `set` to the `Node.prototype.style` descriptor in
`runtime.js`:

```js
set: function (value) {
    _setAttribute(this.handle, "style", value.toString());
},
```

This routes `div.style = "..."` to `_setAttribute`, which calls
`setNeedsRender()`. So far so good — this is the correct path.

But the JS in `exercise-13-3` does **not** use `div.style = "..."` to set
individual properties. It assigns the **whole style string** at once. The
`set` trap fires once, calls `_setAttribute`, and the full string is parsed
by `applyStyle` during the next `render()`.

However, `exercise-13-3`'s JS also has this line at the top of the script:

```js
var div = document.querySelectorAll("div")[0];
```

This runs during script execution. At that point, `div` is a `Node` object.
Later, `go()` does:

```js
div.style = "background-color:lightblue;transform:translate(0px,0px);opacity:0.1";
```

The `set` trap fires, calls `_setAttribute(handle, "style", value)`. But
`_setAttribute` (JSRuntime.swift:103-108) does:

```swift
elt.attributes["style"] = value
self.tab?.setNeedsRender()
```

`setNeedsRender()` sets `needsStyle = true, needsRender = true` and calls
`browser?.setNeedsAnimationFrame(self)`. This is correct.

But the **old** `__styleSet__` bridge (JSRuntime.swift:414-426) — which is
called by the Proxy's `set` trap for `node.style.prop = value` — does
something **extra**:

```swift
node.style[attr] = value
self.tab?.setNeedsRender()
self.tab?.render()    // ← calls render() IMMEDIATELY
```

`__styleSet__` calls `render()` **synchronously**, right there in the JS
callback. This is the problem.

When `div.style = "..."` fires the descriptor's `set`, it calls
`_setAttribute` → `setNeedsRender()` (no immediate render). Good. But if
**any** other code path calls `__styleSet__` (the Proxy trap) during the same
frame, that `__styleSet__` calls `render()` immediately, which runs
`applyStyle` and resets `node.style` from `attributes["style"]`.

The sequence in 13-3 is:

1. Script loads. `div = document.querySelectorAll("div")[0]`.
2. `requestAnimationFrame(frame)` schedules a `BrowserTask`.
3. `execScripts` finishes. `setNeedsRender()` is called (Tab.swift:275).
4. `BrowserTask` runs `runAnimationFrame`:
   - `__runRAFHandlers()` → `frame()`. `count==0` → `count=1`,
     `requestAnimationFrame(frame)`.
   - `needsRender` true → `render()` runs. First render: `applyStyle` sets
     `node.style["opacity"] = "0.999"` from the initial inline style.
     `diffStyles` sees `oldStyle = [:]` (first render), so no animations.
5. Second `BrowserTask` runs `runAnimationFrame`:
   - `__runRAFHandlers()` → `frame()`. `count==1` → `go()`.
   - `go()` sets `div.style = "...translate(0px,0px);opacity:0.1"`.
   - The descriptor `set` fires → `_setAttribute` →
     `elt.attributes["style"] = "..."` → `setNeedsRender()`.
   - Back in `runAnimationFrame`: `needsRender` true → `render()` runs.
   - `render()` → `applyStyle` → captures `oldStyles` (which has
     `opacity=0.999` from step 4) → resets `node.style = [:]` → applies CSS
     rules → applies inline style from `attributes["style"]` (the new one).
   - **But wait** — between capturing `oldStyles` and applying the new inline
     style, `applyStyle` does `node.style = [:]` (DOMUtils.swift:122). Then it
     re-applies inherited properties, CSS rules, and inline style. The
     `oldStyles` capture (Tab.swift:340-343) happens **before** `applyStyle`,
     so `old` should have the values from the previous render.

The actual problem is more subtle. The log shows `oldOpacity=nil` and
`oldTransform=nil` on the **second** RENDER line. This means the `oldStyles`
capture did NOT find the values that the first render set. Why?

Because **`__styleSet__` called `render()` synchronously** at some point
between the two `runAnimationFrame` calls, and that extra `render()` ran
`applyStyle` which reset `node.style` — but then `diffStyles` found no
changes (because the inline style hadn't changed yet), so no animations were
created. But `node.style` was left in a state where `opacity` and `transform`
were missing (because `applyStyle` re-derived them from the inline style,
which may not have had `opacity` at that point).

### The real trigger: `__styleSet__` is called by the Proxy trap during `go()`

When `go()` does `div.style = "..."`, the descriptor `set` fires. But
`JavaScriptCore` may **also** invoke the Proxy's `set` trap as part of the
property lookup chain. The Proxy is returned by the `get` trap. If the `get`
trap runs first (to retrieve the style object), and then the `set` trap runs
on the Proxy... no, that's not how descriptors work.

The actual issue: `__styleSet__` calls `render()` **immediately**
(JSRuntime.swift:423). This `render()` runs `applyStyle`, which resets
`node.style` from `attributes["style"]`. If `__styleSet__` is called at any
point during a frame, it triggers an **unscheduled render** that clobbers the
current `node.style`.

In 13-2, `setAttribute("style", ...)` is used, which calls `_setAttribute`
(No immediate `render()`). In 13-3, `div.style = "..."` calls `_setAttribute`
via the descriptor `set` (No immediate `render()`). But if the Proxy's `set`
trap is **also** triggered (e.g., by `div.style.opacity = ...` elsewhere, or
by the JS engine's internal bookkeeping), `__styleSet__` runs and calls
`render()` immediately.

### Fix 11 — remove the immediate `render()` call from `__styleSet__`

#### File touched

| File | Change | Why |
|------|--------|-----|
| `Sources/Engine/JSRuntime.swift` | In `__styleSet__` (line 423), remove the `self.tab?.render()` call | Let `setNeedsRender()` schedule the render on the next animation frame, same as `_setAttribute` does. The immediate `render()` clobbers `node.style` mid-frame and breaks `diffStyles` |

#### Old (JSRuntime.swift:414-426)

```swift
// __styleSet__ - sets a CSS property on a node from JS, triggers re-render
jsContext.setObject(
    {
        [weak self] (handle: Int, attr: String, value: String) in
        guard let self = self, let node = self.handleToNode[handle] else { return }
        Task {
            @MainActor in
            node.style[attr] = value
            self.tab?.setNeedsRender()
            self.tab?.render()
        }
    } as @convention(block) (Int, String, String) -> Void,
    forKeyedSubscript: "__styleSet__" as NSString)
```

#### New

```swift
// __styleSet__ - sets a CSS property on a node from JS, triggers re-render
jsContext.setObject(
    {
        [weak self] (handle: Int, attr: String, value: String) in
        guard let self = self, let node = self.handleToNode[handle] else { return }
        Task {
            @MainActor in
            node.style[attr] = value
            self.tab?.setNeedsRender()
        }
    } as @convention(block) (Int, String, String) -> Void,
    forKeyedSubscript: "__styleSet__" as NSString)
```

One line removed. `setNeedsRender()` (Tab.swift:884-888) already sets
`needsStyle = true, needsRender = true` and calls
`browser?.setNeedsAnimationFrame(self)`. The render will happen on the next
`runAnimationFrame` tick, exactly like `_setAttribute` does.

#### Why this is safe

`setNeedsRender()` already schedules the render. The immediate `render()` call
was redundant — it just ran the render **now** instead of on the next frame.
But running it immediately is dangerous because:

1. It runs `applyStyle`, which resets `node.style = [:]` and rebuilds from
   `attributes["style"]`. Any style values written by the animation fast path
   (which writes directly to `node.style`, not to `attributes`) are lost.
2. It runs `diffStyles`, which captures `oldStyles` from the current
   `node.style`. If `node.style` was just clobbered by `applyStyle`, the
   `oldStyles` are wrong, and `diffStyles` fails to create animations.
3. It can fire **between** `runAnimationFrame` calls, creating an extra
   render that the frame loop doesn't know about.

`_setAttribute` (the path used by `setAttribute("style", ...)` and the
descriptor `set`) does **not** call `render()` immediately. It only calls
`setNeedsRender()`. This is the correct behavior. `__styleSet__` should
match.

#### Why 13-2 works but 13-3 doesn't

13-2 uses `box.setAttribute("style", "...")` which routes through
`_setAttribute` → `setNeedsRender()` (no immediate render). The style change
is processed cleanly on the next `runAnimationFrame`.

13-3 uses `div.style = "..."` which routes through the descriptor `set` →
`_setAttribute` → `setNeedsRender()` (no immediate render). This should also
work. But the Proxy's `set` trap (`__styleSet__`) may be triggered by the JS
engine when evaluating `div.style = "..."` if the engine first calls the
`get` trap (returning a Proxy) and then tries to set properties on it. If
that happens, `__styleSet__` runs `render()` immediately, clobbering
`node.style`.

After Fix 11, `__styleSet__` no longer calls `render()`. Both paths
(`_setAttribute` and `__styleSet__`) use only `setNeedsRender()`, so the
render happens exactly once, on the next `runAnimationFrame`, with the
correct `oldStyles` capture.

#### Verification

After Fix 11, the diagnostic logs should show:

```
RENDER: div oldTransform=translate(50px, 50px) newTransform=translate(0px, 0px) oldOpacity=0.999 newOpacity=0.1 transition=transform 2s , opacity 2s animations=3
```

`oldTransform` and `oldOpacity` are no longer `nil` (because no extra
`render()` clobbered them). `animations=3` (transform-x, transform-y,
opacity). The fast path then ticks them, and the div animates.
