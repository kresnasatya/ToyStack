# Display list refactor: items 1 and 2

Implementation plan for **item 1 (draw commands → `DisplayOp`)** and **item 2 (paint output → flat buffer)** from [oop-findings.md](./oop-findings.md). Ordering rationale lives in [oop-refactor-order.md](./oop-refactor-order.md).

This file is the plan only. No engine code is edited here; every diff below is applied by hand.

## Scope

**In scope**

- Replace `DisplayItem` / `DisplayCommand` protocols and the eight `Draw*` structs with one value enum.
- Resolve colors at paint time: `DisplayOp` carries `BrowserColor`, not `String`.
- Replace the `BrowserVisualEffect` class tree with `EffectKind` scopes.
- Replace the nested effect tree with one flat `[DisplayOp]` buffer using `beginEffect` / `endEffect`.
- Keep layer grouping, compositing strategy, animation updates, caches, tile hashing, and headless rendering behavior equivalent.
- Remove the machinery the two representations needed: `parentEffect`, `parent`, `needsCompositing`, `clone`, `addParentPointers`, `maxRectBottom`, `treeToList(DisplayItem)`, subtree copies.

**Out of scope**

- `NodeID` (item 3). `NodeKey` is the temporary alias item 4 replaces.
- Invalidation table and versions (item 4).
- Typed `ComputedStyle` beyond the color payload (item 5).
- `Sendable` snapshots and splitting `Frame` state (item 6). `RasterInput` keeps `@unchecked Sendable`.
- Renderer protocol changes. `Renderer` stays the open seam.

## Baseline

Verified before writing this plan:

- `swift build` → `Build complete!`
- `swift test` → **189 tests in 26 suites passed**
- `Sources/Engine` today: 38 `Draw*` / `ScrollbarBar` constructor calls, 43 files referencing the display types.

Capture visual baselines before the first code step:

```sh
swift run ToyStackHeadless "file://$PWD/www/ch11/index.html" \
  --trace /tmp/before-effects.trace --frame-limit 5 --screenshot /tmp/before-effects.png
swift run ToyStackHeadless "file://$PWD/www/ch11/exercise-11-3.html" \
  --trace /tmp/before-scroll.trace --frame-limit 5 --screenshot /tmp/before-scroll.png
```

## End state

One flat buffer. Nesting is a marker, not an object graph.

```swift
public enum DisplayOp {
    case rect(rect: Rect, color: BrowserColor)
    case rrect(rect: Rect, radii: CornerRadii, color: BrowserColor)
    case line(from: Point, to: Point, color: BrowserColor, width: CGFloat)
    case outline(rect: Rect, color: BrowserColor, width: CGFloat)
    case text(text: String, font: BrowserFont, color: BrowserColor, rect: Rect)
    case image(image: CGImage, rendering: ImageRendering, rect: Rect, version: UInt64)
    case clippedImage(image: CGImage, rendering: ImageRendering, rect: Rect, clip: Rect)
    case compositedLayer(layer: CompositedLayer, rect: Rect, visibleTop: CGFloat, visibleBottom: CGFloat)
    case beginEffect(EffectScope)
    case endEffect
}
```

The cases carry argument labels. Constructions use them (`.rect(rect:color:)`); patterns may omit them (`case .rect(let rect, let color)`). Diff snippets below predate the labels, so their positional constructions are pre-label form.

```swift
public enum EffectKind {
    case blend(opacity: Double, mode: BrowserBlendMode?)
    case blur(radius: CGFloat)
    case clip(ClipShape)
    case transform(CGPoint?)
    case scroll(ClipShape, offset: CGFloat)
}

public struct EffectScope {
    let id: EffectScopeID
    let kind: EffectKind
    let placement: EffectPlacement
}

public struct EffectPlacement {
    let rect: Rect
    let node: NodeKey?
    let animatedTransform: Bool
}
```

```swift
public struct EffectScopeID: Hashable {
    let paint: UInt
    let ordinal: Int
}

public struct NodeKey: Hashable {
    let raw: ObjectIdentifier

    init(_ node: any DOMNode) {
        self.raw = ObjectIdentifier(node)
    }
}

struct EffectUpdate {
    let style: PaintEffectStyle
    let isAnimatedTransform: Bool
}
```

Consumers:

- `Frame.displayList: [DisplayOp]`, `RasterScene.displayList: [DisplayOp]`, `CompositedLayer.displayItems: [DisplayOp]`, `TileStrip.items: [DisplayOp]`.
- `CompositedLayer.ancestorChain: [EffectScope]`.
- `compositedUpdates: [NodeKey: EffectUpdate]`.
- `LayerEffect.key: NodeKey?`.
- `LayerID.effect: EffectScopeID?`.

## Decisions

### D1. Two phases, seven steps

Phase A makes the list a single enum while effects are still an object tree. Phase B removes the tree. Each step below leaves the build green and the 189 tests passing.

| Step | Change | Commit subject |
|---|---|---|
| A1 | Add `DisplayOp` leaf enum and helpers | `refactor: model draw items as one value type` |
| A2 | Cut the engine over to `[DisplayOp]`; effects become an enum case | `refactor: replace draw protocols with one op enum` |
| A3 | Delete the parent-pointer and compositing-flag machinery | `refactor: drop display tree pointer plumbing` |
| B1 | Add flat effect types (`EffectKind`, `EffectScope`, updates) | `refactor: describe effects as values` |
| B2 | Replace effect classes with `DisplayEffect` values | `refactor: store effects as data, not objects` |
| B3 | Flatten paint into `beginEffect` / `endEffect` | `refactor: paint one flat display list` |
| B4 | Scan the flat list for composition and draw output | `refactor: compose layers from one flat scan` |

### D2. `DisplayOp` becomes public

`Browser.drawList` is public and `Chrome.paint()` returns the display type to the `ToyStack` target. `DisplayOp` must be public, so its payload types must be public too:

- `CompositedLayer` (internal class used by `.compositedLayer`)
- `ClipShape`, `EffectKind`, `EffectScope`, `EffectPlacement`, `EffectScopeID`, `NodeKey`
- `BrowserColor` gains `public struct BrowserColor: Hashable` (needed by `contentHash`)

This exposes type names, not internals: all stored properties and initializers stay internal. Item 6 replaces the composited layer with a value snapshot and can re-hide `CompositedLayer`.

**Alternative:** keep `DisplayOp` internal and give `Browser` public render/signature methods. Rejected: `Chrome.paint()` still needs a public display type, and the extra facade adds API without removing the payload exposure.

### D3. Flat data, recursive consumer

The display list is flat, but the renderer walks scopes by range:

```swift
func renderDisplayList(_ ops: [DisplayOp], renderer: any Renderer)
```

On `beginEffect`, find the matching `endEffect`, call the effect's renderer wrapper (`saveState`/`clip`/`translate` or `drawLayer`), and recurse over the inner index range. No array slices, no items copied; only indices.

**Alternative:** add `beginLayer` / `endLayer` to `Renderer` and render with a stack. Rejected: `SwiftUIRenderer` uses `GraphicsContext.drawLayer` which is closure-only, and blur needs an offscreen image. Range recursion preserves both renderer implementations unchanged.

### D4. Effect identity is `(paint, ordinal)`

`EffectScopeID` is allocated by paint, not by node or effect type:

- `paint` = `Frame.paintRevision`, so IDs from different paints never collide.
- `ordinal` = allocation order within that paint, deterministic.

This preserves today's behavior: effect objects are recreated on every paint, so layer IDs do not match across repaints. Within one paint (and therefore within repeated composites of the same display list), IDs are stable and `reuseRasterization` keeps working.

**Alternative:** `EffectScopeID(node:kind:)`. Rejected: `IframeLayout` emits two blend scopes for the same node, which would collide.

### D5. Animation updates become style values

`Frame.runAnimationFrame` currently rebuilds a `Transform(Blend(...))` tree per node so `getLatest` can match effects by class. After the flat refactor, an update is the whole computed effect style for that node:

```swift
EffectUpdate(style: paintEffectStyle(node:)!, isAnimatedTransform: node.animations["transform"] != nil)
```

`layerEffectStrategy` looks up the update by `scope.placement.node` and reads the field for that scope's kind. Same values, no tree search.

### D6. Drop the dead `scroll:` parameter

Every call site passes `scroll: 0` (`ScrollbarBar.swift:16`, all `execute(scroll:)` call sites, `TileStripRasterizer.swift:12`). Paint is already windowed and the content transform applies scrolling. Rename `execute(scroll:renderer:)` to `execute(renderer:)` while the signatures are changing anyway.

## File map

### Phase A

| File | Why |
|---|---|
| `Display/DisplayOp.swift` | **new**: enum, `rect`, `execute`, `shifted`, `contentHash`, `name` |
| `Display/DisplayItem.swift` | delete protocol |
| `Display/DisplayCommand.swift` | delete protocol and switch-based hash |
| `Display/DrawRect.swift`, `DrawLine.swift`, `DrawText.swift`, `DrawOutline.swift`, `DrawRRect.swift`, `DrawImage.swift`, `DrawClippedImage.swift`, `DrawCompositedLayer.swift`, `ScrollbarBar.swift` | delete; cases move to `DisplayOp` |
| `Display/BrowserVisualEffect.swift` | children become `[DisplayOp]`; remove `DisplayItem`, `parent`, `needsCompositing`, `addParentPointers`, `maxRectBottom` |
| `Display/Blend.swift`, `BlurFilter.swift`, `Clip.swift`, `ScrollEffect.swift`, `Transform.swift` | children `[DisplayOp]`; cast-free execute; rect via `child.rect` |
| `Display/PaintTree.swift` | buffers become `[DisplayOp]`; slices stay in Phase A |
| `Display/PaintCache.swift`, `LinePaintCache.swift` | store `[DisplayOp]`; reject effects and composited ops by case |
| `Display/DisplaySignature.swift` | switch on `DisplayOp` |
| `Display/Scrollbar.swift` | `scrollbarBarRect` returns `DisplayOp?` |
| `Display/DrawCursor.swift` | returns `DisplayOp` |
| `Display/ClipShape.swift` | becomes `public` |
| `Display/BrowserColor.swift` | add `Hashable` |
| `Layouts/BlockLayout.swift`, `ButtonLayout.swift`, `CanvasLayout.swift`, `IframeLayout.swift`, `ImageLayout.swift`, `InputLayout.swift`, `LineLayout.swift`, `TextLayout.swift`, `LayoutObject.swift` | constructors and `paint(into:)` become `[DisplayOp]` |
| `Core/Browser.swift` | `drawList`, composition walk, `LayerID`, a11y outlines |
| `Core/BrowserTab.swift`, `Frame.swift`, `FrameDisplay.swift`, `FrameDisplayOutput.swift`, `FrameRender.swift` | list types |
| `Core/TreeTraversal.swift` | delete the `DisplayItem` overload after the walker replaces it |
| `Raster/CompositedLayer.swift`, `TileStrip.swift`, `TileStripRasterizer.swift`, `RasterScene.swift`, `RasterOutput.swift` | list types, `canMerge(scope:)` |
| `ToyStack/Chrome.swift`, `ToyStack.swift` | chrome draw list |
| `ToyStackHeadless/ScreenshotCapture.swift` | no casts |
| `Tests/ToyStackTests/PaintCacheTests.swift`, `PaddingLayoutTests.swift`, `PaintCullingTests.swift`, `LayoutOracleTests.swift` | pattern-match cases |
| `profiling.md` | remove `paint.range.copy`, `raster.composite.flatten` |
| `README.md:38` | replace the `Draw*` / effect-class description with `DisplayOp` / scopes |

### Phase B

| File | Why |
|---|---|
| `Display/EffectKind.swift`, `EffectScope.swift`, `EffectScopeID.swift`, `NodeKey.swift`, `EffectUpdate.swift`, `PaintSession.swift`, `DisplayListRenderer.swift` | **new** flat types and renderer walk |
| `Display/DisplayEffect.swift` | **new in B2, deleted in B3**; bridge value tree |
| `Display/DisplayOp.swift` | `.effect` → `beginEffect` / `endEffect`; renderer switch |
| `Display/BrowserVisualEffect.swift`, `Blend.swift`, `BlurFilter.swift`, `Clip.swift`, `ScrollEffect.swift`, `Transform.swift` | delete in B2 |
| `Display/PaintTree.swift` | open/close markers, patch scope rects, iframe scopes |
| `Display/PaintCache.swift`, `LinePaintCache.swift`, `DisplaySignature.swift` | reject/print markers |
| `Layouts/LayoutObject.swift`, `EmbedLayout.swift`, `IframeLayout.swift` | effect hooks become scope emission |
| `Core/Frame.swift` | `PaintSession`, `EffectUpdate` |
| `Core/FrameDisplay.swift`, `Core/FrameDisplayOutput.swift`, `Core/FrameRender.swift` | list and update types |
| `Raster/RasterScene.swift`, `Raster/RasterOutput.swift` | list and update types |
| `Core/Browser.swift` | flat composition, layer strategy, composited draw stream |
| `Raster/CompositedLayer.swift`, `LayerID.swift`, `TileStrip.swift` | scope chains and first command index |
| `Raster/LayerEffect.swift` | `key: NodeKey?` |
| `ToyStack/Chrome.swift`, `ToyStackHeadless/ScreenshotCapture.swift` | `renderDisplayList` |
| `profiling.md`, `README.md` (architecture note if the display list is described) | metric names |

---

## Phase A — one enum, effects still a tree

### A1. Add `DisplayOp` (leaf cases only)

New file `Sources/Engine/Display/DisplayOp.swift`:

```swift
import CoreGraphics

public enum DisplayOp {
    case rect(Rect, BrowserColor)
    case rrect(Rect, CornerRadii, BrowserColor)
    case line(Point, Point, BrowserColor, CGFloat)
    case outline(Rect, BrowserColor, CGFloat)
    case text(String, BrowserFont, BrowserColor, Rect)
    case image(CGImage, ImageRendering, Rect, UInt64)
    case clippedImage(CGImage, ImageRendering, Rect, Rect)
    case compositedLayer(CompositedLayer, Rect, CGFloat, CGFloat)
    case effect(BrowserVisualEffect)   // temporary: removed in B2/B3
}

extension DisplayOp {
    var rect: Rect {
        switch self {
        case .rect(let rect, _), .rrect(let rect, _, _), .outline(let rect, _, _),
             .text(_, _, _, let rect), .image(_, _, let rect, _),
             .clippedImage(_, _, let rect, _), .compositedLayer(_, let rect, _, _):
            return rect
        case .line(let from, let to, _, _):
            return Rect(left: from.x, top: from.y, right: to.x, bottom: to.y)
        case .effect(let effect):
            return effect.rect
        }
    }

    var name: String {
        switch self {
        case .rect: return "rect"
        case .rrect: return "rrect"
        case .line: return "line"
        case .outline: return "outline"
        case .text: return "text"
        case .image: return "image"
        case .clippedImage: return "clippedImage"
        case .compositedLayer: return "compositedLayer"
        case .effect(let effect): return String(describing: type(of: effect))
        }
    }

    public func execute(renderer: any Renderer) {
        switch self {
        case .rect(let rect, let color):
            renderer.fillRect(rect, color: color)
        case .rrect(let rect, let radii, let color):
            renderer.fillRRect(rect, radii: radii, color: color)
        case .line(let from, let to, let color, let width):
            renderer.strokeSegment(from: from, to: to, color: color, lineWidth: width)
        case .outline(let rect, let color, let width):
            renderer.strokeRect(rect, color: color, lineWidth: width)
        case .text(let text, let font, let color, let rect):
            renderer.drawText(text, font: font, color: color, at: Point(x: rect.left, y: rect.top))
        case .image(let image, let rendering, let rect, _):
            renderer.drawImage(image, in: rect, rendering: rendering)
        case .clippedImage(let image, let rendering, let rect, let clip):
            renderer.saveState()
            renderer.clip(to: clip)
            renderer.drawImage(image, in: rect, rendering: rendering)
            renderer.restoreState()
        case .compositedLayer(let layer, _, let visibleTop, let visibleBottom):
            executeCompositedLayer(layer, visibleTop: visibleTop, visibleBottom: visibleBottom, renderer: renderer)
        case .effect(let effect):
            effect.execute(renderer: renderer)
        }
    }

    func shifted(dx: CGFloat, dy: CGFloat) -> DisplayOp {
        switch self {
        case .rect(let rect, let color):
            return .rect(rect.translated(dx: dx, dy: dy), color)
        case .rrect(let rect, let radii, let color):
            return .rrect(rect.translated(dx: dx, dy: dy), radii, color)
        case .line(let from, let to, let color, let width):
            return .line(
                Point(x: from.x + dx, y: from.y + dy),
                Point(x: to.x + dx, y: to.y + dy),
                color, width
            )
        case .outline(let rect, let color, let width):
            return .outline(rect.translated(dx: dx, dy: dy), color, width)
        case .text(let text, let font, let color, let rect):
            return .text(text, font, color, rect.translated(dx: dx, dy: dy))
        case .image(let image, let rendering, let rect, let version):
            return .image(image, rendering, rect.translated(dx: dx, dy: dy), version)
        case .clippedImage(let image, let rendering, let rect, let clip):
            return .clippedImage(
                image, rendering,
                rect.translated(dx: dx, dy: dy),
                clip.translated(dx: dx, dy: dy)
            )
        case .compositedLayer, .effect:
            preconditionFailure("\(name) cannot be shifted")
        }
    }

    var contentHash: Int {
        var hasher: Hasher = Hasher()
        hasher.combine(name)
        hasher.combine(rect.left)
        hasher.combine(rect.top)
        hasher.combine(rect.right)
        hasher.combine(rect.bottom)
        switch self {
        case .rect(_, let color), .outline(_, let color, _):
            hasher.combine(color)
        case .rrect(_, let radii, let color):
            hasher.combine(color)
            hasher.combine(radii)
        case .line(_, _, let color, let width):
            hasher.combine(color)
            hasher.combine(width)
        case .text(let text, let font, let color, _):
            hasher.combine(text)
            hasher.combine(color)
            hasher.combine(ObjectIdentifier(font.ctFont))
        case .image(let image, let rendering, _, let version):
            hasher.combine(ObjectIdentifier(image))
            hasher.combine(rendering.rawValue)
            hasher.combine(version)
        case .clippedImage(let image, let rendering, _, let clip):
            hasher.combine(ObjectIdentifier(image))
            hasher.combine(rendering.rawValue)
            hasher.combine(clip.left)
            hasher.combine(clip.top)
            hasher.combine(clip.right)
            hasher.combine(clip.bottom)
        case .compositedLayer, .effect:
            break
        }
        return hasher.finalize()
    }
}
```

One note before this compiles:

`executeCompositedLayer` is the body currently inside `DrawCompositedLayer.execute` (`DrawCompositedLayer.swift:18-43`). Move it to a private helper in the same file:

```swift
private func executeCompositedLayer(
    _ layer: CompositedLayer,
    visibleTop: CGFloat,
    visibleBottom: CGFloat,
    renderer: any Renderer
) {
    let bounds: Rect = layer.compositedBounds()
    if !layer.tiles.isEmpty {
        let t: CGFloat = CompositedLayer.tileSize
        for index in layer.orderedTileIndices {
            guard let image: CGImage = layer.tiles[index] else { continue }
            let tileLeft: CGFloat = CGFloat(index.col) * t
            let tileTop: CGFloat = CGFloat(index.row) * t
            if tileTop + t <= visibleTop || tileTop >= visibleBottom { continue }
            renderer.drawImage(
                image,
                in: Rect(left: tileLeft, top: tileTop, right: tileLeft + t, bottom: tileTop + t)
            )
        }
    } else {
        renderer.saveState()
        renderer.translateBy(x: bounds.left, y: bounds.top)
        layer.raster(renderer: renderer)
        renderer.restoreState()
    }
}
```

Build gate: new file unused, `swift build` green.

Before this step compiles, apply the access changes from D2: `CompositedLayer`, `ClipShape` become `public`, and `BrowserColor` becomes `Hashable`. The enum declaration rejects an internal payload type even when the enum is unused.

### A2. Cut over to `[DisplayOp]`

This is the mechanical step. It is one commit because the protocols cannot coexist with the enum as the list element: the compiler forces every producer and consumer to move together.

**2a. Effects own `[DisplayOp]` children.** `Sources/Engine/Display/BrowserVisualEffect.swift`:

```diff
-public class BrowserVisualEffect: DisplayItem {
+public class BrowserVisualEffect {
     public var rect: Rect
-    var children: [any DisplayItem]
+    var children: [DisplayOp]
     weak var node: DOMNode?
-    var needsCompositing: Bool
-    weak var parent: BrowserVisualEffect?
 
-    init(rect: Rect, children: [any DisplayItem], node: DOMNode? = nil) {
+    init(rect: Rect, children: [DisplayOp], node: DOMNode? = nil) {
         self.rect = rect
         self.children = children
         self.node = node
-        self.needsCompositing = children.compactMap({
-            $0 as? BrowserVisualEffect
-        })
-        .contains(where: {
-            $0.needsCompositing
-        })
     }
 
     public func execute(renderer: any Renderer) {}
 
     func map(rect: Rect) -> Rect { return rect }
 
     func unmap(rect: Rect) -> Rect { return rect }
 
-    func clone(children: [any DisplayItem]) -> BrowserVisualEffect {
+    func clone(children: [DisplayOp]) -> BrowserVisualEffect {
         fatalError("\(type(of: self)) must be implement clone(children:)")
     }
 }
```

Each subclass: `children: [DisplayOp]`, `clone(children: [DisplayOp])`, and replace the cast loops with direct dispatch:

```diff
-            for child in children {
-                if let ve = child as? BrowserVisualEffect {
-                    ve.execute(renderer: renderer)
-                } else if let dc = child as? DisplayCommand {
-                    dc.execute(scroll: 0, renderer: renderer)
-                }
-            }
+            for child in children {
+                child.execute(renderer: renderer)
+            }
```

`Blend.swift` / `BlurFilter.swift` compute their union without casts:

```diff
-        var combinedRect: Rect = Rect(left: 0, top: 0, right: 0, bottom: 0)
-        for child in children {
-            if let ve = child as? BrowserVisualEffect {
-                combinedRect = combinedRect.union(ve.rect)
-            } else if let dc = child as? DisplayCommand {
-                combinedRect = combinedRect.union(dc.rect)
-            }
-        }
+        var combinedRect: Rect = Rect(left: 0, top: 0, right: 0, bottom: 0)
+        for child in children {
+            combinedRect = combinedRect.union(child.rect)
+        }
```

`paintBrowserVisualEffects` returns `[DisplayOp]` and wraps in `.effect(...)`:

```diff
-func paintBrowserVisualEffects(style: PaintEffectStyle, node: DOMNode, items: [any DisplayItem], rect: Rect) -> [any DisplayItem] {
-    var displayItems: [any DisplayItem] = items
+func paintBrowserVisualEffects(style: PaintEffectStyle, node: DOMNode, items: [DisplayOp], rect: Rect) -> [DisplayOp] {
+    var displayItems: [DisplayOp] = items
     if style.blurRadius > 0 {
-        displayItems = [BlurFilter(radius: style.blurRadius, node: node, children: displayItems)]
+        displayItems = [.effect(BlurFilter(radius: style.blurRadius, node: node, children: displayItems))]
     }
 
     let blend: Blend = Blend(
         opacity: style.opacity,
         blendMode: style.blendMode,
         node: node,
         children: displayItems
     )
 
     let transform: Transform = Transform(
         translation: style.translation,
         rect: rect,
         node: node,
-        children: [blend]
+        children: [.effect(blend)]
     )
 
-    return [transform]
+    return [.effect(transform)]
 }
```

**2b. Convert the 38 constructors.** Mapping, applied with the parameter order shown:

| Old | New |
|---|---|
| `DrawRect(rect:color:)` | `.rect(rect, BrowserColor(cssName: color))` |
| `DrawRRect(rect:parentEffect:radii:color:)` | `.rrect(rect, radii, BrowserColor(cssName: color))` |
| `DrawLine(from:to:color:thickness:)` | `.line(from, to, BrowserColor(cssName: color), thickness)` |
| `DrawOutline(rect:color:thickness:)` | `.outline(rect, BrowserColor(cssName: color), thickness)` |
| `DrawText(rect:text:font:color:)` and `DrawText(at:text:font:color:)` | `.text(text, font, BrowserColor(cssName: color), rect)`; the `at:` form computes `Rect(left: point.x, top: point.y, right: point.x + font.measure(text), bottom: point.y + font.linespace)` |
| `DrawImage(image:rendering:rect:parentEffect:contentVersion:)` | `.image(image, rendering, rect, contentVersion)` |
| `DrawClippedImage(image:rendering:rect:clip:)` | `.clippedImage(image, rendering, rect, clip)` |
| `DrawCompositedLayer(layer:visibleTop:visibleBottom:)` | `.compositedLayer(layer, layer.absoluteBounds(), visibleTop, visibleBottom)` |
| `ScrollbarBar(rect:color:radius:)` | `.rrect(rect, .uniform(.px(radius)), BrowserColor(cssName: color))` |

Call sites, one line each where possible:

- `BlockLayout.swift:1067,1075,1083,1093,1094,1105,1110,1113,1144`
- `ButtonLayout.swift:122,123,127,128`
- `CanvasLayout.swift:58`
- `IframeLayout.swift:79,152`
- `ImageLayout.swift:96`
- `InputLayout.swift:47,55,60,61,64,74,75,96,103,104`
- `LineLayout.swift:225,226`
- `TextLayout.swift:109`
- `Browser.swift:807,832,833,837,838`
- `Frame.swift:1192`
- `Scrollbar.swift:27`
- `DrawCursor.swift:6`
- `Chrome.swift:102-246`

`DrawOutline.fromStyle` / `fromBorderStyle` return `DisplayOp?`. `childScrollbar` returns `DisplayOp?`. `drawCursor` returns `DisplayOp`. `scrollbarCommands()` on `Frame` and `BrowserTab` returns `[DisplayOp]`. `Chrome.paint()` returns `[DisplayOp]`.

**2c. Paint signature.** `LayoutObject.paint(into:)`, `paintEffects`, `applyPaintEffects`, `PaintTree.paintTree`, `clippedChildren` and every override use `[DisplayOp]`.

`PaintCache`:

```diff
 struct PaintCache {
-    private var items: [any DisplayCommand] = []
+    private var items: [DisplayOp] = []
@@
     mutating func store(
-        items: [any DisplayItem],
+        items: [DisplayOp],
         key: PaintKey,
         origin: Point
     ) {
-        var relative: [any DisplayCommand] = []
+        var relative: [DisplayOp] = []
         relative.reserveCapacity(items.count)
         for item in items {
-            guard let command = item as? any DisplayCommand, !(command is DrawCompositedLayer)
-            else {
+            if case .effect = item {
+                valid = false
+                self.items.removeAll(keepingCapacity: true)
+                return
+            }
+            if case .compositedLayer = item {
                 valid = false
                 self.items.removeAll(keepingCapacity: true)
                 return
             }
-            relative.append(command.shifted(dx: -origin.x, dy: -origin.y))
+            relative.append(item.shifted(dx: -origin.x, dy: -origin.y))
         }
@@
-    func append(to displayList: inout [any DisplayItem], origin: Point) {
+    func append(to displayList: inout [DisplayOp], origin: Point) {
```

`LinePaintCache` accepts only `.text` and `.outline`:

```diff
-        var commands: [any DisplayCommand] = []
+        var commands: [DisplayOp] = []
         commands.reserveCapacity(items.count)
         for item in items {
-            guard let command = item as? any DisplayCommand, command is DrawText || command is DrawOutline
-            else {
-                valid = false
-                self.items.removeAll(keepingCapacity: true)
-                return
-            }
-            commands.append(command)
+            switch item {
+            case .text, .outline:
+                commands.append(item)
+            default:
+                valid = false
+                self.items.removeAll(keepingCapacity: true)
+                return
+            }
         }
```

**2d. Composition walker.** `parentEffect` no longer exists, so `computeComposite` walks the tree with an explicit scope stack instead of flattening and mutating pointers.

Delete from `Browser.swift`:

```diff
-        var displayList: [any DisplayItem] = inputs.scene.displayList
-        addParentPointers(&displayList)
-        measure.stop("raster.composite.copy")
-
-        measure.start("raster.composite.flatten", category: .raster, frame: frame)
-        var allItems: [any DisplayItem] = []
-        for item in displayList {
-            treeToList(item, into: &allItems)
-        }
-
-        let nonComposited: [any DisplayCommand] = allItems.compactMap({ item -> (any DisplayCommand)? in
-            if let pc = item as? (any DisplayCommand) { return pc }
-            if let ve = item as? BrowserVisualEffect, !ve.needsCompositing {
-                if ve.parent == nil || ve.parent!.needsCompositing { return nil }
-            }
-            return nil
-        })
-        measure.stop("raster.composite.flatten")
```

Replace with one walk (the `nonComposited` filter was dead: both branches returned `nil` for effects, so it was every command in depth-first order):

```swift
var compositedLayers: [CompositedLayer] = []
var ordinals: [ObjectIdentifier?: Int] = [:]
var assumeOverlap: Bool = false

func visit(_ op: DisplayOp, _ scopes: [BrowserVisualEffect]) {
    let scope: ObjectIdentifier? = scopes.last.map(ObjectIdentifier.init)
    if scopes.contains(where: { ($0 as? Transform)?.isAnimated == true }) {
        assumeOverlap = true
    }
    for layer in compositedLayers.reversed() {
        if layer.canMerge(scope: scope) {
            layer.add(op)
            return
        } else if assumeOverlap {
            break
        }
    }
    let ordinal: Int = ordinals[scope, default: 0]
    ordinals[scope] = ordinal + 1
    let layer: CompositedLayer = CompositedLayer(displayItem: op)
    layer.id = LayerID(effect: scope, ordinal: ordinal)
    layer.ancestorChain = Array(scopes.reversed())
    compositedLayers.append(layer)
}

walkDisplayItems(inputs.scene.displayList, visit: visit)
```

`walkDisplayItems` is a new supporting helper in `DisplayOp.swift` (it survives until B4). It passes the scope stack by value so the visitor can read it without overlapping an `inout` access:

```swift
func walkDisplayItems(
    _ items: [DisplayOp],
    scopes: [BrowserVisualEffect] = [],
    visit: (DisplayOp, [BrowserVisualEffect]) -> Void
) {
    for item in items {
        if case .effect(let effect) = item {
            walkDisplayItems(effect.children, scopes: scopes + [effect], visit: visit)
        } else {
            visit(item, scopes)
        }
    }
}
```

`CompositedLayer`:

```diff
-    var displayItems: [DisplayCommand] = []
+    var displayItems: [DisplayOp] = []
@@
-    init(displayItem: DisplayCommand) {
+    init(displayItem: DisplayOp) {
         self.displayItems = [displayItem]
     }
 
-    func canMerge(_ displayItem: DisplayCommand) -> Bool {
-        guard displayItem.parentEffect === displayItems[0].parentEffect else {
-            return false
-        }
-        return true
+    func canMerge(scope: ObjectIdentifier?) -> Bool {
+        return id.effect == scope
     }
 
-    func add(_ displayItem: DisplayCommand) {
+    func add(_ displayItem: DisplayOp) {
@@
-        for item in displayItems {
-            item.execute(scroll: 0, renderer: renderer)
+        for item in displayItems {
+            item.execute(renderer: renderer)
@@
-        let items: [any DisplayCommand] = displayItems
+        let items: [DisplayOp] = displayItems
@@
-        var rowItems: [Int: [DisplayCommand]] = [:]
+        var rowItems: [Int: [DisplayOp]] = [:]
@@
-            let strip: [any DisplayCommand] = rowItems[row] ?? []
+            let strip: [DisplayOp] = rowItems[row] ?? []
@@
-                let inside: [any DisplayCommand] = strip.filter { $0.rect.left < colRight  && $0.rect.right > colLeft }
+                let inside: [DisplayOp] = strip.filter { $0.rect.left < colRight  && $0.rect.right > colLeft }
@@
-    private func tileHash(_ inside: [DisplayCommand], tileRect: Rect) -> Int {
+    private func tileHash(_ inside: [DisplayOp], tileRect: Rect) -> Int {
         var hasher: Hasher = Hasher()
         for item in inside {
-            if let fill = item as? DrawRect {
-                hasher.combine(ObjectIdentifier(DrawRect.self))
-                hasher.combine(fill.color)
-                let visible: Rect = fill.rect.intersect(tileRect)
+            if case .rect(let rect, let color) = item {
+                hasher.combine("rect")
+                hasher.combine(color)
+                let visible: Rect = rect.intersect(tileRect)
                 hasher.combine(visible.left)
                 hasher.combine(visible.top)
                 hasher.combine(visible.right)
                 hasher.combine(visible.bottom)
             } else {
                 hasher.combine(item.contentHash)
             }
```

`TileStrip` and `TileStripRasterizer` take `[DisplayOp]` and call `execute(renderer:)`.

**2e. Plain loops lose their casts.**

`Browser.swift:514-519`:

```diff
-                                for item in drawList {
-                                    if let cmd = item as? any DisplayCommand {
-                                        cmd.execute(scroll: 0, renderer: r)
-                                    } else if let ve = item as? BrowserVisualEffect {
-                                        ve.execute(renderer: r)
-                                    }
-                                }
+                                for op in drawList {
+                                    op.execute(renderer: r)
+                                }
```

`ScreenshotCapture.swift:29-35` and `ToyStack.swift:69-71` become the same one-line loop.

**2f. Signatures and tests.**

```diff
-public func displaySignature(_ list: [any DisplayItem]) -> String {
+public func displaySignature(_ list: [DisplayOp]) -> String {
@@
-        if let command = item as? any DisplayCommand {
-            parts.append("\(type(of: command)) \(command.rect) \(command.contentHash)")
-        } else if let effect = item as? BrowserVisualEffect {
-            parts.append("\(type(of: effect)) \(effect.rect)")
-            appendDisplaySignature(effect.children, into: &parts)
-        } else {
-            parts.append("\(type(of: item))")
-        }
+        parts.append("\(item.name) \(item.rect) \(item.contentHash)")
+        if case .effect(let effect) = item {
+            appendDisplaySignature(effect.children, into: &parts)
+        }
```

Test updates:

- `PaintCacheTests.swift`: replace `displayList.first as? DrawRect` with `guard case .rect(let rect, let color) = try #require(displayList.first)`. Color assertions compare `BrowserColor(cssName: "red")` instead of the string. Line 143 changes `(item as? any DisplayCommand)?.execute(scroll: 0, renderer: renderer)` to `item.execute(renderer: renderer)`.
- `PaddingLayoutTests.swift:110`: `compactMap` becomes a `compactMap` that returns `rect` only for `.rect`.
- `PaintCullingTests.swift:98-104`: `displayTexts` becomes:

```swift
private func displayTexts(_ list: [DisplayOp]) -> [String] {
    var texts: [String] = []
    walkDisplayItems(list) { op, _ in
        if case .text(let text, _, _, _) = op { texts.append(text) }
    }
    return texts
}
```

- `LayoutOracleTests.swift:355-358`: find the caret as `.line(from, to, color, _)` where `color == BrowserColor(cssName: "red")`; return `from.x`.
- `TileKeyTests.swift` is unchanged in Phase A.

**2g. Delete the old types.** Remove `DisplayItem.swift`, `DisplayCommand.swift`, the eight `Draw*.swift` files, and `ScrollbarBar.swift`. Remove `treeToList(_ item: any DisplayItem, ...)` from `TreeTraversal.swift` and `maxRectBottom` from `BrowserVisualEffect.swift`.

Gate A2:

```sh
swift build
swift test
swift run ToyStackHeadless "file://$PWD/www/ch11/index.html" --trace /tmp/a2.trace --frame-limit 5 --screenshot /tmp/a2.png
```

Compare `/tmp/a2.png` with `/tmp/before-effects.png`. They must match pixel-for-pixel; if they do not, stop before A3.

### A3. Delete the remaining tree plumbing

- Remove `needsCompositing` from `Blend`/`BlurFilter`/`Clip`/`ScrollEffect` (now unused) and the dead branch at `Browser.swift:624-625`.
- Remove `weak var parent` and `addParentPointers` (already unused after A2; if the compiler allowed them to stay, delete now).
- Update `profiling.md`:
  - remove `paint.range.copy` (line 344),
  - keep `paint.effect.check`/`wrap` for Phase A; `paint.effect.wrap` now measures only array creation and is removed in B3,
  - replace `raster.composite.flatten` with `raster.composite.walk` and note it is one depth-first walk.

Gate A: `swift build`, `swift test`, both baseline screenshots.

---

## Phase B — one flat buffer

### B1. Add flat effect types

New files, unused until B2:

`EffectKind.swift`:

```swift
import CoreGraphics

public enum EffectKind {
    case blend(opacity: Double, mode: BrowserBlendMode?)
    case blur(radius: CGFloat)
    case clip(ClipShape)
    case transform(CGPoint?)
    case scroll(ClipShape, offset: CGFloat)
}
```

`EffectScope.swift`:

```swift
import CoreGraphics

public struct EffectScope {
    let id: EffectScopeID
    let kind: EffectKind
    let placement: EffectPlacement

    init(id: EffectScopeID, kind: EffectKind, placement: EffectPlacement) {
        self.id = id
        self.kind = kind
        self.placement = placement
    }
}

// MARK: - EffectPlacement

public struct EffectPlacement {
    let rect: Rect
    let node: NodeKey?
    let animatedTransform: Bool

    init(rect: Rect, node: NodeKey?, animatedTransform: Bool) {
        self.rect = rect
        self.node = node
        self.animatedTransform = animatedTransform
    }
}
```

`EffectScopeID.swift`:

```swift
public struct EffectScopeID: Hashable {
    let paint: UInt
    let ordinal: Int

    init(paint: UInt, ordinal: Int) {
        self.paint = paint
        self.ordinal = ordinal
    }
}
```

`NodeKey.swift`:

```swift
public struct NodeKey: Hashable {
    let raw: ObjectIdentifier

    init(_ node: any DOMNode) {
        self.raw = ObjectIdentifier(node)
    }
}
```

`EffectUpdate.swift`:

```swift
struct EffectUpdate {
    let style: PaintEffectStyle
    let isAnimatedTransform: Bool
}
```

`PaintSession.swift`:

```swift
struct PaintSession {
    let paint: UInt
    let epoch: UInt
    let window: PaintWindow
    private var nextScope: Int = 0

    init(paint: UInt, epoch: UInt, window: PaintWindow) {
        self.paint = paint
        self.epoch = epoch
        self.window = window
    }

    mutating func makeScope(_ kind: EffectKind, node: NodeKey?, animatedTransform: Bool) -> EffectScope {
        defer { nextScope += 1 }
        return EffectScope(
            id: EffectScopeID(paint: paint, ordinal: nextScope),
            kind: kind,
            placement: EffectPlacement(rect: .zero, node: node, animatedTransform: animatedTransform)
        )
    }
}
```

`PaintSession` is used in B2 (tree) only to allocate IDs; `epoch`/`window` replace the old `paintTree` parameters in B3.

Gate B1: build.

### B2. Effects become values

Replace the class files with one bridge type. `DisplayEffect.swift`:

```swift
public struct DisplayEffect {
    var scope: EffectScope
    var children: [DisplayOp]

    func execute(renderer: any Renderer) {
        applyEffect(scope.kind, renderer: renderer) { inner in
            for child in children {
                child.execute(renderer: inner)
            }
        }
    }
}
```

`applyEffect` lives in `EffectKind.swift` and is shared with the B3 renderer:

```swift
func applyEffect(
    _ kind: EffectKind,
    renderer: any Renderer,
    content: (any Renderer) -> Void
) {
    switch kind {
    case .transform(let translation):
        renderer.saveState()
        if let translation {
            renderer.translateBy(x: translation.x, y: translation.y)
        }
        content(renderer)
        renderer.restoreState()
    case .clip(let shape):
        renderer.saveState()
        renderer.clipRRect(shape.rect, radii: shape.radii)
        content(renderer)
        renderer.restoreState()
    case .scroll(let shape, let offset):
        renderer.saveState()
        renderer.clipRRect(shape.rect, radii: shape.radii)
        renderer.translateBy(x: 0, y: -offset)
        content(renderer)
        renderer.restoreState()
    case .blend(let opacity, let mode):
        guard opacity < 1.0 || mode != nil else {
            content(renderer)
            return
        }
        renderer.drawLayer(LayerOptions(opacity: opacity, blendMode: mode)) { inner in
            content(inner)
        }
    case .blur(let radius):
        renderer.drawLayer(LayerOptions(blur: radius)) { inner in
            content(inner)
        }
    }
}
```

`DisplayOp.effect` changes payload:

```diff
-    case effect(BrowserVisualEffect)
+    case effect(DisplayEffect)
```

`rect`/`execute`/`shifted`/`name` switch updates are one line each.

`paintBrowserVisualEffects` now returns `.effect(DisplayEffect(...))`. It needs a session to allocate IDs. Change the two construction sites:

```diff
-func paintBrowserVisualEffects(style: PaintEffectStyle, node: DOMNode, items: [DisplayOp], rect: Rect) -> [DisplayOp] {
+func paintBrowserVisualEffects(
+    style: PaintEffectStyle,
+    node: DOMNode,
+    items: [DisplayOp],
+    rect: Rect,
+    session: inout PaintSession
+) -> [DisplayOp] {
     var displayItems: [DisplayOp] = items
     if style.blurRadius > 0 {
-        displayItems = [.effect(BlurFilter(radius: style.blurRadius, node: node, children: displayItems))]
+        displayItems = [.effect(DisplayEffect(
+            scope: session.makeScope(.blur(radius: style.blurRadius), node: NodeKey(node), animatedTransform: false),
+            children: displayItems
+        ))]
     }
 
-    let blend: Blend = Blend(
-        opacity: style.opacity,
-        blendMode: style.blendMode,
-        node: node,
-        children: displayItems
-    )
-
-    let transform: Transform = Transform(
-        translation: style.translation,
-        rect: rect,
-        node: node,
-        children: [.effect(blend)]
-    )
-
-    return [.effect(transform)]
+    let blend: DisplayEffect = DisplayEffect(
+        scope: session.makeScope(
+            .blend(opacity: style.opacity, mode: style.blendMode),
+            node: NodeKey(node),
+            animatedTransform: false
+        ),
+        children: displayItems
+    )
+
+    let transform: DisplayEffect = DisplayEffect(
+        scope: session.makeScope(
+            .transform(style.translation),
+            node: NodeKey(node),
+            animatedTransform: node.animations["transform"] != nil
+        ),
+        children: [.effect(blend)]
+    )
+
+    return [.effect(transform)]
 }
```

The `rect` inside `EffectPlacement` is set after the wrapper is built: the old classes computed it in `init`. For the bridge, set it explicitly:

```swift
var effectScope: EffectScope = session.makeScope(...)
effectScope = EffectScope(
    id: effectScope.id,
    kind: effectScope.kind,
    placement: EffectPlacement(rect: computedRect, node: NodeKey(node), animatedTransform: ...)
)
```

where `computedRect` is `items.reduce(.zero, { $0.union($1.rect) })` for blur/blend and `rect` for transform, matching the old class initializers.

`ScrollEffect` and `Clip` in `PaintTree.swift` become `DisplayEffect` with `.scroll(...)` / `.clip(...)` scopes, allocated from the session. `IframeLayout.paintEffects` builds `DisplayEffect` values the same way with its internal `.clip`, `.transform`, `.blend(1, nil)` scopes.

Composition in B2 walks `DisplayEffect` values:

```swift
func walkDisplayItems(
    _ items: [DisplayOp],
    scopes: [EffectScope] = [],
    visit: (DisplayOp, [EffectScope]) -> Void
) {
    for item in items {
        if case .effect(let effect) = item {
            walkDisplayItems(effect.children, scopes: scopes + [effect.scope], visit: visit)
        } else {
            visit(item, scopes)
        }
    }
}
```

`CompositedLayer.ancestorChain: [EffectScope]`, `LayerID.effect: EffectScopeID?`. The A2 visit function keeps its shape; only the scope type changes:

```swift
func visit(_ op: DisplayOp, _ scopes: [EffectScope]) {
    let scopeID: EffectScopeID? = scopes.last?.id
    if scopes.contains(where: { scope in
        if case .transform = scope.kind { return scope.placement.animatedTransform }
        return false
    }) {
        assumeOverlap = true
    }
    // merge / create layer as in A2, keyed by scopeID and chain scopes.reversed()
}

walkDisplayItems(inputs.scene.displayList, visit: visit)
```

`Frame`:

```diff
-    private var compositedUpdates: [ObjectIdentifier: BrowserVisualEffect] = [:]
+    private var compositedUpdates: [NodeKey: EffectUpdate] = [:]
```

`Frame.runAnimationFrame` (`Frame.swift:978-990`):

```diff
                         node.style[property] = value
-                        if let rect = (node.layoutObject as? BlockLayout)?.selfRect(),
-                            let effect = paintBrowserVisualEffects(node: node, items: [], rect: rect).first
-                                as? BrowserVisualEffect
-                        {
-                            compositedUpdates[ObjectIdentifier(node)] = effect
+                        if (node.layoutObject as? BlockLayout) != nil,
+                            let style: PaintEffectStyle = paintEffectStyle(node: node)
+                        {
+                            compositedUpdates[NodeKey(node)] = EffectUpdate(
+                                style: style,
+                                isAnimatedTransform: node.animations["transform"] != nil
+                            )
                         }
```

`Browser.layerEffectStrategy` reads scope values:

```swift
for scope in layer.ancestorChain {
    let update: EffectUpdate? = scope.placement.node.flatMap { updates[$0] }
    let animated: Bool = update?.isAnimatedTransform ?? scope.placement.animatedTransform
    switch scope.kind {
    case .scroll:
        kind = max(kind, .scrollFallback)
    case .blend(let opacity, let mode):
        let updatedOpacity: Double = update?.style.opacity ?? opacity
        let updatedMode: BrowserBlendMode? = update.map({ $0.style.blendMode }) ?? mode
        if let updatedMode, updatedMode != .normal {
            if updatedMode.compositingFilterName != nil {
                kind = max(kind, .ca)
                if blendMode == nil { blendMode = updatedMode }
            } else {
                kind = max(kind, .blendFallback)
            }
        } else if updatedOpacity < 1 {
            kind = max(kind, .ca)
        }
        if key == nil { key = scope.placement.node }
    case .transform(let translation):
        let updatedTranslation: CGPoint? = update.map({ $0.style.translation }) ?? translation
        if let updatedTranslation {
            translation.x += updatedTranslation.x
            translation.y += updatedTranslation.y
            kind = max(kind, .ca)
        }
        if animated { kind = max(kind, .ca) }
        if key == nil { key = scope.placement.node }
    case .blur(let radius):
        let updatedRadius: CGFloat = update?.style.blurRadius ?? radius
        if updatedRadius > 0 {
            blur = max(blur, updatedRadius)
            kind = max(kind, .ca)
            if key == nil { key = scope.placement.node }
        }
    case .clip(let shape):
        let local: Rect = Rect(
            left: shape.rect.left - translation.x,
            top: shape.rect.top - translation.y,
            right: shape.rect.right - translation.x,
            bottom: shape.rect.bottom - translation.y
        )
        clipRect = clipRect.map({ $0.intersect(local) }) ?? local
    }
}
```

`LayerEffect.key: NodeKey?`; `applyEffectFastPath` uses `Set<NodeKey>`; `updatesAreCA`:

```swift
nonisolated static func updatesAreCA(_ updates: [NodeKey: EffectUpdate]) -> Bool {
    updates.values.allSatisfy({ update in
        update.style.blurRadius == 0
            && (update.style.blendMode == nil
                || update.style.blendMode == .normal
                || update.style.blendMode?.compositingFilterName != nil)
    })
}
```

`CompositedLayer.absoluteBounds()` applies `.transform` scopes:

```swift
for scope in ancestorChain {
    if case .transform(let translation) = scope.kind, let translation {
        rect = Rect(
            left: rect.left + translation.x,
            top: rect.top + translation.y,
            right: rect.right + translation.x,
            bottom: rect.bottom + translation.y
        )
    }
}
```

Delete `BrowserVisualEffect.swift`, `Blend.swift`, `BlurFilter.swift`, `Clip.swift`, `ScrollEffect.swift`, `Transform.swift`, `clone`, and `getLatest`.

Gate B2: build, tests, screenshots.

### B3. Flatten paint

Delete `DisplayEffect.swift`. `DisplayOp`:

```diff
-    case effect(DisplayEffect)
+    case beginEffect(EffectScope)
+    case endEffect
```

`PaintTree.paintTree` opens markers before painting and closes them after:

```swift
func paintTree(_ obj: any LayoutObject, into ops: inout [DisplayOp], session: inout PaintSession) {
    // culling unchanged: session.window replaces the old `window` parameter

    let start: Int = ops.count
    profiler.count("paint.nodes", by: 1)

    // cache checks unchanged; a cache hit appends and returns

    let scopes: [EffectKind] = obj.paintScopeKinds()   // [] for LineLayout
    var opened: [EffectScope] = []
    for kind in scopes {
        let scope: EffectScope = session.makeScope(
            kind,
            node: NodeKey(obj.node),
            animatedTransform: obj.node.animations["transform"] != nil
        )
        opened.append(scope)
        ops.append(.beginEffect(scope))
    }

    if obj.shouldPaint() {
        // block cache path unchanged, except `store(items: Array(ops[ownStart...]), ...)`
        obj.paint(into: &ops)
    }
    profiler.count("paint.own.items", by: ops.count - start - opened.count)

    // scroll / clip / iframe / children branches below

    for scope in opened.reversed() {
        let beginIndex: Int = ...   // saved when the marker was appended
        let rect: Rect = scopeRect(scope.kind, obj: obj, ops: ops, from: beginIndex + 1)
        ops[beginIndex] = .beginEffect(EffectScope(
            id: scope.id,
            kind: scope.kind,
            placement: EffectPlacement(
                rect: rect,
                node: scope.placement.node,
                animatedTransform: scope.placement.animatedTransform
            )
        ))
        ops.append(.endEffect)
    }
}
```

Keep `beginIndex` alongside the scope (a small local struct `OpenScope { let index: Int; let scope: EffectScope }`).

`obj.paintScopeKinds()` is a helper on `LayoutObject`:

```swift
func paintScopeKinds() -> [EffectKind] {
    if self is LineLayout { return [] }
    guard let style: PaintEffectStyle = profiler.measure("paint.effect.check", {
        paintEffectStyle(node: node)
    }) else { return [] }
    var kinds: [EffectKind] = [.transform(style.translation)]
    kinds.append(.blend(opacity: style.opacity, mode: style.blendMode))
    if style.blurRadius > 0 {
        kinds.append(.blur(radius: style.blurRadius))
    }
    return kinds
}
```

`scopeRect`:

```swift
func scopeRect(_ kind: EffectKind, obj: any LayoutObject, ops: [DisplayOp], from start: Int) -> Rect {
    switch kind {
    case .transform:
        return obj.selfRect()
    case .clip(let shape), .scroll(let shape, _):
        return shape.rect
    case .blend, .blur:
        var rect: Rect = .zero
        for index in start..<ops.count {
            if case .endEffect = ops[index] { continue }
            rect = rect.union(ops[index].rect)
        }
        return rect
    }
}
```

Scroll and clip branches open a marker at `childStart` before painting children and append `.endEffect` after, then append the scrollbar outside:

```swift
if let block = obj as? BlockLayout, block.node.style["overflow"] == "scroll" {
    let radii: CornerRadii = CSSValueParser.cornerRadii(block.node.style) ?? .zero
    let scroll: EffectScope = session.makeScope(
        .scroll(ClipShape(rect: block.selfRect(), radii: radii), offset: block.scrollOffset),
        node: NodeKey(block.node),
        animatedTransform: false
    )
    ops.append(.beginEffect(scroll))
    // paint visible children
    ops.append(.endEffect)
    ops.append(contentsOf: block.paintScrollbar())
}
```

`IframeLayout.paintEffects` is deleted. Move its geometry into a `paintIframe` helper in `PaintTree.swift`; open the internal `.blend(1, nil)` / `.transform` / `.clip` scopes before `obj.paint`, paint the child document, close clip/transform, append the child scrollbar, close blend, then append border and outline. Node scopes opened by `paintTree` stay outside.

Caches: `PaintCache` invalidates on `.beginEffect` / `.endEffect`; `LinePaintCache` accepts only `.text`/`.outline`. `shifted` precondition-fails on markers, as written in A1.

`DisplaySignature`:

```swift
for op in list {
    switch op {
    case .beginEffect(let scope):
        parts.append("beginEffect \(scope.kind) \(scope.placement.rect)")
    case .endEffect:
        parts.append("endEffect")
    default:
        parts.append("\(op.name) \(op.rect) \(op.contentHash)")
    }
}
```

`EffectKind` needs a printable form for the signature; write a `description` switch (`blend`, `blur`, `clip`, `transform`, `scroll`) with its values. Do not print `EffectScopeID`: incremental and full paints use different `paintRevision`s, and the oracle compares signatures across them.

Add `DisplayListRenderer.swift`:

```swift
public func renderDisplayList(_ ops: [DisplayOp], renderer: any Renderer) {
    var index: Int = 0
    renderDisplayRange(ops, index: &index, end: ops.count, renderer: renderer)
}

private func renderDisplayRange(
    _ ops: [DisplayOp],
    index: inout Int,
    end: Int,
    renderer: any Renderer
) {
    while index < end {
        switch ops[index] {
        case .beginEffect(let scope):
            let close: Int = matchingEnd(ops, from: index)
            applyEffect(scope.kind, renderer: renderer) { inner in
                var innerIndex: Int = index + 1
                renderDisplayRange(ops, index: &innerIndex, end: close, renderer: inner)
            }
            index = close + 1
        case .endEffect:
            return
        default:
            ops[index].execute(renderer: renderer)
            index += 1
        }
    }
}

private func matchingEnd(_ ops: [DisplayOp], from start: Int) -> Int {
    var depth: Int = 0
    var index: Int = start
    while index < ops.count {
        switch ops[index] {
        case .beginEffect:
            depth += 1
        case .endEffect:
            depth -= 1
            if depth == 0 { return index }
        default:
            break
        }
        index += 1
    }
    preconditionFailure("unbalanced display effect scope")
}
```

`DisplayOp.execute` no longer has an `.effect` case; markers `preconditionFailure` with a message pointing at `renderDisplayList`.

Replace the three manual loops:

- `Browser.swift:514-519` → `renderDisplayList(drawList, renderer: r)`
- `ScreenshotCapture.swift:29-35` → `renderDisplayList(browser.drawList, renderer: renderer)`
- `ToyStack.swift:69-71` → `renderDisplayList(chrome.paint(), renderer: chromeRenderer)`
- `CompositedLayer.raster` loops leaves; they contain no markers by construction. Keep `op.execute(renderer:)`.

`Frame.paint`:

```swift
var list: [DisplayOp] = []
list.reserveCapacity(displayList.count)
var session: PaintSession = PaintSession(paint: paintRevision, epoch: paintEpoch, window: window)
paintTree(doc, into: &list, session: &session)
displayList = list
```

Gate B3: build, tests, screenshots; confirm no `Array(displayList[...])` remains in `PaintTree.swift`.

### B4. Compose from the flat scan

`computeComposite` becomes one linear pass:

```swift
nonisolated static func computeComposite(
    _ inputs: RasterInput,
    measure: MeasureTime,
    frame: Int
) -> [CompositedLayer] {
    measure.start("raster.composite.scan", category: .raster, frame: frame)
    var compositedLayers: [CompositedLayer] = []
    var scopes: [EffectScope] = []
    var ordinals: [EffectScopeID?: Int] = [:]
    var animatedTransforms: Int = 0
    var assumeOverlap: Bool = false
    var commandIndex: Int = 0

    for op in inputs.scene.displayList {
        switch op {
        case .beginEffect(let scope):
            scopes.append(scope)
            if case .transform = scope.kind, scope.placement.animatedTransform {
                animatedTransforms += 1
            }
        case .endEffect:
            let scope: EffectScope = scopes.removeLast()
            if case .transform = scope.kind, scope.placement.animatedTransform {
                animatedTransforms -= 1
            }
        default:
            let scopeID: EffectScopeID? = scopes.last?.id
            if animatedTransforms > 0 { assumeOverlap = true }
            var merged: Bool = false
            for layer in compositedLayers.reversed() {
                if layer.id.effect == scopeID {
                    layer.add(op)
                    merged = true
                    break
                } else if assumeOverlap {
                    break
                }
            }
            if !merged {
                let ordinal: Int = ordinals[scopeID, default: 0]
                ordinals[scopeID] = ordinal + 1
                let layer: CompositedLayer = CompositedLayer(
                    displayItem: op,
                    firstCommandIndex: commandIndex,
                    id: LayerID(effect: scopeID, ordinal: ordinal)
                )
                layer.ancestorChain = Array(scopes.reversed())
                compositedLayers.append(layer)
            }
            commandIndex += 1
        }
    }
    reuseRasterization(from: inputs.scene.previousLayers, into: compositedLayers)
    measure.stop("raster.composite.scan")
    return compositedLayers
}
```

`CompositedLayer` gains `var firstCommandIndex: Int = -1` and an initializer `init(displayItem:firstCommandIndex:id:)`.

`computePaintDrawList` emits a flat stream that keeps scope markers and replaces the first command of each layer with one composited-layer op:

```swift
var layerByIndex: [Int: CompositedLayer] = [:]
for layer in layers where layer.firstCommandIndex >= 0 {
    layerByIndex[layer.firstCommandIndex] = layer
}

let scale: ContentScale = inputs.settings.viewport.scale
let viewportHeight: CGFloat = (inputs.settings.viewport.windowSize.height - inputs.settings.viewport.topInset) / scale.page
let visibleTop: CGFloat = inputs.scrollState.scroll - 2 * CompositedLayer.tileSize
let visibleBottom: CGFloat = inputs.scrollState.scroll + viewportHeight + 2 * CompositedLayer.tileSize

var commandIndex: Int = 0
var drawList: [DisplayOp] = []
drawList.reserveCapacity(inputs.scene.displayList.count)
for op in inputs.scene.displayList {
    switch op {
    case .beginEffect, .endEffect:
        drawList.append(op)
    default:
        if let layer: CompositedLayer = layerByIndex[commandIndex] {
            drawList.append(.compositedLayer(layer, layer.absoluteBounds(), visibleTop, visibleBottom))
        }
        commandIndex += 1
    }
}

// hovered / read bounds outlines unchanged
```

This preserves the old shared-prefix behavior: a scope is emitted once, and every layer under it appears inside that one range. It also preserves layer order, because a layer's op replaces its first command position.

Delete from `Browser.swift`: the effect-clone loop (`newEffects`, `mergedIntoExisting`, `getLatest`), `treeToList(DisplayItem)`, `addParentPointers`, `maxRectBottom`. Delete `walkDisplayItems` if nothing else uses it.

Test update in B4: `Tests/ToyStackTests/TileKeyTests.swift:21-23` replaces the `NSObject` identities with `EffectScopeID(paint: 0, ordinal: 0)` / `ordinal: 1` / `paint: 1`. The assertion shape stays the same.

Update `profiling.md`: `raster.composite.copy`+`.flatten` merge into `raster.composite.scan`.

Update `README.md:38`: the Display architecture line now reads `DisplayOp` construction, typed colors, effect scopes, `PaintTree`, scrollbar, focus ring.

Gate B4:

```sh
swift build
swift test
swift run ToyStackHeadless "file://$PWD/www/ch11/index.html" --trace /tmp/b4-effects.trace --frame-limit 5 --screenshot /tmp/b4-effects.png
swift run ToyStackHeadless "file://$PWD/www/ch11/exercise-11-3.html" --trace /tmp/b4-scroll.trace --frame-limit 5 --screenshot /tmp/b4-scroll.png
swift run -c release ToyStackHeadless "file://$PWD/www/bench/large-animated.html" --trace /tmp/b4-bench.trace --frame-limit 600 --no-profile
```

Compare both screenshots with the baselines. Confirm the release run finishes and `isRenderIdle` is reached (the scenario runner exits 0).

## Acceptance checklist

- `rg "any DisplayItem|any DisplayCommand|DisplayCommand|DrawRect|DrawText|DrawLine|DrawOutline|DrawRRect|DrawImage|DrawClippedImage|DrawCompositedLayer|ScrollbarBar" Sources Tests` returns no hits.
- `rg "BrowserVisualEffect|addParentPointers|maxRectBottom|needsCompositing|parentEffect|\\.clone\\(" Sources Tests` returns no hits.
- `rg "Array\\(displayList\\[|removeSubrange|replaceSubrange" Sources/Engine/Display` returns no hits.
- `Frame.displayList`, `RasterScene.displayList`, `RasterOutput.drawList`, `Browser.drawList`, `CompositedLayer.displayItems`, `TileStrip.items` are all `[DisplayOp]`.
- `CompositedLayer.displayItems` never contains `beginEffect`/`endEffect`/`compositedLayer` (leaves only). The layer constructor and `add` are the only writers.
- `PaintCache` invalidates on any marker or `.compositedLayer`; `LinePaintCache` only accepts `.text` / `.outline`.
- `displaySignature` does not print `EffectScopeID`.
- Both baseline screenshots match.
- `profiling.md` no longer documents `paint.range.copy` or `raster.composite.flatten`.

## Risks

| Risk | Mitigation |
|---|---|
| Scope rects differ from the old effect classes because the union is computed over a range instead of direct children | The range union is over the same ops the old tree wrapped; `.transform` keeps `selfRect()`, `.clip`/`.scroll` keep `ClipShape.rect`. Compare screenshot in B3. |
| Composited draw-list order changes | B4 emits the layer at its first command index and keeps the original marker order; verify against `/tmp/before-effects.png`. |
| Layer IDs change across paints and break tile reuse | `EffectScopeID.paint` keeps IDs stable within one paint and different across paints, matching the old object identity lifetime. |
| Animation fast path drops updates for non-`BlockLayout` nodes | B2 keeps the `(node.layoutObject as? BlockLayout) != nil` guard from `Frame.swift:985`. |
| Iframe internal scopes are easy to misorder | Move the structure verbatim: `blend(1) [ transform [ clip [ bg + childDoc ] ], bar ]`, then border/outline, all inside the node scopes. |
| `DisplayOp.rect` on `.endEffect` returns `.zero` | Only `beginEffect` scopes are unioned; `scopeRect` skips `.endEffect` explicitly. |

## Rollback

- A2 and B2 each delete files. Keep the branch history linear in `main`: each step is one commit, so `git revert <step>` restores the previous representation without touching unrelated work.
- Screenshot baselines are the stop signal. If A2 or B3 changes them, revert that step before starting the next.
