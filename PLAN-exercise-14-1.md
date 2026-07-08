# Plan: Exercise 14-1 — Focus ring with good contrast

## Problem

The focus ring is one solid color:

- `Sources/Engine/Layouts/LineLayout.swift:96-102` paints a single
  `DrawOutline` around the focused element. Color comes from the CSS
  `outline` rule.
- `Sources/Engine/Resources/browser.css:146-157` sets that outline to
  **black** in light mode; the dark-mode block (lines 178-200) sets it
  to **white**.

A single color can never guarantee contrast: a black ring disappears on
a dark page background, a white ring disappears on a light one — and the
media query only tracks the OS theme, not the actual pixels behind the
ring (a page can paint a black `div` in light mode).

## Fix (the exercise)

Always paint **two** rings, back to front:

1. A **thicker white** ring first (it ends up underneath).
2. A **thinner black** ring on top.

`DrawOutline` strokes are centered on the rectangle edge, so the wider
white ring peeks out on *both* sides of the black one. Result: a black
line with a white halo — the black core is visible on light content, the
white halo is visible on dark content. Contrast guaranteed everywhere,
no theme check needed.

## Design decision

- **Option A (recommended): hardcode white + black.** Ignore
  `outline-color` from CSS entirely. Guaranteed contrast — which is the
  whole point of the exercise. Trade-off: a page (or our dark-mode CSS)
  can no longer recolor the focus ring.
- **Option B: outer ring always white, inner ring = CSS
  `outline-color`.** Keeps page control of the ring color. Trade-off: a
  page that sets `outline-color: white` gets an invisible inner ring
  again — contrast is no longer guaranteed, defeating the exercise.

Going with **Option A**, matching the book's wording ("a thicker white
one and a thinner black one").

## Steps

Each step leaves the project building (`swift build`).

### Step 0 — Tab.swift: fix Tab-key focus (prerequisite bugs)

Found while testing: pressing Tab appears to do nothing. The key *is*
wired (`Sources/ToyStack/ToyStack.swift:117-125`, keyCode 48 →
`advanceTab()`) and focus even moves internally — but two bugs hide it.
Without this step the exercise can't be verified at all.

**Bug 0a — focus change never repaints.**
`focusElement` (`Sources/Engine/Tab.swift:778-785`) sets `isFocused`
but never schedules a repaint, so the ring is never painted. Compare
`blur()` right above it (`Tab.swift:771-776`), which does call
`setNeedsRender()`. The book's `focus_element` ends with
`self.set_needs_render()` — the port dropped it.

**Old** (`Sources/Engine/Tab.swift:778-785`):

```swift
func focusElement(_ node: Element?) {
    if let node = node, node !== focus {
        needsFocusScroll = true
    }
    focus?.isFocused = false
    focus = node
    node?.isFocused = true
}
```

**New** (one line added at the end):

```swift
func focusElement(_ node: Element?) {
    if let node = node, node !== focus {
        needsFocusScroll = true
    }
    focus?.isFocused = false
    focus = node
    node?.isFocused = true
    setNeedsRender()
}
```

**Bug 0b — links never focusable.**
`advanceTab` (`Sources/Engine/Tab.swift:789-794`) walks the **layout**
tree (`treeToList(doc)`, where `doc` is the `DocumentLayout`). An `<a>`
element has no layout object of its own — its text becomes a text
layout whose `node` is the TextNode, not the `a` element — so the Tab
order only ever contains `input`/`button` and skips every link. The
book walks the **DOM** instead. The Tab already holds the DOM root
(`nodes`, `Tab.swift:12`) and a DOM overload of `treeToList` exists
(`Sources/Engine/DOMUtils.swift:194`); Swift picks that overload
automatically from the argument type.

**Old** (`Sources/Engine/Tab.swift:789-794`):

```swift
guard let doc = document else { return false }
let focusableElements = treeToList(doc).compactMap({ obj -> Element? in
    guard let el = obj.node as? Element else { return nil }
    let tag = el.tag
    return (tag == "input" || tag == "button" || tag == "a") ? el : nil
})
```

**New** (walk the DOM; keep the guard as a "page loaded" check):

```swift
guard document != nil else { return false }
let focusableElements = treeToList(nodes).compactMap({ n -> Element? in
    guard let el = n as? Element else { return nil }
    let tag = el.tag
    return (tag == "input" || tag == "button" || tag == "a") ? el : nil
})
```

Notes:
- Option+Tab needs no handling — plain Tab already reaches the handler;
  only Ctrl+Tab differs (cycles browser tabs).
- After the last focusable element, Tab intentionally jumps to the
  address bar (`Tab.swift:802-803` returns `false` →
  `ToyStack.swift:122`). That's existing, correct behavior.

**Bug 0c — LineLayout checks the wrong node, so link rings never paint.**
Found after applying 0a/0b: Tab now reaches links internally, but the
ring stays invisible on them. `LineLayout.paint`
(`Sources/Engine/Layouts/LineLayout.swift:92-95`) checks
`child.node.isFocused`, and for a link the line's children are text
layouts whose `node` is the **TextNode** inside the `<a>` — never the
`<a>` element that `focusElement` marked focused. Inputs/buttons are
unaffected because they own their layout objects. Same layout-vs-DOM
mismatch as Bug 0b; the book's `paint_outline` reads
`child.node.parent` for exactly this reason.

**Old** (`Sources/Engine/Layouts/LineLayout.swift:92-95`):

```swift
var focusedNode: DOMNode? = nil
for child in children {
    if child.node.isFocused { focusedNode = child.node }
}
```

**New** (also check the text node's parent; `parent` is
`(any DOMNode)?` per `Sources/Engine/DOMNode.swift:9`, hence the type
change):

```swift
var focusedNode: (any DOMNode)? = nil
for child in children {
    if child.node.isFocused {
        focusedNode = child.node
    } else if let parent = child.node.parent, parent.isFocused {
        focusedNode = parent
    }
}
```

Note: the ring rect is `selfRect()` — the full line width — so a
focused link's ring spans the whole line rather than hugging the link
text. Optional later polish; not needed for the exercise.

### Step 1 — LineLayout.swift (the focus ring itself)

Replace the single outline with the white+black pair.

**Old** (`Sources/Engine/Layouts/LineLayout.swift:96-102`):

```swift
if let focused = focusedNode {
    let color = focused.style["outline-color"] ?? "black"
    let widthStr = (focused.style["outline-width"] ?? "2px").replacingOccurrences(
        of: "px", with: "")
    let thickness = CGFloat(Double(widthStr) ?? 2.0)
    cmds.append(DrawOutline(rect: selfRect(), color: color, thickness: thickness))
}
```

**New**:

```swift
if focusedNode != nil {
    let rect = selfRect()
    // Two rings: a thicker white one underneath, a thinner black one
    // on top. The white halo shows on dark content, the black core on
    // light content, so the ring has contrast on any background.
    cmds.append(DrawOutline(rect: rect, color: "white", thickness: 4))
    cmds.append(DrawOutline(rect: rect, color: "black", thickness: 2))
}
```

Notes:
- `focused.style` is no longer read, so the `if let focused` binding
  becomes a plain `!= nil` check (or keep the binding if you prefer —
  Swift will warn about the unused variable).
- 4 px / 2 px: the white stroke extends 1 px beyond the black stroke on
  each side, giving a 1 px halo inside and outside.

### Step 2 — Browser.swift (same trick for the accessibility hover ring)

Optional but consistent: the hover outline at
`Sources/Engine/Browser.swift:332-335` has the same single-color
problem, solved today with a `darkMode` check.

**Old**:

```swift
if let bounds = inputs.hoveredBounds {
    let color = inputs.darkMode ? "white" : "black"
    drawList.append(DrawOutline(rect: bounds, color: color, thickness: 2))
}
```

**New**:

```swift
if let bounds = inputs.hoveredBounds {
    drawList.append(DrawOutline(rect: bounds, color: "white", thickness: 4))
    drawList.append(DrawOutline(rect: bounds, color: "black", thickness: 2))
}
```

(`inputs.darkMode` is still used elsewhere — leave `RasterInputs`
alone.)

### Step 3 — browser.css cleanup (after Steps 0-2 verified)

The engine now ignores outline *color*, so the dark-mode overrides
`a:focus`, `input:focus`, `div:focus`, `button:focus`
(`browser.css:178-200`) are dead weight. Delete those four rules.
The light-mode `input:focus` / `button:focus` rules (lines 146-157)
are also unused after Step 1 (width hardcoded too), so you may delete
them as well, or keep them as documentation of "these elements get a
focus ring". Your call; deleting is cleaner.

Per the workflow rule, do this deletion only as the final step, after
the new painting is verified.

### Step 4 — Verify

1. `swift build`
2. Open `www/ch14/exercise-14-1.html`, press Tab repeatedly.
3. Focus must move through link → input → button in each section
   (links included — that's Bug 0b fixed), then jump to the address
   bar after the last one.
4. The ring on the dark section must stay visible (white halo), the
   ring on the light section must stay visible (black core).
5. Toggle OS dark mode: ring looks the same in both.

## Files touched

| File | Why |
|---|---|
| `Sources/Engine/Tab.swift` | Step 0: repaint on focus change; walk DOM (not layout) for Tab order |
| `Sources/Engine/Layouts/LineLayout.swift` | Step 1: paint two rings instead of one (the exercise) |
| `Sources/Engine/Browser.swift` | Step 2: same fix for the a11y hover ring (optional) |
| `Sources/Engine/Resources/browser.css` | Step 3: remove now-dead outline color overrides (cleanup) |
| `www/ch14/exercise-14-1.html` | Proof page |

## Colors

Only `white` and `black` — both already exist in
`Sources/Engine/PaintCommand.swift:18-19`. No new colors.

---

# Follow-up: button focus ring only hugs the text

## Symptom

Tab to a button: the ring wraps just the label text inside the button,
not the 200px button box (see "Screen Recording 2026-07-08 at
08.37.36.mov").

## Cause (three facts combine)

1. **Parent paints before children.** `paintTree`
   (`Sources/Engine/DOMUtils.swift:230-235`) appends `obj.paint()`
   first, then recurses into children. So a line's ring is painted
   *before* the widgets sitting on that line.
2. **The outer ring gets buried.** The outer `LineLayout` sees the
   `ButtonLayout` child (`child.node` = the focused `<button>`) and
   paints a ring around the full button rect — but right after,
   `ButtonLayout.paint` (`Sources/Engine/Layouts/ButtonLayout.swift:117-125`)
   fills the same rect with solid white and its own 1px outline.
   Strokes are centered on the rect edge, so the fill erases the inner
   half of the ring; only a thin sliver outside the edge survives.
3. **An inner ring paints around the text only.** `ButtonLayout` builds
   its own inner `LineLayout`s for the label
   (`ButtonLayout.swift:67`). Their children are TextLayouts whose
   `node.parent` is the focused `<button>`, so the parent check in
   `LineLayout.paint` (`Sources/Engine/Layouts/LineLayout.swift:94`)
   — added for links in Bug 0c — fires *inside* the button and paints
   a fully visible ring around just the text union.

`InputLayout` has no inner lines, so inputs only suffer fact 2 (thin
but complete ring).

## Fix — Option A: widgets paint their own ring

The book does exactly this: atomic widgets (`input`, `button`) paint
their focus outline themselves, *after* their background; lines only
handle text children of focused inline elements (links).

- **Option A (chosen): ring logic in widget paint + guard in
  LineLayout.** Ring always on top of the widget's own background.
  Trade-off: the white/black pair now appears in three files.
- **Option B (rejected): paint the line's ring after its children**
  by restructuring `paintTree` order. Touches global paint order,
  risks z-order/visual-effect regressions — too heavy for this bug.

Each step below leaves the project building (`swift build`).

### Step 1 — ButtonLayout.swift: paint own ring

**Old** (`Sources/Engine/Layouts/ButtonLayout.swift:117-125`):

```swift
func paint() -> [Any] {
    guard let element = node as? Element else { return [] }
    var cmds: [any PaintCommand] = []
    let bgcolor = element.style["background-color"] ?? "transparent"
    let displayColor = bgcolor == "transparent" ? "white" : bgcolor
    cmds.append(DrawRect(rect: selfRect(), color: displayColor))
    cmds.append(DrawOutline(rect: selfRect(), color: "black", thickness: 1))
    return cmds
}
```

**New** (ring appended last, so it sits on top of the fill):

```swift
func paint() -> [Any] {
    guard let element = node as? Element else { return [] }
    var cmds: [any PaintCommand] = []
    let bgcolor = element.style["background-color"] ?? "transparent"
    let displayColor = bgcolor == "transparent" ? "white" : bgcolor
    cmds.append(DrawRect(rect: selfRect(), color: displayColor))
    cmds.append(DrawOutline(rect: selfRect(), color: "black", thickness: 1))
    if element.isFocused {
        cmds.append(DrawOutline(rect: selfRect(), color: "white", thickness: 4))
        cmds.append(DrawOutline(rect: selfRect(), color: "black", thickness: 2))
    }
    return cmds
}
```

### Step 2 — InputLayout.swift: same, two insertion points

The checkbox branch returns early, so it needs its own copy.

**Old** (`Sources/Engine/Layouts/InputLayout.swift:84-93`):

```swift
// For input checkbox
if element.attributes["type"] == "checkbox" {
    cmds.append(DrawRect(rect: selfRect(), color: "white"))
    cmds.append(DrawOutline(rect: selfRect(), color: "black", thickness: 1))
    if element.isChecked {
        cmds.append(
            DrawText(x1: x, y1: y, text: "X", font: font, color: "black"))
    }
    return cmds
}
```

**New**:

```swift
// For input checkbox
if element.attributes["type"] == "checkbox" {
    cmds.append(DrawRect(rect: selfRect(), color: "white"))
    cmds.append(DrawOutline(rect: selfRect(), color: "black", thickness: 1))
    if element.isChecked {
        cmds.append(
            DrawText(x1: x, y1: y, text: "X", font: font, color: "black"))
    }
    if element.isFocused {
        cmds.append(DrawOutline(rect: selfRect(), color: "white", thickness: 4))
        cmds.append(DrawOutline(rect: selfRect(), color: "black", thickness: 2))
    }
    return cmds
}
```

**Old** (`Sources/Engine/Layouts/InputLayout.swift:115-121`, the main
path — the `isFocused` block already exists for the typing cursor):

```swift
// 3. Cursor line when this element has focus (user is typing into it)
if element.isFocused {
    let cx = x + font.measure(text)
    cmds.append(
        DrawLine(
            x1: cx, y1: y, x2: cx, y2: y + height, color: "black", thickness: 1))
}
```

**New** (rings join the existing block):

```swift
// 3. Cursor line and focus ring when this element has focus
if element.isFocused {
    let cx = x + font.measure(text)
    cmds.append(
        DrawLine(
            x1: cx, y1: y, x2: cx, y2: y + height, color: "black", thickness: 1))
    cmds.append(DrawOutline(rect: selfRect(), color: "white", thickness: 4))
    cmds.append(DrawOutline(rect: selfRect(), color: "black", thickness: 2))
}
```

Note: the main path wraps `cmds` in `paintVisualEffects`
(`InputLayout.swift:123`), so the ring inherits the element's opacity
etc. — that's consistent with how the rest of the widget is drawn.

### Step 3 — LineLayout.swift: lines only ring *text* of focused inline elements

Two changes in one line:

- Drop `child.node.isFocused`: on an outer line that only ever matched
  `InputLayout`/`ButtonLayout` children (a TextLayout's node is a
  TextNode, never focused), and those widgets now paint their own ring.
- Guard the parent check with `child.node.parent !== node`: an inner
  button line's own `node` *is* the button, so text inside the button
  no longer triggers the ring; link text on a normal line still does
  (its parent is the `<a>`, not the line's node).

**Old** (`Sources/Engine/Layouts/LineLayout.swift:94`):

```swift
let isFocusedChild = child.node.isFocused || (child.node.parent?.isFocused ?? false)
```

**New**:

```swift
let isFocusedChild =
    (child.node.parent?.isFocused ?? false) && child.node.parent !== node
```

Apply Steps 1-2 first: until they're in, dropping
`child.node.isFocused` would remove the (buried) widget ring with
nothing replacing it.

### Step 4 — Verify

1. `swift build`
2. Open `www/ch14/exercise-14-1.html`, Tab through all sections.
3. Button: ring around the full 200px box, no inner ring around the
   label text.
4. Input: ring around the full box, now at full thickness (it is no
   longer half-buried under the white fill).
5. Links: unchanged — ring hugs the link text.
6. Dark section: white halo still visible on black background.

## Files touched (follow-up)

| File | Why |
|---|---|
| `Sources/Engine/Layouts/ButtonLayout.swift` | Step 1: button paints own ring on top of its fill |
| `Sources/Engine/Layouts/InputLayout.swift` | Step 2: input/checkbox paint own ring |
| `Sources/Engine/Layouts/LineLayout.swift` | Step 3: restrict line ring to text of focused inline elements outside the widget |

## Colors

Still only `white` and `black` — no new colors.
