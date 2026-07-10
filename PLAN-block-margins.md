# Plan: vertical margins in BlockLayout (fix exercise 14-2 check 7 without more filler)

## Goal

Make "Focus the far-away input" actually scroll in ToyStack, the same
way it does in Firefox, by fixing the real difference between the two
engines: Firefox's user-agent stylesheet gives `<p>` and headings
default vertical margins, so 20 filler paragraphs push the far input
off-screen. ToyStack parses `margin-*` (`CSSParser.swift:278`,
`expandBox` at `CSSParser.swift:319`) but the layout never reads it,
so the whole page fits in one screen and the scroll-on-focus code in
`Tab.swift:486-489` returns early at the visibility check in
`scrollTo` (`Tab.swift:523`).

This continues `ANALYSIS-browser-css-defaults.md` — that document's
"Option B: implement vertical margins in the engine", now chosen
because we do not want to add filler.

## Scope decision

**Vertical margins only** (`margin-top`, `margin-bottom`), on block
boxes only. Horizontal margins and margin collapsing are out of scope.

Known simplification: real browsers collapse adjacent vertical margins
(16px + 16px between two paragraphs = 16px gap). This plan adds them
(gap = 32px). That is fine for a toy engine and actually helps the
goal (taller page). If the doubled gap ever bothers you, halve the
values in browser.css — do not implement collapsing for this.

## Files that change and why

| File | Why |
|---|---|
| `Sources/Engine/Layouts/BlockLayout.swift` | The only place blocks stack vertically (`y` at line 73) and the only place a parent sums child heights (line 143). Both must learn about margins. |
| `Sources/Engine/Resources/browser.css` | Add the default margins (px values — the engine's length parser is px-only, see `BlockLayout.swift:212`). |

No other file changes. `Tab.swift` scroll-on-focus already works — it
just never had anything to scroll to.

## Steps (each leaves the project building)

### Step 1 — margin helper in BlockLayout.swift

Add a private helper near the top of `BlockLayout` (e.g. below
`layoutMode()`), mirroring how `width`/`height` parse px at
`BlockLayout.swift:56` and `BlockLayout.swift:146`:

```swift
// Reads a vertical margin like "16px" from computed style; 0 if absent.
private func marginPx(_ n: any DOMNode, _ prop: String) -> CGFloat {
    guard let s = n.style[prop], s.hasSuffix("px"),
        let v = Double(s.dropLast(2)) else { return 0 }
    return dpx(CGFloat(v), zoom: zoom)
}
```

`dpx` is the same zoom scaler the rest of layout uses
(`DOMUtils.swift:556`, used in `DocumentLayout.swift:32`), so margins
zoom together with fonts.

Builds and changes nothing yet.

### Step 2 — offset y by margins when stacking (BlockLayout.swift:71-74)

| Old (`BlockLayout.swift:71-74`) | New |
|---|---|
| `} else {`<br>`    // Stack below the previous sibling, or start at the parent's y.`<br>`    y = previous.map { $0.y + $0.height } ?? parent!.y`<br>`}` | `} else {`<br>`    // Stack below the previous sibling (plus its bottom margin and`<br>`    // our top margin), or start at the parent's y plus our top margin.`<br>`    let ownTop = marginPx(node, "margin-top")`<br>`    if let prev = previous, prev is BlockLayout {`<br>`        y = prev.y + prev.height + marginPx(prev.node, "margin-bottom") + ownTop`<br>`    } else {`<br>`        y = (previous.map { $0.y + $0.height } ?? parent!.y) + ownTop`<br>`    }`<br>`}` |

Why the `prev is BlockLayout` guard: an anonymous box
(`extraNodes` path, `BlockLayout.swift:39`) reuses `nodes[0]` as its
`node` — usually an inline node with no margins, so it is naturally 0,
but the guard documents the intent: only block boxes carry margins.

Builds; still renders identically (all margins are 0 — browser.css has
none yet).

### Step 3 — include margins in the parent's height sum (BlockLayout.swift:143-145)

| Old (`BlockLayout.swift:143-145`) | New |
|---|---|
| `let sumHeight = children.reduce(0) {`<br>`    $0 + ($1.node.style["position"] == "absolute" ? 0 : $1.height)`<br>`}` | `let sumHeight = children.reduce(0) {`<br>`    if $1.node.style["position"] == "absolute" { return $0 }`<br>`    var h = $1.height`<br>`    if $1 is BlockLayout {`<br>`        h += marginPx($1.node, "margin-top") + marginPx($1.node, "margin-bottom")`<br>`    }`<br>`    return $0 + h`<br>`}` |

The `is BlockLayout` check here is load-bearing, not cosmetic: in
inline mode the children are `LineLayout`s whose `node` is this block's
own node (`newLine()`, `BlockLayout.swift:261`). Without the check, a
`<p>` with margins and 3 lines of text would count its own margins 3
extra times.

Note `selfRect()` (`BlockLayout.swift:364`) stays as-is: height
excludes the element's own margins, so background colors
(`.log`, `.box` in the exercise) do not paint over the margin gap —
same as real browsers.

Builds; still renders identically.

### Step 4 — sanity-check before touching CSS

Run the browser, load a couple of older pages (e.g. ch13 exercises)
and `exercise-14-2`. Everything must look exactly as before — margins
exist in the engine but no stylesheet sets any.

### Step 5 — add default margins to browser.css

Append after the existing font-size block (browser.css line ~112+).
Values are the Chrome UA-stylesheet defaults from
`ANALYSIS-browser-css-defaults.md`, rounded to whole px, vertical
components only (the engine ignores horizontal margins):

```css
p { margin-top: 16px; margin-bottom: 16px; }
h1 { margin-top: 21px; margin-bottom: 21px; }
h2 { margin-top: 20px; margin-bottom: 20px; }
h3 { margin-top: 19px; margin-bottom: 19px; }
h4 { margin-top: 21px; margin-bottom: 21px; }
h5 { margin-top: 22px; margin-bottom: 22px; }
h6 { margin-top: 25px; margin-bottom: 25px; }
ul { margin-top: 16px; margin-bottom: 16px; }
ol { margin-top: 16px; margin-bottom: 16px; }
pre { margin-top: 16px; margin-bottom: 16px; }
blockquote { margin-top: 16px; margin-bottom: 16px; }
```

Longhand on purpose: it does not depend on the `expandBox` shorthand
path, so each rule is exactly one property the engine reads.

### Step 6 — re-test exercise 14-2, check 7

1. Load `exercise-14-2`. The page is now roughly 640px taller from the
   fillers alone (20 x 32px), plus margins on the other paragraphs and
   the h1 — the far-away input starts off-screen.
2. Click "Focus the far-away input": the page must scroll down to it
   (`Tab.swift:486` -> `scrollTo` at `Tab.swift:518`) and the log must
   show "far input: focus".
3. Regression pass: Tab key focus cycling still scrolls to the focused
   element; clicking `.box`/`.log` shows backgrounds that do NOT bleed
   into the gaps between paragraphs.

## Colors

No new colors introduced.
