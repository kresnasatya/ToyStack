# Resize reflow 2a — build the display list once, flat

Status: **ready to implement**. Second layout/perf commit out of
[`resize-reflow-remaining-work.md`](./resize-reflow-remaining-work.md), after
[`resize-reflow-1a-reuse-layout-tree.md`](./resize-reflow-1a-reuse-layout-tree.md).

Line numbers are from the current working tree.

---

## Why 2a, now

The 1a measurement (see its *1a measured* section) left the tick split like this on a
warm reflow:

```
layout   66.6 ms   (1a removed ~7 ms of font lookups; the rest is untouched)
paint    52.7 ms   ← nothing has touched this
```

Paint is the largest single term that no change has addressed, and 2a is the
mechanical half of it: 2b (paint only the changed subtrees) is the design-heavy half
and needs the dirty model. 2a is independent of layout, so it can land on its own and
be measured on its own.

---

## What the code does today

`PaintTree.swift:4-45` builds a **new array per object** and copies each finished
subtree up into its parent:

```swift
func paintTree(_ obj: any LayoutObject, into displayList: inout [any DisplayItem]) {
    var items: [any DisplayItem] = []          // :5   new array, per object
    if obj.shouldPaint() { items.append(contentsOf: obj.paint()) }
    ...
    for child in inPaintOrder(obj.children) {  // :37
        paintTree(child, into: &items)         //      child copies its subtree in
    }
    items = obj.paintEffects(items)            // :42  wrap, if any
    displayList.append(contentsOf: items)      // :44  copy the whole subtree up again
}
```

The last line is the problem. Every object's items are copied **once per level of
depth above them**, so an item at depth *d* is copied *d* times. For the parent plan's
~12k-item list across a tree a dozen or more levels deep, that is the cost, and it is
the diffuse `malloc` / `swift_retain` / `swift_release` the Round 3 profile showed.

### The wrinkle that makes this not a plain flatten

`paintEffects` (`:42`) can **wrap** a subtree. `BrowserVisualEffect.swift:33-72`
turns a node's items into `[Transform]` containing a `Blend` containing the items —
so a node's items are not simply concatenated into the parent, they can be replaced by
a single wrapper that owns them. Wrapping needs to know exactly which items belong to
this object:

| Implementation | Wrap rule |
|---|---|
| `LayoutObject` default (`LayoutObject.swift:23-26`) | wrap only if the node has an effect |
| `IframeLayout` (`IframeLayout.swift:61`) | **always** wraps, in a `Clip` |
| `EmbedLayout` (`EmbedLayout.swift:34`) | same as the default (redundant) |

So 2a cannot just thread one accumulator and append — it has to remember where each
object's own items start, and only pay a copy for the objects that really wrap.

---

## Design decision (pick one)

The naive version — keep `paintEffects(_ items:)`, and slice `Array(acc[start...])` for
every object before calling it — copies for *every* object, which is no better than
today. The copy has to be conditional on "will this object wrap?". That is the one
decision:

**Option A — add a second method `hasPaintEffects()` and gate the slice on it.**

Cheap and additive, but now there are two methods per type that must agree, and
`IframeLayout` always wraps, so it needs an override too. If the two ever disagree,
`IframeLayout` silently loses its clip and iframe content spills out of the frame.
That is a correctness bug produced by a perf-driven split — bad trade.

**Option B — move the decision into `paintEffects` by handing it the accumulator and
where this object's items start. (Recommended.)**

One method per type, one place that decides, no possible disagreement:

```swift
func paintEffects(into items: inout [any DisplayItem], from start: Int)
```

The default slices only when the node really has an effect; `IframeLayout` overrides
it and wraps as it already does. The cost is that the signature is less pretty and
`IframeLayout`'s override needs a mechanical rewrite.

---

## Three traps found while scoping this

1. **`IframeLayout` wraps unconditionally.** Any gate that keys off CSS properties
   alone will be wrong for it, which is why Option B is recommended over A.
2. **`mix-blend-mode` cannot be re-derived from the enum's `rawValue`.** The cases are
   `normal` / `multiply` / `difference` / `destinationIn`
   (`BrowserBlendMode.swift:3-8`), but the CSS value is `destination-in`, with a
   hyphen. `BrowserBlendMode(rawValue: "destination-in")` returns `nil`. The condition
   that decides "does this node blend" must go through the one switch that knows the
   hyphen, or the gate and the wrap will disagree on `destination-in`.
3. **A subclass cannot override a protocol-extension default.** `IframeLayout` is a
   subclass of `EmbedLayout` (`IframeLayout.swift:5`), and `EmbedLayout` only gets
   `paintEffects` from the extension. Both ways of writing it in `IframeLayout` are
   wrong:

   | Written as | Result |
   |---|---|
   | `override func paintEffects(into:from:)` | **does not compile** — "does not override any method from its superclass" |
   | `func paintEffects(into:from:)` (no `override`) | compiles, but **is never called** — a call through `any LayoutObject` reaches the extension default |

   `paintTree` calls `obj.paintEffects(...)` on the existential, so the second case
   silently drops iframe clipping. Verified both ways. Fix: `EmbedLayout` declares the
   method **in its own class body**, which makes the subclass `override` real.

   This is the mirror image of the 1a lesson. There, the method had to be a protocol
   *requirement* so the `BlockLayout` implementation would be found through the
   witness table. Here it must be a *superclass member* so the override dispatch works.
   A method that is only an extension default is not overridable at all.

---

## Files that change

| File | Why |
|---|---|
| `Sources/Engine/Display/PaintTree.swift` | paint into the caller's list; copy only for effect wraps |
| `Sources/Engine/Layouts/LayoutObject.swift` | new `paintEffects(into:from:)` requirement + default |
| `Sources/Engine/Display/BrowserVisualEffect.swift` | resolve the effect properties once, via `paintEffectStyle` |
| `Sources/Engine/Display/PaintEffectStyle.swift` | **new** — the resolved effect properties |
| `Sources/Engine/Display/BrowserBlendMode.swift` | the CSS → `BrowserBlendMode` switch, in one place |
| `Sources/Engine/Layouts/IframeLayout.swift` | rewrite the override for the new signature |
| `Sources/Engine/Layouts/EmbedLayout.swift` | keep a class-body declaration so `IframeLayout` can override it |
| `Sources/Engine/Core/Frame.swift` | reserve the list against the previous frame's size |

---

## Diffs

### `Sources/Engine/Display/PaintEffectStyle.swift` (new file)

The properties that decide a wrap, resolved once so the gate and the wrap can never
disagree. Named and placed after the type it holds, per the code-architecture rule.

```diff
+import CoreGraphics
+
+// MARK: - PaintEffectStyle
+
+/// The resolved effect properties that put a node's subtree into its own stacking
+/// context. Resolved once, so the check for "is there an effect" and the wrap itself
+/// always agree.
+struct PaintEffectStyle {
+    let borderRadius: CGFloat
+    let opacity: Double
+    let blendMode: BrowserBlendMode?
+    let translation: CGPoint?
+    let blurRadius: CGFloat
+}
+
+// MARK: - Resolution
+
+/// `nil` when there is nothing to wrap — the common case, and the cheap path.
+func paintEffectStyle(node: DOMNode) -> PaintEffectStyle? {
+    let opacity: Double = Double(node.style["opacity"] ?? "1.0") ?? 1.0
+    let blendMode: BrowserBlendMode? = browserBlendMode(node.style["mix-blend-mode"])
+    let translation: CGPoint? = CSSValueParser.transform(node.style["transform"] ?? "")
+    let radiusStr: String = (node.style["border-radius"] ?? "0px").replacingOccurrences(
+        of: "px", with: "")
+    let borderRadius: CGFloat = CGFloat(Double(radiusStr) ?? 0)
+    let blurRadius: CGFloat = CSSValueParser.blur(node.style["filter"] ?? "")
+    let animated: Bool = node.animations["transform"] != nil || node.animations["opacity"] != nil
+
+    guard borderRadius > 0 || blurRadius > 0 || opacity < 1
+        || (blendMode != nil && blendMode != .normal)
+        || translation != nil || animated
+    else { return nil }
+
+    return PaintEffectStyle(
+        borderRadius: borderRadius, opacity: opacity, blendMode: blendMode,
+        translation: translation, blurRadius: blurRadius)
+}
```

### `Sources/Engine/Display/BrowserBlendMode.swift`

The switch that maps the CSS string onto the enum moves here, next to the enum it
builds. One caller with the hyphen rule in it, not two.

```diff
 public enum BrowserBlendMode: String {
     case normal
     case multiply
     case difference
     case destinationIn
 }
 
+// MARK: - CSS value
+
+/// The CSS `mix-blend-mode` value, or `nil` for anything this engine does not
+/// implement. Note `destination-in` — the hyphen means this cannot be a
+/// `rawValue` lookup against the case name.
+func browserBlendMode(_ css: String?) -> BrowserBlendMode? {
+    switch css {
+    case "multiply": return .multiply
+    case "difference": return .difference
+    case "destination-in": return .destinationIn
+    default: return nil
+    }
+}
+
 extension BrowserBlendMode {
```

### `Sources/Engine/Display/BrowserVisualEffect.swift`

`paintBrowserVisualEffects` keeps its signature — `Frame.swift:791` still calls it for
the animation scan — but its guard and its readings come from `paintEffectStyle`.

```diff
 func paintBrowserVisualEffects(node: DOMNode, items: [any DisplayItem], rect: Rect) -> [any DisplayItem] {
-    let opacity: Double = Double(node.style["opacity"] ?? "1.0") ?? 1.0
-    let blendModeStr: String? = node.style["mix-blend-mode"]
-    let translation: CGPoint? = CSSValueParser.transform(node.style["transform"] ?? "")
-    let radiusStr: String = (node.style["border-radius"] ?? "0px").replacingOccurrences(of: "px", with: "")
-    let borderRadius: CGFloat = CGFloat(Double(radiusStr) ?? 0)
-    let blurRadius: CGFloat = CSSValueParser.blur(node.style["filter"] ?? "")
-
-    let blendMode: BrowserBlendMode? = {
-        switch blendModeStr {
-        case "multiply": return .multiply
-        case "difference": return .difference
-        case "destination-in": return .destinationIn
-        default: return nil
-        }
-    }()
-    let animated: Bool = node.animations["transform"] != nil || node.animations["opacity"] != nil
-    guard borderRadius > 0 || blurRadius > 0 || opacity < 1
-        || (blendMode != nil && blendMode != .normal)
-        || translation != nil || animated
-    else { return items }
+    guard let style: PaintEffectStyle = paintEffectStyle(node: node) else { return items }
+    let opacity: Double = style.opacity
+    let blendMode: BrowserBlendMode? = style.blendMode
+    let translation: CGPoint? = style.translation
+    let borderRadius: CGFloat = style.borderRadius
+    let blurRadius: CGFloat = style.blurRadius
 
     var displayItems: [any DisplayItem] = items
     if borderRadius > 0 {
```

The rest of the function is unchanged.

### `Sources/Engine/Layouts/LayoutObject.swift`

Replace the wrap method with the accumulator form. Like `layout(reusesChildren:)` in
1a, this must be a **protocol requirement**, or the implementation would be skipped.

```diff
     func layout(reusesChildren: Bool)
     func paint() -> [any DisplayItem]
     func shouldPaint() -> Bool
-    func paintEffects(_ items: [any DisplayItem]) -> [any DisplayItem]
+    /// Wrap the items this object just painted, if it has an effect to apply.
+    /// `start` is where those items begin in `items`; the default leaves them
+    /// alone, so most objects finish with no copy of their own subtree.
+    func paintEffects(into items: inout [any DisplayItem], from start: Int)
 
 }
 
 extension LayoutObject {
-    func paintEffects(_ items: [any DisplayItem]) -> [any DisplayItem] {
-        if self is LineLayout { return items }
-        return paintBrowserVisualEffects(node: node, items: items, rect: selfRect())
+    func paintEffects(into items: inout [any DisplayItem], from start: Int) {
+        applyPaintEffects(into: &items, from: start)
+    }
+
+    /// The shared wrap. Kept separate from the requirement above so that a
+    /// class-body `paintEffects` — the one subclasses override — can call the
+    /// default without recursing into itself.
+    func applyPaintEffects(into items: inout [any DisplayItem], from start: Int) {
+        if self is LineLayout || paintEffectStyle(node: node) == nil { return }
+        let produced: [any DisplayItem] = Array(items[start...])
+        let wrapped: [any DisplayItem] = paintBrowserVisualEffects(
+            node: node, items: produced, rect: selfRect())
+        items.replaceSubrange(start..<items.count, with: wrapped)
     }
```

### `Sources/Engine/Display/PaintTree.swift`

The whole function. Each object's items go straight into the caller's list; the only
copy left is the one an effect wrap genuinely needs.

```diff
 @MainActor
 func paintTree(_ obj: any LayoutObject, into displayList: inout [any DisplayItem]) {
-    var items: [any DisplayItem] = []
+    // Everything this object paints goes straight into the caller's list. The only
+    // reason to know where our own items begin is the effect wrap at the end, which
+    // needs exactly this object's items and nothing else.
+    let start: Int = displayList.count
 
     if obj.shouldPaint() {
-        items.append(contentsOf: obj.paint())
+        displayList.append(contentsOf: obj.paint())
     }
 
     if let block = obj as? BlockLayout, block.node.style["overflow"] == "scroll" {
-        var childItems: [any DisplayItem] = []
+        let childStart: Int = displayList.count
         let visibleTop: CGFloat = block.y + block.scrollOffset
         let visibleBottom: CGFloat = visibleTop + block.height
         var visibleChildren: [any LayoutObject] = []
         for child in obj.children {
             if child.y + child.height < visibleTop { continue }
             if child.y > visibleBottom { break }
             visibleChildren.append(child)
         }
         for child in inPaintOrder(visibleChildren) {
-            paintTree(child, into: &childItems)
+            paintTree(child, into: &displayList)
         }
+        // The scroll effect owns its children, so this one copy is unavoidable.
+        let childItems: [any DisplayItem] = Array(displayList[childStart...])
+        displayList.removeSubrange(childStart..<displayList.count)
         let effect: ScrollEffect = ScrollEffect(
             rect: block.selfRect(),
             scrollOffset: block.scrollOffset,
             node: block.node,
             children: childItems
         )
-        items.append(effect)
-        items.append(contentsOf: block.paintScrollbar())
+        displayList.append(effect)
+        displayList.append(contentsOf: block.paintScrollbar())
     } else if let iframe = obj as? IframeLayout,
         let childFrame = (iframe.node as? Element)?.frame, childFrame.loaded,
         let childDoc = childFrame.document {
-        paintTree(childDoc, into: &items)
+        paintTree(childDoc, into: &displayList)
     } else {
         for child in inPaintOrder(obj.children) {
-            paintTree(child, into: &items)
+            paintTree(child, into: &displayList)
         }
     }
 
-    items = obj.paintEffects(items)
-
-    displayList.append(contentsOf: items)
+    // Wrapping copies, so only the few objects that have an effect do it.
+    // Everything else finishes without copying its own subtree at all.
+    obj.paintEffects(into: &displayList, from: start)
 }
```

### `Sources/Engine/Layouts/IframeLayout.swift`

Mechanical: the body is unchanged, it just works on the range instead of a parameter.
Note it wraps **unconditionally**, which is why the gate cannot live in the caller.

```diff
-    override func paintEffects(_ items: [any DisplayItem]) -> [any DisplayItem] {
+    override func paintEffects(into items: inout [any DisplayItem], from start: Int) {
         let rect: Rect = selfRect()
         let diff: CGFloat = scaled(1)
         let scroll: CGFloat = (frame?.loaded ?? false) ? (frame?.scroll ?? 0) : 0
         ...
+        let produced: [any DisplayItem] = Array(items[start...])
         let clip: Clip = Clip(
             rect: innerRect,
             clipRect: clipRect,
             node: nil,
-            children: items
+            children: produced
         )
         ...
-        return paintBrowserVisualEffects(node: node, items: cmds, rect: rect)
+        let wrapped: [any DisplayItem] = paintBrowserVisualEffects(node: node, items: cmds, rect: rect)
+        items.replaceSubrange(start..<items.count, with: wrapped)
     }
```

(Only `children: items` and the final `return` change; the middle of the function is
untouched.)

### `Sources/Engine/Layouts/EmbedLayout.swift`

Do **not** delete the method (an earlier version of this plan said to, and that is what
broke the build). `EmbedLayout` is the superclass of `IframeLayout`, `CanvasLayout` and
`ImageLayout`; its class-body declaration is what makes `IframeLayout`'s `override`
real. The body moves to the shared `applyPaintEffects` so there is nothing to drift.

```diff
     func shouldPaint() -> Bool { true }
     func paint() -> [any DisplayItem] { [] }
+
+    // Declared here, not just taken from the protocol default, so subclasses can
+    // override it. A method that exists only as a protocol-extension default is
+    // not overridable through `any LayoutObject` — the call silently reaches the
+    // default instead. See trap 3.
+    func paintEffects(into items: inout [any DisplayItem], from start: Int) {
+        applyPaintEffects(into: &items, from: start)
+    }
 }
```

### `Sources/Engine/Core/Frame.swift`

A frame's item count barely changes between reflows, so reserve against the previous
list instead of growing from empty. `displayList` still holds the previous frame at
this point (`:765` assigns it later).

```diff
         guard let doc = document else { return }
         var list: [any DisplayItem] = []
+        list.reserveCapacity(displayList.count)
         paintTree(doc, into: &list)
```

---

## Correctness notes

- **Order is unchanged.** Items go into the list in the same depth-first order as
  before, so the display list is byte-for-byte the same sequence of items.
- **The scroll branch keeps its structure.** The block's own items are painted before
  `childStart`, so they stay *outside* the `ScrollEffect` — same as when they lived in
  `items` before the effect was appended.
- **`LineLayout` still never wraps** (`self is LineLayout`), matching today.
- **`IframeLayout` still always wraps**, because the decision is in its own override.

---

## Order of work

1. `BrowserBlendMode.swift`, `PaintEffectStyle.swift`, `BrowserVisualEffect.swift` —
   the resolution refactor, behaviour-free. Builds and looks identical.
2. `LayoutObject.swift`, `EmbedLayout.swift`, `IframeLayout.swift` — the signature
   change, all three together: without `EmbedLayout`'s class-body declaration the
   `IframeLayout` `override` will not compile (trap 3), and without
   `applyPaintEffects` on the extension the default has nowhere to delegate.
3. `PaintTree.swift`, `Frame.swift` — the flat list.
4. Run the app, resize, and diff a screenshot against the previous build. The display
   list should be identical in content, so a pixel diff should be empty.

---

## How to check it worked

**The win.** `BrowserTab.paint` average and p50 from `browser.trace`. Baseline from
the 1a trace is **52.7 ms avg, 52.6 ms p50**. Per the parent plan, sample rather than
trust one span: `paintTree` is a single span, so attach
`sample` to a long page and read `Frame.paint()`'s branch shares.

**Nothing regressed in the raster cache, and this is the important one.** 2a touches
the list the tile hash is built from (`CompositedLayer.swift:170`,
`DisplayCommand.swift:11`). Unchanged frames must still report
`{hits: N, misses: 0}` — the 1a trace has 52 such events, so the check has a known
good value to compare against. If `hits` collapses to 0, the flat list produced a
different sequence (or a different set) of items and the hash stopped being stable.

```bash
python3 -c "
import json
d = json.load(open('browser.trace'))
t=[e['args'] for e in d['traceEvents'] if e.get('ph')=='C' and e.get('name')=='tiles']
print('hits>0 misses==0:', sum(1 for x in t if x['hits']>0 and x['misses']==0))
print('hits==0 misses>0:', sum(1 for x in t if x['hits']==0 and x['misses']>0))
"
```

---

## Sequencing: do items 3 and 4 first

The parent plan's items **3** (`border-radius` string replace) and **4**
(`inPaintOrder` sorting) are ten-minute changes that sit *inside* the code 2a
rewrites:

- Item 3's hot site is `BrowserVisualEffect.swift:37` — the exact line 2a moves into
  `PaintEffectStyle.swift`. Landing 3 first means `paintEffectStyle` is written with
  `CSSValueParser.px(...)` from the start, instead of the string replace above.
- Item 4 is `PaintTree.swift:54-62`, and both of its call sites (`:21`, `:37`) are
  lines 2a is already editing.

Doing them first keeps 2a's measurement clean — otherwise a paint improvement could
come from any of three changes and you could not attribute it. Neither is required for
2a to work; they just remove a confound.

---

## Explicitly out of scope

- **2b — paint only what changed.** The design-heavy half: either keep the display list
  per subtree and rebuild dirty ones, or teach `setNeedsPaint` the difference between
  "geometry changed" and "text moved". Same dirty model as 1b/1c; its own plan.
- **`maxRectBottom` (`Frame.swift:764`).** It walks the whole list a second time after
  paint. With a flat list most items are nested inside effects, so it is still a full
  tree walk — but it is one walk with no allocation. Measure it before touching it;
  likely a millisecond or two, not worth folding into 2a.
- **`paint()` / `paintEffects()` building new structs per node per paint.** Same
  measure-first stance.
- **Item 5 (breakpoint re-cascade), item 6 (presentation latency), item 7
  (horizontal overflow).** Untouched.

## Related

- `resize-reflow-1a-reuse-layout-tree.md` — the layout half, and the measured baseline
  these numbers come from.
- `resize-reflow-remaining-work.md` — items 1–7 and where 2a sits.
- `profiling.md` — trace format, `MeasureTime` vs `Profiler`, `--no-profile`.
