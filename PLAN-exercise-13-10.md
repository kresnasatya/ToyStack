# Plan: Exercise 13-10 — z-index

Right now paint order = document order: `paintTree` (Sources/Engine/DOMUtils.swift:230)
walks children top-to-bottom, so later elements draw on top. This exercise adds
`z-index`: among siblings, a bigger z-index draws on top; ties keep document
order; default is 0; it only counts when `position` is not `static`.

## Where we are today

- `paintTree` (Sources/Engine/DOMUtils.swift:230-263) paints `obj` first, then
  each child **in document order**, then wraps everything in visual effects.
  Each child's whole subtree is collected as one unit before it lands in `cmds`.
- The scroll branch (DOMUtils.swift:237-251) filters children by visibility
  using `continue`/`break` — the `break` assumes children are sorted by `y`,
  i.e. document order.
- `LayoutObject.hitTest` (Sources/Engine/Layouts/LayoutObject.swift:37) walks
  `children.reversed()` — reverse document order — so clicks land on whatever
  paints last. If paint order changes, click order must change with it.
- CSS side: nothing to do. `CSSParser` stores any `property: value` pair
  generically, so `position: relative` and `z-index: 3` already land in
  `node.style`. Layout ignores `position` (no offsets) — fine, we only use it
  as a gate.

## Files that change and why

| File | Why |
|------|-----|
| `Sources/Engine/DOMUtils.swift` | Add `effectiveZIndex` + `inPaintOrder` helpers; use them in both branches of `paintTree` |
| `Sources/Engine/Layouts/LayoutObject.swift` | `hitTest` must visit children in reverse **paint** order, not reverse document order, or clicks hit the wrong box |
| `www/ch13/exercise-13-10.html` / `.css` | Proof page (already created) |

## Design decision

**Option A (recommended): sort siblings at each tree level.**
At every node, stable-sort the children by z-index before recursing. Because
`paintTree` already collects each child's subtree into one block of commands,
a child's subtree moves as a unit. That gives you nested stacking contexts for
free: a child with `z-index: 999` inside a parent with `z-index: 1` can never
climb above the parent's sibling with `z-index: 2`, exactly like the MDN
stacking-context page describes.

**Option B: full spec stacking contexts.**
Real CSS says a positioned element with `z-index: auto` does *not* create a
stacking context — its positioned descendants escape upward and compete with
elements from other tree levels. Implementing that means collecting positioned
descendants up to the nearest ancestor context and painting in the spec's
seven-step order. Way more machinery for a case the book's toy layout (no real
`position` offsets) can't even produce visually.

Trade-off: Option A treats *every* element as its own stacking context. That is
stricter than the spec but self-consistent, and it is the same simplification
the book's own solutions make. Go with A.

## Steps

Each step leaves the project building.

### Step 1 — z-index helper (DOMUtils.swift)

Add near `paintTree`:

```swift
// z-index only applies to positioned elements (position != static).
// Everything else acts as z-index 0.
func effectiveZIndex(_ node: any DOMNode) -> Int {
    guard (node.style["position"] ?? "static") != "static" else { return 0 }
    return Int(node.style["z-index"] ?? "0") ?? 0
}

// Children in paint order: ascending z-index, ties keep document order.
// Swift's sorted() does not promise stability, so break ties with the
// original index instead of trusting it.
func inPaintOrder(_ children: [any LayoutObject]) -> [any LayoutObject] {
    return children.enumerated()
        .sorted { a, b in
            let za = effectiveZIndex(a.element.node)
            let zb = effectiveZIndex(b.element.node)
            return za == zb ? a.offset < b.offset : za < zb
        }
        .map { $0.element }
}
```

Builds unused — project still compiles.

### Step 2 — paint order, normal branch (DOMUtils.swift:252-255)

| Old | New |
|-----|-----|
| `for child in obj.children {` | `for child in inPaintOrder(obj.children) {` |
| `    paintTree(child, into: &cmds)` | `    paintTree(child, into: &cmds)` |
| `}` | `}` |

### Step 3 — paint order, scroll branch (DOMUtils.swift:241-246)

The `break` shortcut needs document (y) order, so filter first, sort after:

Old:

```swift
for child in obj.children {
    // skip children completely outside visible scroll
    if child.y + child.height < visibleTop { continue }
    if child.y > visibleBottom { break }
    paintTree(child, into: &childCmds)
}
```

New:

```swift
var visibleChildren: [any LayoutObject] = []
for child in obj.children {
    // skip children completely outside visible scroll
    if child.y + child.height < visibleTop { continue }
    if child.y > visibleBottom { break }
    visibleChildren.append(child)
}
for child in inPaintOrder(visibleChildren) {
    paintTree(child, into: &childCmds)
}
```

### Step 4 — hit testing follows paint order (LayoutObject.swift:37)

| Old | New |
|-----|-----|
| `for child in children.reversed() {` | `for child in inPaintOrder(children).reversed() {` |

Without this, box A drawn on top via z-index still sends clicks to box B
underneath — screen and mouse disagree.

### Step 5 — verify with www/ch13/exercise-13-10.html

Serve `www` the usual way and load the page. Expect:

1. Three overlapping boxes A, B, C. Document order is A, B, C, but z-index
   is A=3, C=1, B unset → paint order becomes B (bottom), C (middle),
   A (top). Without z-index support you'd see C on top.
2. B has `z-index: 5` but **no** `position`, so it must stay on the bottom —
   proves the `position != static` gate.
3. Nested pair: parent P1 (`z-index: 1`) holds a child with `z-index: 999`;
   sibling P2 has `z-index: 2`. P2 must cover the child — the child cannot
   escape its parent's stacking context.
4. Click each visible box: the JS-free check is visual, but if you wire a
   click listener, the topmost box should receive the click (Step 4).

## Notes

- Negative z-index works: `Int("-1")` parses, the child sorts before its
  siblings, but still paints after the parent's own background (parent's
  `paint()` commands go into `cmds` before any child at DOMUtils.swift:233-235).
  That matches the spec's "below siblings, above own stacking context's
  background".
- Compositing/raster untouched: `displayList` order is decided entirely at
  paint time, and the composite step just consumes the list.
- Accessibility tree hit test (AccessibilityNode.swift:69) still uses document
  order. Out of scope here; note it if screen-reader targeting ever matters.

## New colors needed in PaintCommand.swift

`www/ch13/exercise-13-10.css` uses three colors the engine doesn't know yet.
Add them to **both** color tables (`cssColorToRGB` at Sources/Engine/PaintCommand.swift:17
and `Color(cssName:)` at Sources/Engine/PaintCommand.swift:61), otherwise they
fall through to `nil` / black.

| CSS name | RGB | `cssColorToRGB` case | `Color(cssName:)` case |
|----------|-----|----------------------|------------------------|
| `tomato` | 255, 99, 71 | `case "tomato": return (255, 99, 71)` | `case "tomato": self = Color(red: 255 / 255, green: 99 / 255, blue: 71 / 255)` |
| `gold` | 255, 215, 0 | `case "gold": return (255, 215, 0)` | `case "gold": self = Color(red: 255 / 255, green: 215 / 255, blue: 0 / 255)` |
| `orchid` | 218, 112, 214 | `case "orchid": return (218, 112, 214)` | `case "orchid": self = Color(red: 218 / 255, green: 112 / 255, blue: 214 / 255)` |

Already supported, no change needed: `lightblue`, `lightgreen`, `steelblue`.
