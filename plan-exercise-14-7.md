# Plan: Exercise 14-7 — High-Contrast (Forced Colors) Mode

## Goal

Add a browser-level toggle (Ctrl+H) that throws away every color the page asked
for and repaints the whole document using a small fixed palette with guaranteed
contrast. Pages can detect the mode with `@media (forced-colors: active)`.

Same idea as Windows High Contrast: the user's palette wins over the author's, no
matter how the author set the color (stylesheet, `!important`, inline `style`, or
JavaScript).

## The palette (8 roles)

Every role maps to a color name the engine already knows
(Sources/Engine/PaintCommand.swift), so **no new colors are needed**.

| Role | Used for | Color |
|---|---|---|
| Canvas | every non-transparent background | `black` |
| CanvasText | every piece of text, bullets, scrollbars | `white` |
| LinkText | `<a>` text | `yellow` |
| VisitedText | visited `<a>` text | `orchid` |
| ButtonFace | `<input>` / `<button>` background | `black` |
| ButtonText | `<input>` / `<button>` text | `white` |
| ButtonBorder | borders and widget outlines | `white` |
| Highlight | focus rings, hover/read rings | `gold` |

Contrast against Canvas (black): white 21:1, yellow 19.6:1, gold 15.3:1,
orchid 6.7:1. All above the 4.5:1 threshold, so any pairing stays readable.

## Design decision 1 — where colors get replaced

**Option A (chosen): replace at style time**, as the last step of `applyStyle`
(Sources/Engine/DOMUtils.swift:118). The cascade runs normally, then the forced
palette overwrites the color properties of the computed style.

- Wins over stylesheets, `!important` and inline `style` for free, because it
  runs after all of them (Sources/Engine/DOMUtils.swift:153-160).
- Keeps the *meaning* of each color: text becomes CanvasText, a background
  becomes Canvas. Foreground and background can never collapse into one color.
- Paint commands keep storing color *strings*, so nothing about raster or
  compositing changes.

**Option B (rejected): replace at paint time**, inside `Color(cssName:)` — map
each color to the nearest palette entry. Fewer touch points, but blind to role: a
page with `color: #333; background: #222` maps both to `black` and the text
vanishes. It would also need a mutable flag readable from the raster thread.

## Design decision 2 — how paint code learns the mode is on

Some colors are hardcoded in paint code, not in CSS: focus rings, `<li>` bullets,
the Table-of-Contents bar, scrollbars, checkbox boxes. Those need the flag too.

**Option A2 (chosen): a marker property in the computed style.** When forcing,
`applyStyle` also writes `node.style["-forced-colors"] = "active"`. Paint code
already has `node`, so it can ask `isForcedColors(node)` with no new function
parameters and no shared mutable state (style is read on the main thread during
paint, exactly like `node.style["color"]` is today).

**Option B2 (rejected): thread a `forcedColors: Bool` argument through every
`paint()`.** Changes the signature of every layout class and every call site for
information already reachable through `node`.

The two places with no DOM node — the browser chrome
(Sources/Engine/Chrome.swift:88) and the accessibility rings drawn by the browser
(Sources/Engine/Browser.swift:338-347) — get the flag the way `prefersDark` does
today: through the `TabManager` protocol and `RasterInputs`.

## Files that change and why

| File | Why |
|---|---|
| `Sources/Engine/ForcedColors.swift` (new) | The palette, the marker, the style-rewriting function. |
| `Sources/Engine/CSSParser.swift` | Parse `@media (forced-colors: active)`. |
| `Sources/Engine/DOMUtils.swift` | Match that media query; run the forcing step at the end of `applyStyle`. |
| `Sources/Engine/Tab.swift` | Own the `forcedColors` flag; pass it to `applyStyle`; fix default text color, visited links, page scrollbar; put it in `CommitData`. |
| `Sources/Engine/CommitData.swift` | Carry the flag from tab to browser. |
| `Sources/Engine/RasterInputs.swift` | Carry the flag to the raster thread. |
| `Sources/Engine/Browser.swift` | Toggle, plumbing, hover/read rings. |
| `Sources/Engine/Chrome.swift` | Paint the chrome with the palette. |
| `Sources/Engine/Layouts/BlockLayout.swift` | Focus ring, bullet, ToC bar, element scrollbar. |
| `Sources/Engine/Layouts/InputLayout.swift` | Checkbox, text cursor, focus ring. |
| `Sources/Engine/Layouts/ButtonLayout.swift` | Button face, border, focus ring. |
| `Sources/Engine/Layouts/LineLayout.swift` | Focus ring for mixed inlines. |
| `Sources/ToyStack/ToyStack.swift` | Ctrl+H key handler, window background color. |
| `www/ch14/exercise-14-7.html` | Proof page (already written). |

---

## Step 1 — New file: `Sources/Engine/ForcedColors.swift`

Nothing references it yet, so the project still builds after this step.

```swift
import CoreGraphics

// MARK: - Forced Colors Palette
// The user's palette for high-contrast mode. Every name here is already
// understood by Color(cssName:) in PaintCommand.swift.
enum ForcedColor {
    static let canvas = "black"        // all backgrounds
    static let canvasText = "white"    // all text
    static let linkText = "yellow"
    static let visitedText = "orchid"
    static let buttonFace = "black"
    static let buttonText = "white"
    static let buttonBorder = "white"  // borders and widget outlines
    static let highlight = "gold"      // focus, hover and read rings
}

// Marker written into the computed style while forcing, so paint code can ask
// "am I in forced-colors mode?" using the node it already has.
let forcedColorsMarker = "-forced-colors"

func isForcedColors(_ node: any DOMNode) -> Bool {
    node.style[forcedColorsMarker] == "active"
}

// Focus/hover ring colors: gold over black in forced mode, the existing
// white-over-black pair otherwise. Every ring site calls this.
func ringColors(_ node: any DOMNode) -> (outer: String, inner: String) {
    isForcedColors(node)
        ? (ForcedColor.highlight, ForcedColor.canvas)
        : ("white", "black")
}

// Rewrites the color-carrying properties of one node's computed style.
// Called as the last step of applyStyle, so it overrides stylesheets,
// !important and inline styles alike.
func forceColors(node: any DOMNode) {
    node.style[forcedColorsMarker] = "active"

    // Text nodes keep the color they inherited from an already-forced parent
    // (white from a <p>, yellow from an <a>). Overwriting it here would undo
    // the link color for exactly the text that shows it.
    guard let element = node as? Element else { return }

    element.style["color"] = ForcedColor.canvasText

    // Transparent stays transparent: forcing a background onto every element
    // would emit a DrawRect (and a composited layer) per element for no visible
    // difference, since every background would be the same color.
    if let bg = element.style["background-color"], bg != "transparent" {
        element.style["background-color"] = ForcedColor.canvas
    }

    if element.style["border-color"] != nil {
        element.style["border-color"] = ForcedColor.buttonBorder
    }

    switch element.tag {
    case "a":
        element.style["color"] = ForcedColor.linkText
    case "input", "button":
        element.style["color"] = ForcedColor.buttonText
        element.style["background-color"] = ForcedColor.buttonFace
    default:
        break
    }
}
```

## Step 2 — `CSSParser.swift`: parse the media query

In `mediaQuery()` (Sources/Engine/CSSParser.swift:503-527), add one case to the
`switch prop`, next to `max-width` (around line 519):

```swift
            case "forced-colors":
                guard val == "active" || val == "none" else {
                    throw CSSParseError.parseError
                }
                return "forced-colors:\(val)"
```

Rules inside an unparseable `@media` block are skipped today, so before this step
a page's `@media (forced-colors: active)` block is silently ignored — not a
crash. That is why this step is safe on its own.

## Step 3 — `DOMUtils.swift`: match the query and force the colors

Four edits in `applyStyle`.

**3a. New parameter** (Sources/Engine/DOMUtils.swift:118-121):

| Old | New |
|---|---|
| `prefersDark: Bool = false, frameWidth: CGFloat = .greatestFiniteMagnitude` | `prefersDark: Bool = false, forcedColors: Bool = false,`<br>`frameWidth: CGFloat = .greatestFiniteMagnitude` |

Defaulting to `false` keeps every existing caller compiling.

**3b. Match the media query** — in the `switch m`
(Sources/Engine/DOMUtils.swift:133-147), add two cases before `default`:

```swift
            case "forced-colors:active":
                matches = forcedColors
            case "forced-colors:none":
                matches = !forcedColors
```

**3c. Force, after inline styles** — insert right after the Step 3 block that
applies the `style` attribute (after Sources/Engine/DOMUtils.swift:160):

```swift
    // Step 3b: the user's palette overrides the author's. This runs after
    // stylesheets and inline styles, so no author declaration can escape it.
    if forcedColors { forceColors(node: node) }
```

**3d. Pass it down the recursion** (Sources/Engine/DOMUtils.swift:182):

| Old | New |
|---|---|
| `applyStyle(node: child, rules: rules, prefersDark: prefersDark, frameWidth: frameWidth)` | `applyStyle(node: child, rules: rules, prefersDark: prefersDark, forcedColors: forcedColors, frameWidth: frameWidth)` |

## Step 4 — `Tab.swift`: own the flag and use it

**4a. The property**, next to `prefersDark` (Sources/Engine/Tab.swift:48-52):

```swift
    var forcedColors: Bool = false {
        didSet {
            if oldValue != forcedColors { setNeedsRender() }
        }
    }
```

**4b. Default text color and the style call** (Sources/Engine/Tab.swift:360-361):

| Old | New |
|---|---|
| `inheritedProperties["color"] = prefersDark ? "white" : "black"` | `inheritedProperties["color"] = forcedColors ? ForcedColor.canvasText : (prefersDark ? "white" : "black")` |
| `applyStyle(node: nodes, rules: sortedRules, prefersDark: prefersDark, frameWidth: tabWidth / zoom)` | `applyStyle(node: nodes, rules: sortedRules, prefersDark: prefersDark, forcedColors: forcedColors, frameWidth: tabWidth / zoom)` |

**4c. Visited links** (Sources/Engine/Tab.swift:395) — this loop runs *after*
`applyStyle`, so it needs its own palette check:

| Old | New |
|---|---|
| `el.style["color"] = "purple"` | `el.style["color"] = forcedColors ? ForcedColor.visitedText : "purple"` |

**4d. Page scrollbar** (Sources/Engine/Tab.swift:590):

| Old | New |
|---|---|
| `return [DrawRect(rect: barRect, color: "blue")]` | `return [DrawRect(rect: barRect, color: forcedColors ? ForcedColor.canvasText : "blue")]` |

**4e. Commit the flag** (Sources/Engine/Tab.swift:513-516) — add
`forcedColors: forcedColors` to the `CommitData(...)` call.

## Step 5 — Carry the flag to the browser and the raster thread

**5a. `CommitData.swift`** — add `let forcedColors: Bool`, an `init` parameter and
the assignment, mirroring `prefersDark` (Sources/Engine/CommitData.swift:12, 17,
27).

**5b. `RasterInputs.swift`** — add `let forcedColors: Bool` after `prefersDark`
(Sources/Engine/RasterInputs.swift:10). It uses the memberwise init, so the one
construction site (Sources/Engine/Browser.swift:145-154) must pass it.

**5c. `Browser.swift`** — three properties next to the dark-mode ones
(Sources/Engine/Browser.swift:38-40):

```swift
    @Published public var forcedColors: Bool = false
    public private(set) var activeTabForcedColors: Bool = false
    @Published public private(set) var commitedForcedColors: Bool = false
```

Then:

- `newTab` (Sources/Engine/Browser.swift:59): add `tab.forcedColors = forcedColors`.
- `commit` (Sources/Engine/Browser.swift:114): add
  `activeTabForcedColors = data.forcedColors`.
- `scheduleRasterAndDraw` (Sources/Engine/Browser.swift:152): pass
  `forcedColors: activeTabForcedColors` into `RasterInputs`.
- Raster completion (Sources/Engine/Browser.swift:192): add
  `self.commitedForcedColors = inputs.forcedColors`.
- New toggle next to `togglePrefersDark` (Sources/Engine/Browser.swift:385-388):

```swift
    public func toggleForcedColors() {
        forcedColors = !forcedColors
        activeTab?.forcedColors = forcedColors
    }
```

**5d. Accessibility rings** in `computePaintDrawList`
(Sources/Engine/Browser.swift:338-347):

| Old | New |
|---|---|
| hover ring: `color: "white", thickness: 4` then `color: "black", thickness: 2` | `color: inputs.forcedColors ? ForcedColor.highlight : "white", thickness: 4` then `color: "black", thickness: 2` |
| read ring: `color: "gold", thickness: 4` then `color: "black", thickness: 2` | unchanged — `gold` over `black` is already the forced pair |

## Step 6 — `Chrome.swift`: paint the chrome with the palette

**6a. Protocol** (Sources/Engine/Chrome.swift:10) — add next to `prefersDark`:

```swift
    var forcedColors: Bool { get }
```

`Browser` satisfies it automatically after Step 5c.

**6b. `paint()`** (Sources/Engine/Chrome.swift:96-98):

| Old | New |
|---|---|
| `let darkMode = tabManager?.prefersDark ?? false`<br>`let color = darkMode ? "white" : "black"`<br>`let bgColor = darkMode ? "black" : "white"` | `let forced = tabManager?.forcedColors ?? false`<br>`let darkMode = tabManager?.prefersDark ?? false`<br>`let color = forced ? ForcedColor.canvasText : (darkMode ? "white" : "black")`<br>`let bgColor = forced ? ForcedColor.canvas : (darkMode ? "black" : "white")` |

Everything below in `paint()` already draws with `color` / `bgColor`, so the rest
of the chrome follows for free.

## Step 7 — Layout paint sites

All of these read the marker through `isForcedColors(node)` / `ringColors(node)`.

**7a. `BlockLayout.swift`**

| Where | Old | New |
|---|---|---|
| :413-414 focus ring | `color: "white", thickness: 4`<br>`color: "black", thickness: 2` | `let ring = ringColors(node)`<br>`color: ring.outer, thickness: 4`<br>`color: ring.inner, thickness: 2` |
| :424 `<li>` bullet | `color: "black"` | `color: isForcedColors(node) ? ForcedColor.canvasText : "black"` |
| :429 ToC bar | `color: "gray"` | `color: isForcedColors(node) ? ForcedColor.canvasText : "gray"` |
| :433 ToC label | `color: "white"` | `color: isForcedColors(node) ? ForcedColor.canvas : "white"` |
| :447 element scrollbar | `color: "gray"` | `color: isForcedColors(node) ? ForcedColor.canvasText : "gray"` |

The ToC bar inverts (white bar, black label) so the header still reads as a bar
against the black canvas.

**7b. `InputLayout.swift`**

| Where | Old | New |
|---|---|---|
| :86 checkbox box | `color: "white"` | `color: isForcedColors(node) ? ForcedColor.buttonFace : "white"` |
| :87 checkbox border | `color: "black", thickness: 1` | `color: isForcedColors(node) ? ForcedColor.buttonBorder : "black", thickness: 1` |
| :90 check mark "X" | `color: "black"` | `color: isForcedColors(node) ? ForcedColor.buttonText : "black"` |
| :93-94 checkbox focus ring | `"white"` 2 / `"black"` 4 | `ringColors(node).outer` 2 / `ringColors(node).inner` 4 |
| :124 text cursor | `color: "black"` | `color: isForcedColors(node) ? ForcedColor.buttonText : "black"` |
| :125-126 focus ring | `"white"` 4 / `"black"` 2 | `ring.outer` 4 / `ring.inner` 2 |

Line :116 (`element.style["color"] ?? "black"`) needs no change — Step 3c already
forced that style value to ButtonText.

**7c. `ButtonLayout.swift`**

| Where | Old | New |
|---|---|---|
| :121 transparent fallback | `bgcolor == "transparent" ? "white" : bgcolor` | `bgcolor == "transparent" ? (isForcedColors(node) ? ForcedColor.buttonFace : "white") : bgcolor` |
| :123 border | `color: "black", thickness: 1` | `color: isForcedColors(node) ? ForcedColor.buttonBorder : "black", thickness: 1` |
| :125-126 focus ring | `"white"` 4 / `"black"` 2 | `ring.outer` 4 / `ring.inner` 2 |

**7d. `LineLayout.swift`** (:102-103) — the mixed-inline focus ring from exercise
14-5:

| Old | New |
|---|---|
| `DrawOutline(rect: rect, color: "white", thickness: 4)`<br>`DrawOutline(rect: rect, color: "black", thickness: 2)` | `let ring = ringColors(node)`<br>`DrawOutline(rect: rect, color: ring.outer, thickness: 4)`<br>`DrawOutline(rect: rect, color: ring.inner, thickness: 2)` |

## Step 8 — `ToyStack.swift`: the key and the window background

**8a. Ctrl+H** — in the `event.modifierFlags.contains(.control)` switch
(Sources/ToyStack/ToyStack.swift:129-153), add:

```swift
                            case 4:  // Ctrl+H
                                app.toggleForcedColors()
```

macOS key code 4 is `h`. `Ctrl+D` (case 2) keeps toggling dark mode.

**8b. Window background** (Sources/ToyStack/ToyStack.swift:69) — the area below
the document is painted by SwiftUI, not by the display list, so it must follow
the palette too:

| Old | New |
|---|---|
| `.background(app.commitedPrefersDark ? Color.black : Color.white)` | `.background(app.commitedForcedColors ? Color(cssName: ForcedColor.canvas) : (app.commitedPrefersDark ? Color.black : Color.white))` |

## Step 9 — Verify

1. `swift build` — clean.
2. Open `www/ch14/exercise-14-7.html`. Normal mode: loud colors, deliberately
   low-contrast text, colored buttons and inputs, a status dot that means
   something only by color.
3. Press **Ctrl+H**. Everything turns black / white / yellow: page background,
   chrome, buttons, inputs, bullets, borders, scrollbar. The
   `@media (forced-colors: active)` blocks appear — that proves the media-query
   path; the palette everywhere else proves the forcing path.
4. Click a link, come back: the visited link is orchid, not purple.
5. Tab through the page: focus rings are gold. Press **Ctrl+A**, then hover
   elements: hover ring gold, read ring gold over black.
6. Press **Ctrl+H** again: the original colors return exactly, because the flag
   only affects computed style — never the DOM, never the stylesheet.
7. Press **Ctrl+D** while forced colors is on: nothing changes. The forced
   palette runs after the dark-mode rules, so it wins. That is correct.

## Notes and known limits

- **`background-color` transitions** (Sources/Engine/DOMUtils.swift:488): while
  forcing, the old and new values are both `black`, so an animation still runs
  but paints one color. No crash, no flicker.
- **`transparent` is preserved.** A page whose meaning comes from a background on
  a transparent parent still looks right; a page whose meaning comes from color
  *alone* (a red/green status dot) loses that meaning. That is inherent to forced
  colors, and it is why the mode is detectable: pages restore meaning with shape
  or text inside `@media (forced-colors: active)`. The proof page shows both
  sides.
- **Images** are unaffected; this engine does not paint images yet.
- **The flag is per-tab**, like `prefersDark`: `toggleForcedColors` sets the
  active tab and `Browser`, and new tabs inherit from `Browser`. A tab opened
  before the toggle keeps its old value — same behavior as dark mode today.

## Colors

No new colors. Every palette entry (`black`, `white`, `yellow`, `orchid`, `gold`)
already exists in `cssColorToRGB` and `Color(cssName:)` in
Sources/Engine/PaintCommand.swift.
