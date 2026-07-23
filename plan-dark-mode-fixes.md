# Plan: Dark Mode Fixes

Two bugs, found by stepping through `Screen Recording 2026-07-23 at 20.27.35.mov` frame by frame (60fps) and tracing the code.

- **Bug 1 — flash when toggling dark/light.** For ~5 frames (~80ms) the screen shows the *new* background with the *old* page content. Going dark: black background + old black text = page goes blank except blue links.
- **Bug 2 — page layout differs between light and dark.** In dark mode the book-cover / "Buy Web Browser Engineering" section (`<div class="wide-ad">`) collapses into one merged run of text; in light mode each part sits on its own line.

No new colors are introduced by this plan.

---

## Bug 1: The toggle flash

### Why it happens

Two things change at different times:

1. **Instant:** `togglePrefersDark()` (`Sources/Engine/Browser.swift:380`) flips `prefersDark`, which is `@Published`. SwiftUI reacts in the same frame: `.background(app.prefersDark ? Color.black : Color.white)` (`Sources/ToyStack/ToyStack.swift:69`) swaps the page background immediately.
2. **~80ms later:** `Tab.prefersDark`'s `didSet` (`Sources/Engine/Tab.swift:48`) only calls `setNeedsRender()`. The new text colors need the full pipeline — style, layout, paint, commit, composite, raster — before the new `drawList` lands (`Sources/Engine/Browser.swift:187`).

Between 1 and 2 the background and the content disagree. Real browsers never show this because a whole frame updates at once.

### Option A (chosen): background color rides the commit

Make the background color travel *with* the rendered content, so both flip in the same frame.

**Why not the simpler version** (capture `Browser.prefersDark` when the raster job is submitted): if the user scrolls during the 80ms window, a scroll-triggered draw would submit with the *new* flag but the *old* display list — background flips early again, same flash. The mode must be attached to the display list it was rendered with, which means it rides `CommitData`.

### Files that change and why

| File | Why |
|---|---|
| `Sources/Engine/CommitData.swift` | Carry the mode the display list was built with. |
| `Sources/Engine/Tab.swift` | Fill in that new field when committing. |
| `Sources/Engine/Browser.swift` | Store the committed mode, pass it to the raster job, publish it when the drawn frame is ready. |
| `Sources/ToyStack/ToyStack.swift` | Read the committed mode for `.background` instead of the live flag. |

`RasterInputs.prefersDark` (`Sources/Engine/RasterInputs.swift:10`) already exists and is currently consumed nowhere in the raster code — it is the perfect carrier, no schema change needed there.

### Steps (each leaves the project building)

**Step 1 — `CommitData` carries the mode** (`Sources/Engine/CommitData.swift` + `Sources/Engine/Tab.swift:512`, one step because the added init parameter must be filled at the call site to compile):

Old (`CommitData.swift:3-16`, abbreviated):
```swift
class CommitData {
    let url: WebURL
    ...
    let interestTop: CGFloat

    init(url: WebURL, scroll: CGFloat, height: CGFloat, displayList: [Any],
         compositedUpdates: [ObjectIdentifier: VisualEffect]?, accessibilityTree: AccessibilityNode?,
         focus: DOMNode?, interestTop: CGFloat) {
```
New:
```swift
class CommitData {
    let url: WebURL
    ...
    let interestTop: CGFloat
    let prefersDark: Bool   // mode this displayList was rendered with

    init(url: WebURL, scroll: CGFloat, height: CGFloat, displayList: [Any],
         compositedUpdates: [ObjectIdentifier: VisualEffect]?, accessibilityTree: AccessibilityNode?,
         focus: DOMNode?, interestTop: CGFloat, prefersDark: Bool) {
```
(and `self.prefersDark = prefersDark` in the init body)

Old (`Tab.swift:512-516`):
```swift
let data = CommitData(
    url: url!, scroll: scroll, height: docHeight, displayList: displayList,
    compositedUpdates: updates, accessibilityTree: accessibilityTree, focus: focus,
    interestTop: interestTop
)
```
New:
```swift
let data = CommitData(
    url: url!, scroll: scroll, height: docHeight, displayList: displayList,
    compositedUpdates: updates, accessibilityTree: accessibilityTree, focus: focus,
    interestTop: interestTop, prefersDark: prefersDark
)
```

**Step 2 — `Browser` stores and publishes the committed mode** (`Sources/Engine/Browser.swift`):

2a. Near the existing published flag (`Browser.swift:37`), add two properties:
```swift
@Published public var prefersDark: Bool = false                      // existing, unchanged
public private(set) var activeTabPrefersDark: Bool = false           // new: latest committed mode
@Published public private(set) var committedPrefersDark: Bool = false // new: mode of the frame on screen
```

2b. In `commit(tab:data:)` (`Browser.swift:106`), record the committed mode next to the other committed data (after line 111):
```swift
activeTabPrefersDark = data.prefersDark
```

2c. In `scheduleRasterAndDraw()` (`Browser.swift:148`), feed the raster job the committed mode, not the live flag:

Old:
```swift
prefersDark: prefersDark, needsComposite: wantsComposite, ...
```
New:
```swift
prefersDark: activeTabPrefersDark, needsComposite: wantsComposite, ...
```

2d. In the raster completion closure (`Browser.swift:187`, right where `drawList` is stored), publish it:

Old:
```swift
if let drawList = output.drawList { self.drawList = drawList }
self.objectWillChange.send()
```
New:
```swift
if let drawList = output.drawList { self.drawList = drawList }
self.committedPrefersDark = inputs.prefersDark
self.objectWillChange.send()
```

The project still builds and behaves exactly as before — the new properties aren't read by the view yet.

**Step 3 — the view reads the committed mode** (`Sources/ToyStack/ToyStack.swift:69`):

Old:
```swift
.background(app.prefersDark ? Color.black : Color.white)
```
New:
```swift
.background(app.committedPrefersDark ? Color.black : Color.white)
```

Now the background flips in the same `objectWillChange` cycle that delivers the newly drawn content. No frame can show new background with old text.

**Known small trade-off:** the browser chrome (tab bar, address bar) still reads the live flag (`Sources/Engine/Chrome.swift:96`) and flips instantly, ~80ms before the page. That matches what real browsers do (their UI flips before pages re-render), so leave it.

### How to verify

Run the app, load https://browser.engineering/, toggle dark mode a few times. The page should switch in one clean step — no frame where the text vanishes. To be thorough, screen-record the toggle and step through frames like the analysis did.

---

## Bug 2: Layout differs between light and dark

### The evidence chain

Three causes stack on top of each other:

**Cause 1 — a typo in the website's own CSS (upstream, not fixable here).**
`https://browser.engineering/book.css` line 192 has a stray closing parenthesis:
```css
@media (prefers-color-scheme: light) ) {
.note { color: black; }
}
```

**Cause 2 — the CSS parser gets poisoned by that typo** (`Sources/Engine/CSSParser.swift:545-623`).
In `parse()`, the media line is handled like this (`CSSParser.swift:560-565`):
```swift
if keyword == "media" {
    i = saveI
    media = try mediaQuery()   // succeeds, media = "light"
    skipWhitespace()
    try literal("{")           // sees the stray ")" -> throws
    skipWhitespace()
}
```
`mediaQuery()` succeeds and sets `media = "light"` *before* `literal("{")` throws on the stray `)`. The `catch` block (`CSSParser.swift:608-620`) skips the block but **never resets `media`**. And since every later `@media` line fails the `media == nil` check on line 554, nothing downstream can ever reset it either — no stray `}` ever reaches the loop. Result: **every rule from line 192 to the end of book.css is silently tagged `media="light"`.**

Verified with a standalone harness that runs the engine's actual `CSSParser` over the real book.css:

```
rule counts by media tag: ["light": 80, "nil": 36, "dark": 2]
```

80 rules tagged "light" — the file only has 10 genuine light blocks, all small and color-only. The mis-tagged rules include every layout rule for the merged section:

```
media=light  .wide-ad              display=flex
media=light  .wide-ad figure      display=flex
media=light  .wide-ad figure figcaption  display=none
media=light  .wide-ad .description display=flex
```

**Cause 3 — the light/dark filter is inverted** (`Sources/Engine/DOMUtils.swift:130-134`):
```swift
for (media, selector, body) in rules {
    if let m = media {
        if m == "dark" && !prefersDark { continue }   // correct
        if m == "light" && !prefersDark { continue }  // INVERTED
    }
```
Line 133 skips light rules when the mode is *light* — and applies them when the mode is *dark*. Exactly backwards.

**Putting it together:**
- Light mode: all the mis-tagged "light" rules are (wrongly) skipped → `figure`/`section` keep `display: block` from the engine's own `browser.css` → block layout → tidy separate lines.
- Dark mode: all the mis-tagged "light" rules (wrongly) apply → `.wide-ad` children get `display: flex` → the engine only checks for `display == "block"` when picking layout mode (`Sources/Engine/Layouts/BlockLayout.swift:177-182`), and "flex" isn't "block" → the whole `div.wide-ad` falls back to inline layout → merged text.

That is the entire layout difference. It is not a dark-mode layout feature; it is two bugs canceling into a visible mode difference.

### Fixes

**Fix A — un-invert the filter** (`Sources/Engine/DOMUtils.swift:133`). One-word change:

Old:
```swift
if m == "light" && !prefersDark { continue }
```
New:
```swift
if m == "light" && prefersDark { continue }
```
(Dark line 132 is already correct: skip dark rules when not dark. Light rules must be skipped when dark.)

**Fix B — stop the parser poisoning** (`Sources/Engine/CSSParser.swift:560-565`). If anything fails after `media` was assigned but before the block opens, reset it before letting the normal recovery run:

Old:
```swift
if keyword == "media" {
    i = saveI
    media = try mediaQuery()
    skipWhitespace()
    try literal("{")
    skipWhitespace()
}
```
New:
```swift
if keyword == "media" {
    i = saveI
    media = try mediaQuery()
    skipWhitespace()
    do {
        try literal("{")
    } catch {
        media = nil   // header was malformed; don't tag later rules with it
        throw error
    }
    skipWhitespace()
}
```
The outer `catch` still skips the malformed block; it just no longer leaves `media` stuck. Don't reset `media` in the *outer* catch — that one also fires for broken rules *inside* a valid media block, where the tag must survive.

### Order and expected result

1. Fix A first (one word). Build, run. Layout flips: the merged `.wide-ad` now appears in **light** mode instead of dark — proof the filter was the mode-dependence.
2. Fix B. Build, run. The mis-tagged rules become untagged (`media=nil`), so they apply in **both** modes.

**Expected final behavior — read before judging it broken:** after both fixes, `.wide-ad` shows the merged inline layout in *both* modes. That is correct for this engine: the section really is `display: flex` on the website, the engine doesn't implement flex, and its fallback is inline flow. Today's tidy light-mode layout was an accident of the two bugs. Consistency between modes is the goal; flex support would be a separate project.

Also improved by Fix A: the genuine light-only rules near the top of book.css (body text `#333`, black headings, custom link colors) finally apply in light mode, and stop leaking into dark mode.

### How to verify

- Re-run the parser harness over book.css after Fix B — "light" count should drop from 80 to ~10, "dark" from 2 to a handful, everything else `nil`. (Harness lives in the session scratchpad: `csstest/`, a 30-line `main.swift` linking the engine's `CSSParser.swift` + `DOMNode.swift` unmodified.)
- In the app: toggle dark mode on browser.engineering — layout must no longer change shape between modes, only colors.
