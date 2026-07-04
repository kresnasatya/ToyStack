# Plan: Exercise 13-12 — Opacity plus draw

## Goal

When a composited layer sits inside a `Blend` with opacity, the browser should
draw the layer's cached image **once**, with the opacity applied during that
single draw — instead of first drawing the image into a temporary buffer and
then merging that buffer into the screen with opacity.

Real browsers do exactly this: an element that only fades (opacity animation)
gets its raster image drawn straight to the screen with an alpha value on the
draw call. No extra buffer, no extra copy per frame.

## How the book's version maps to ToyStack

The book uses Skia. ToyStack uses SwiftUI's `GraphicsContext`. The pieces line
up like this:

| Book (Skia)                              | ToyStack (SwiftUI)                                   |
| ---------------------------------------- | ---------------------------------------------------- |
| `canvas.saveLayer(paint)` — temp buffer  | `context.drawLayer { ... }` (see BlurFilter.swift:28) |
| `surface.draw(canvas, paint_with_alpha)` | `context.draw(Image(...))` with `context.opacity` set |
| `DrawCompositedLayer`                    | `DrawCompositedLayer` (PaintCommand.swift:194)        |

## Where things stand today

`Blend.execute` at Sources/Engine/Blend.swift:25-38 does **not** create a
temporary buffer at all. It copies the context, sets `opacity` on the copy,
and executes each child. In SwiftUI, `context.opacity` applies to **each draw
operation separately**, not to the group as a whole.

Two consequences:

1. **Correctness gap.** If a Blend holds two overlapping children, each child
   is faded separately, so the overlap area shows both — a real browser fades
   the group as one unit. The correct tool is `context.drawLayer`, which is
   the temporary buffer the exercise talks about. BlurFilter.swift:27-39
   already uses this pattern.

2. **Once we fix #1, the exercise's problem appears.** A composited layer
   inside a Blend would then be: cached image → drawn into the `drawLayer`
   buffer (copy 1) → buffer merged into the screen with opacity (copy 2).

So the exercise here has two halves: first make Blend a *real* layer, then
add the fast path that skips the layer when it isn't needed.

Relevant facts for the fast path:

- After compositing, a cloned `Blend` in the draw list holds
  `DrawCompositedLayer` children (built in `computePaintDrawList`,
  Browser.swift:293-338). It starts with exactly one child
  (Browser.swift:301+313) and only gains more when several composited layers
  share the same effect (Browser.swift:307).
- A `DrawCompositedLayer` has a `cachedImage` only when the layer has 3+
  display items (`needsTexture`, CompositedLayer.swift:9-11 — exercise 13-8).
  Short lists fall back to executing raw commands (PaintCommand.swift:208-212).
- `Blend` needs a layer at all only when `opacity < 1.0 || blendMode != nil`
  — the same condition as `needsCompositing` at Blend.swift:22.

## Design decision: where does the fast path live?

- **Option A (recommended): inside `Blend.execute`.** Check the children at
  draw time; if the only child is a `DrawCompositedLayer` with a cached
  image, draw it directly with opacity on the context. This is what the book
  intends, and it is one small edit in one file. Trade-off: the check runs on
  every draw (a cheap type check and count).
- **Option B: inside `computePaintDrawList`.** When building the draw list,
  detect Blend-with-single-layer and emit a special "draw image with alpha"
  command instead of the Blend. Trade-off: the decision is made before
  rastering, but `cachedImage` doesn't exist yet at that point (raster runs
  later), so the command would still need a draw-time fallback — more code,
  no extra benefit.

Go with Option A.

## Files that change

| File                            | Who edits | Why                                            |
| ------------------------------- | --------- | ---------------------------------------------- |
| Sources/Engine/Blend.swift      | You       | Rewrite `execute`: real layer + fast path      |
| www/ch13/exercise-13-12.html    | Claude    | Proof page (created)                           |
| www/ch13/exercise-13-12.css     | Claude    | Styles for proof page (created)                |
| www/ch13/exercise-13-12.js      | Claude    | Opacity animation to exercise the fast path    |

No other Swift file changes. `DrawCompositedLayer`, `CompositedLayer`, and
`computePaintDrawList` stay as they are.

## The code change

### Old — Sources/Engine/Blend.swift:25-38

```swift
public override func execute(context: inout GraphicsContext) {
    var layerContext = context
    layerContext.opacity = opacity
    if let mode = blendMode {
        layerContext.blendMode = mode
    }
    for child in children {
        if let ve = child as? VisualEffect {
            ve.execute(context: &layerContext)
        } else if let pc = child as? PaintCommand {
            pc.execute(scroll: 0, context: &layerContext)
        }
    }
}
```

### New — replaces the whole method

```swift
public override func execute(context: inout GraphicsContext) {
    // No opacity and no blend mode: nothing to isolate, draw children
    // straight into the target.
    guard opacity < 1.0 || blendMode != nil else {
        for child in children {
            if let ve = child as? VisualEffect {
                ve.execute(context: &context)
            } else if let pc = child as? PaintCommand {
                pc.execute(scroll: 0, context: &context)
            }
        }
        return
    }

    var layerContext = context
    layerContext.opacity = opacity
    if let mode = blendMode {
        layerContext.blendMode = mode
    }

    // Exercise 13-12 fast path: the only child is a composited layer that
    // already has a raster image. Drawing that image is a single operation,
    // so the context's opacity fades it as one unit — no temporary buffer.
    if children.count == 1,
        let layerCmd = children[0] as? DrawCompositedLayer,
        layerCmd.layer.cachedImage != nil
    {
        layerCmd.execute(scroll: 0, context: &layerContext)
        return
    }

    // General case: draw children into a temporary buffer, then merge the
    // whole buffer into the target with opacity and blend mode applied once.
    layerContext.drawLayer { inner in
        var innerContext = inner
        for child in self.children {
            if let ve = child as? VisualEffect {
                ve.execute(context: &innerContext)
            } else if let pc = child as? PaintCommand {
                pc.execute(scroll: 0, context: &innerContext)
            }
        }
    }
}
```

Notes on the three branches:

1. **Pass-through.** `opacity == 1.0` and no blend mode — same visible result
   as before, one less context copy. (The border-radius clip Blend built at
   DOMUtils.swift:510 has `blendMode = .normal`, so it takes a layer branch,
   not this one — same as its current `needsCompositing == true` status.)
2. **Fast path.** One child, it's a `DrawCompositedLayer`, and the image
   exists. `layerCmd.execute` (PaintCommand.swift:204-214) then does exactly
   one `context.draw(Image...)`, and `layerContext.opacity` is applied during
   that draw. This is the exercise's optimization.
3. **Temporary buffer.** Everything else: several layers under one Blend, a
   nested effect (e.g. a Transform clone) as the child, or a short display
   list with no cached image. `drawLayer` fades the group as one unit —
   this *fixes* the overlap fading bug the old per-child code had.

## Ordered steps (project builds after each)

1. **Step 1 — real layer.** Replace `Blend.execute` with the new version but
   *without* the fast-path `if` (branches 1 and 3 only). Build, run, load
   `http://localhost:3000/exercise-13-12`. Everything should render; the
   nested box (green/steelblue) should fade as one unit.
2. **Step 2 — fast path.** Add the fast-path `if` block. Build, run, same
   page. Nothing should change visually — the gold and lightblue boxes now
   take the one-draw route.
3. **Step 3 — prove it.** Add two temporary prints, run once, then delete
   them:
   - first line inside the fast-path block:
     `print("[blend] fast path: one draw, opacity \(opacity)")`
   - first line inside the `drawLayer` closure:
     `print("[blend] slow path: temporary buffer")`

## What the proof page should show

`www/ch13/exercise-13-12.html` (load via `http://localhost:3000/exercise-13-12`):

- **Gold box (animated).** JS fades it between 0.9 and 0.2 with a
  `transition: opacity 2s`. It has enough content for a texture, so while it
  fades you should see a stream of `[blend] fast path` lines — one per frame.
  This is the case that matters in real browsers.
- **Lightblue box.** Static `opacity: 0.5`, 4+ display items → cached image →
  one `[blend] fast path` line per draw.
- **Salmon box.** Static `opacity: 0.5`, only 2 display items (background +
  one short text) → no texture (exercise 13-8 rule) → `[blend] slow path`.
- **Green box with steelblue inner box.** The inner box has a `transform`, so
  it becomes its own composited layer nested inside the Blend → `[blend] slow
  path`. The inner box overlaps the outer text; with the `drawLayer` fix the
  whole group fades evenly instead of the overlap looking denser.

## Colors

Only colors already in `cssColorToRGB` (PaintCommand.swift:18-36) are used:
gold, lightblue, salmon, lightgreen, steelblue, whitesmoke. No new colors.

## Follow-up: why the fast path did not fire at first

The Blend.swift change was correct. The proof page was wrong.

Every block element gets its own `Transform` + `Blend` wrapper in
`paintVisualEffects` (DOMUtils.swift:500-535, called per block at
DOMUtils.swift:262-263) — even an `h1` or `p` with opacity 1. A paint
command's `parentEffect` is its *nearest* wrapper, and `canMerge`
(CompositedLayer.swift:17-24) only merges commands with the *same*
`parentEffect`. So with this structure:

```
div.anim (opacity 0.9)  →  Blend(0.9)
├── background rect         parentEffect = div's Blend   → layer A (1 item)
├── h1 text                 parentEffect = h1's Blend    → layer B
└── p  text                 parentEffect = p's Blend     → layer C…
```

the gold box splits into several small layers. In `computePaintDrawList`
(Browser.swift:293-338) the gold Blend clone then holds *multiple*
children, and each child is a Transform/Blend clone — never a lone
`DrawCompositedLayer`. The fast-path condition (`children.count == 1`
and child is `DrawCompositedLayer` with a cached image) can never hold,
so every opacity Blend took the slow path.

Fix: no Swift change. The proof page now puts bare text directly inside
the gold and lightblue divs (no `h1`/`p`). Then background + text lines
all have the div's Blend as `parentEffect`, merge into one layer with
3+ display items, get a cached image, and the Blend clone has exactly
one `DrawCompositedLayer` child → fast path.

Expected console output per frame after the page fix:

- gold, lightblue → `[blend] fast path`
- salmon (2 items, no texture) → `[blend] slow path`
- green (nested transformed layer, 2+ children) → `[blend] slow path`
