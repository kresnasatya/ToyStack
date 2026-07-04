# Plan: Exercise 13-9 — Hit Testing

Convert the click location into each layout object's coordinate space while
walking the layout tree, instead of converting every object's bounds to
absolute coordinates (or, in our port's case, scanning flattened paint
commands).

## Where we are today

`Tab.click` (Sources/Engine/Tab.swift:797-815) flattens the display list and
tests the click point against each paint command's rect, picking the last
(topmost) command that carries a `source` layout object.

Two problems:

1. **It ignores transforms.** Paint command rects are recorded *before* the
   `Transform` visual effect moves them, and `flattenCommands`
   (Tab.swift:785-795) walks into visual effects without applying their
   offsets. A box with `transform: translate(150px, 40px)` is clickable at
   its *old* spot, not where you see it on screen.
2. **The book-style helper is dead and wrong.** `absoluteBoundsForObj`
   (Sources/Engine/DOMUtils.swift:553), `localToAbsolute` (:476) and
   `absoluteToLocal` (:494) are never called. They also sum every ancestor's
   `x`/`y` — but our layout coordinates are already absolute
   (`x = parent!.x` at BlockLayout.swift:54, `y = previous.y + height` at
   :73), so they would double-count positions. Only the *transform* offsets
   need accumulating.

## Design decision

- **Option A (recommended): one `hitTest` default implementation in a
  `LayoutObject` protocol extension** (Sources/Engine/Layouts/LayoutObject.swift).
  All five layout classes need identical logic; the only per-object
  difference — the transform — is read from `node.style`. Zero duplication.
- **Option B: add `hitTest` as a protocol requirement and implement it in
  each class** (DocumentLayout, BlockLayout, LineLayout, TextLayout,
  InputLayout). Book-literal, but five identical copies.

Trade-off: protocol-extension methods dispatch statically, so a future
layout type could not override Option A's `hitTest` through the protocol.
If that day comes (e.g. an iframe layout that re-maps the point into a
child frame), promote it to a protocol requirement then. Until then A wins.

## Key correctness rules inside `hitTest`

1. **Subtract this object's own transform first.** A transform visually
   moves the box *and* everything it paints, so the click point moves the
   opposite way before any comparison — including against this object's own
   rect. (Matches the book's `absolute_bounds_for_obj`, which starts mapping
   at `obj.node` itself.)
2. **Search children before self, in reverse order.** Later siblings paint
   on top; the deepest, topmost object must win — same answer the old
   `hits.last` gave.
3. **Never skip children because the point missed this object's box.**
   `position: absolute` children (BlockLayout.swift:48-55) and transformed
   children can sit entirely outside the parent's rect.

## Steps (each leaves the project building)

1. Add `hitTest(x:y:)` to Sources/Engine/Layouts/LayoutObject.swift as a
   protocol extension. Old click path untouched.
2. Rewire `Tab.click` (Tab.swift:797-815) to call
   `document.hitTest(x: x, y: y + scroll)`. Everything from
   `scrollFocusNode = ...` (line 817) down is unchanged.
3. Build; open `www/ch13/exercise-13-9.html`; run the manual checklist below.
4. Cleanup (only after step 3 passes):
   - `sourceOf` (Tab.swift:777-783) and `flattenCommands` (Tab.swift:785-795)
     — only the old click used them.
   - `localToAbsolute` (DOMUtils.swift:476-492), `absoluteToLocal`
     (:494-514), `absoluteBoundsForObj` (:553-557) — dead.
   - Optional: the `source` fields on DrawRect / DrawRRect / DrawText /
     DrawLine (PaintCommand.swift) only feed `sourceOf`. Removing them
     touches every `paint()` call site — verify with a grep for `source:`
     before deciding; fine to keep if it gets noisy.

## Manual test checklist (www/ch13/exercise-13-9.html)

- Click each box **where you see it** — status line reports the right id.
- Click box 2's original (pre-transform) spot — must NOT report box 2.
  The old code fails this; the new code passes.
- Box 3 sits inside a transformed parent and has its own transform —
  clicking its visual position proves offsets accumulate down the tree.
- Click the overlap of boxes 4 and 5 — reports 5 (painted later, on top).

## Behavior notes

- `DocumentLayout` spans the whole page, so clicking empty space now
  returns the root object and dispatches a JS `click` on the root node
  before the anchor/input walk finds nothing. Same as the book; harmless.
- Scrolling is handled exactly as before: `y + scroll` once at the entry
  point, since layout coordinates are document-absolute.

## Full code

### Step 1 — `hitTest` (new, Sources/Engine/Layouts/LayoutObject.swift)

Add below the `LayoutObject` protocol declaration:

```swift
// MARK: - Hit Testing (Exercise 13-9)
// Walk the layout tree converting the click point into each object's
// coordinate space, instead of converting every object's bounds to
// absolute coordinates. Only transforms need mapping: our layout x/y
// are already document-absolute.
extension LayoutObject {
    func hitTest(x: CGFloat, y: CGFloat) -> (any LayoutObject)? {
        var x = x
        var y = y

        // A transform moves this box and everything it paints, so the
        // click point moves the opposite way before any comparison —
        // including against this object's own rect.
        if let t = parseTransform(node.style["transform"] ?? "") {
            x -= t.x
            y -= t.y
        }

        // Children first, in reverse: later siblings paint on top, and
        // the deepest, topmost object must win (same answer the old
        // `hits.last` gave). Never skip children just because the point
        // missed this object's box — position:absolute and transformed
        // children can sit entirely outside the parent's rect.
        for child in children.reversed() {
            if let hit = child.hitTest(x: x, y: y) {
                return hit
            }
        }

        if self.x <= x && x < self.x + width
            && self.y <= y && y < self.y + height
        {
            return self
        }
        return nil
    }
}
```

### Step 2 — rewire `Tab.click` (Sources/Engine/Tab.swift:797-815)

Old:

```swift
public func click(x: CGFloat, y: CGFloat) {
    focusElement(nil)

    let adjustedY = y + scroll
    let allCmds = flattenCommands(displayList)

    let hits = allCmds.filter({ cmd in
        return cmd.rect.left <= x && x < cmd.rect.right
            && cmd.rect.top <= adjustedY && adjustedY < cmd.rect.bottom
    })

    guard
        let source = hits.last(where: { sourceOf($0) != nil }).flatMap({
            sourceOf($0)
        })
    else {
        setNeedsRender()
        return
    }
```

New:

```swift
public func click(x: CGFloat, y: CGFloat) {
    focusElement(nil)

    // Layout coordinates are document-absolute, so scroll is applied
    // once here; hitTest only has to undo transforms on the way down.
    guard let source = document?.hitTest(x: x, y: y + scroll) else {
        setNeedsRender()
        return
    }
```

Everything from `scrollFocusNode = scrollableAncestor(of: source)`
(Tab.swift:817) down is unchanged.

### Step 4 — cleanup (only after the manual checklist passes)

Delete:

- `sourceOf` — Sources/Engine/Tab.swift:777-783
- `flattenCommands` — Sources/Engine/Tab.swift:785-795
- `localToAbsolute` — Sources/Engine/DOMUtils.swift:476-492
- `absoluteToLocal` — Sources/Engine/DOMUtils.swift:494-514
- `absoluteBoundsForObj` — Sources/Engine/DOMUtils.swift:553-557

Optional (decide after `grep -rn "source:" Sources/`): drop the `source`
fields on DrawRect / DrawRRect / DrawText / DrawLine in PaintCommand.swift
— they only fed `sourceOf`. Fine to keep if removal gets noisy.

## Missing colors (www/ch13/exercise-13-9.css)

The test page uses two color names PaintCommand.swift doesn't know:
`whitesmoke` (.outer) and `khaki` (#inner). Unknown names fall through to
`nil` / `.black`, so those boxes would paint wrong. Add a case to **both**
switches:

### 1. `cssColorToRGB` (PaintCommand.swift:17-33) — add before `default`:

```swift
case "whitesmoke": return (245, 245, 245)
case "khaki": return (240, 230, 140)
```

### 2. `Color(cssName:)` (PaintCommand.swift:59-76) — add before `default`:

```swift
case "whitesmoke": self = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
case "khaki": self = Color(red: 240 / 255, green: 230 / 255, blue: 140 / 255)
```

Already covered: `lightgray`, `lightblue`, `gray`, `salmon`.

Side note: existing `lightgray` entry in `cssColorToRGB`
(PaintCommand.swift:28) returns `(211, 211, 217)` — standard CSS value is
`(211, 211, 211)`. Likely a typo; harmless for this exercise.
