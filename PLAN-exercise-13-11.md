# Plan: Exercise 13-11 — Animated Scrolling (`scroll-behavior`)

Goal: pressing down/up arrow animates the scroll smoothly instead of jumping
100px, when the page opts in with `scroll-behavior: smooth` on `<body>`.

## How it works today

- Down arrow → `ToyStack.swift:93` → `Tab.scrollDown()` (`Tab.swift:581`).
- `scrollDown()` jumps `scroll` by `SCROLL_STEP` (100px) immediately, then
  calls `Browser.applyScroll()` (`Browser.swift:361`) — a fast path that only
  re-draws already-rastered layers with the new offset. No tab frame runs.
  That fast path is this port's version of "threaded scrolling".
- `Tab.runAnimationFrame()` (`Tab.swift:427`) runs each frame, advances all
  `node.animations`, then commits `scroll` to the browser (`Tab.swift:497`).

## What we build

1. `scroll-behavior` read from `<body>`'s style (already parsed — nothing to
   add in the CSS code).
2. A `ScrollAnimation` class: animates the scroll offset from A to B over a
   fixed number of frames, reusing the existing `EasingFunction`
   (`NumericAnimation.swift:1`).
3. `scrollDown()`/`scrollUp()` start (or retarget) that animation instead of
   jumping, when behavior is smooth.
4. `runAnimationFrame()` advances the animation one step per frame and the
   existing commit carries the new offset to the screen.

Trade-off the exercise warns about: smooth scrolling routes every frame
through the full tab animation frame + commit, instead of the cheap
`applyScroll` draw-only path. That's "losing threaded scrolling". The commit
still sends `compositedUpdates` as an empty dict (not nil), so the browser
side stays on the draw-only path — no re-raster per frame. Cost is the tab
frame itself (rAF handlers + animation walk), which is acceptable here.

## Design decision: where does the animation tick?

- **Option A (recommended): main-thread, in `Tab.runAnimationFrame`.**
  Matches the exercise text. `Tab.scroll` stays the single source of truth,
  so hit-testing (`click`, `scrollAt`) and the scrollbar are always correct.
  The frame loop already re-arms itself after every commit
  (`Browser.swift:119`), so the animation keeps ticking with no new timer.
- **Option B: browser-thread, in `Browser.animationTick`, via `applyScroll`
  each frame** (the Exercise 13-3 build-on). Keeps scroll frames off the tab,
  but `Tab.scroll` goes stale during the animation — clicks and wheel events
  would hit-test against the wrong offset unless we sync it back every frame,
  which reintroduces the main-thread hop we tried to avoid.

Option A. Simpler, correct hit-testing, and in this port the per-frame cost
difference is one tree walk.

## Files that change

| File | Why |
|------|-----|
| `Sources/Engine/ScrollAnimation.swift` (new) | The animation class |
| `Sources/Engine/Tab.swift` | Start/advance/cancel the animation |
| `www/ch13/exercise-13-11.html` + `.css` (new) | Proof page |

No changes to `Browser.swift`, `ToyStack.swift`, or `CSSParser.swift`.

## Step 1 — new file `Sources/Engine/ScrollAnimation.swift`

```swift
import CoreGraphics

// Animates the page scroll offset from one value to another over a fixed
// number of frames. Unlike NumericAnimation (which produces CSS strings for
// node.style), this produces CGFloat scroll offsets directly.
class ScrollAnimation {
    // Where the animation ends. scrollDown()/scrollUp() read this so a
    // second key press during the animation extends the target instead of
    // restarting from the same place.
    let target: CGFloat

    private let start: CGFloat
    private let numFrames: Int
    private let easing: EasingFunction
    private var frameCount: Int = 0

    init(
        from start: CGFloat, to target: CGFloat, numFrames: Int = 12,
        easing: EasingFunction = .easeOut
    ) {
        self.start = start
        self.target = target
        self.numFrames = numFrames
        self.easing = easing
    }

    // Next scroll offset, or nil when the animation is finished.
    // The last non-nil value is exactly `target` (easing(1.0) == 1.0).
    func animate() -> CGFloat? {
        frameCount += 1
        if frameCount > numFrames { return nil }
        let t = Double(frameCount) / Double(numFrames)
        let eased = easing.apply(t)
        return start + (target - start) * CGFloat(eased)
    }
}
```

Project still builds after this step (nothing references it yet).

## Step 2 — `Tab.swift`: state + helper

Near the other scroll state (`Tab.swift:54`, next to `scrollFocusNode`):

```swift
private var scrollAnimation: ScrollAnimation? = nil
```

Anywhere in the class (suggestion: above `scrollDown()`):

```swift
// Exercise 13-11: <body style="scroll-behavior: smooth"> opts into
// animated scrolling. Style is re-read each key press so a page that
// changes the attribute at runtime behaves correctly.
private var scrollBehaviorIsSmooth: Bool {
    let body = treeToList(nodes)
        .compactMap({ $0 as? Element })
        .first(where: { $0.tag == "body" })
    return body?.style["scroll-behavior"] == "smooth"
}
```

Builds after this step (unused private members are fine).

## Step 3 — `Tab.swift`: start the animation in `scrollDown`/`scrollUp`

Old (`Tab.swift:581-594`):

```swift
public func scrollDown() {
    let maxY = max((document?.height ?? 0) + 2 * VSTEP - tabHeight, 0)
    scroll = min(scroll + SCROLL_STEP, maxY)
    if !checkInterestRegion() {
        browser?.applyScroll(scroll)
    }
}

public func scrollUp() {
    scroll = max(scroll - SCROLL_STEP, 0)
    if !checkInterestRegion() {
        browser?.applyScroll(scroll)
    }
}
```

New:

```swift
public func scrollDown() {
    let maxY = max((document?.height ?? 0) + 2 * VSTEP - tabHeight, 0)
    // Retarget from the in-flight animation's endpoint so mashing the key
    // accumulates distance instead of restarting the same 100px glide.
    let target = min((scrollAnimation?.target ?? scroll) + SCROLL_STEP, maxY)
    if scrollBehaviorIsSmooth {
        scrollAnimation = ScrollAnimation(from: scroll, to: target)
        browser?.setNeedsAnimationFrame(self)
    } else {
        scroll = target
        if !checkInterestRegion() {
            browser?.applyScroll(scroll)
        }
    }
}

public func scrollUp() {
    let target = max((scrollAnimation?.target ?? scroll) - SCROLL_STEP, 0)
    if scrollBehaviorIsSmooth {
        scrollAnimation = ScrollAnimation(from: scroll, to: target)
        browser?.setNeedsAnimationFrame(self)
    } else {
        scroll = target
        if !checkInterestRegion() {
            browser?.applyScroll(scroll)
        }
    }
}
```

Notes:
- `browser?.setNeedsAnimationFrame(self)` kicks the first frame; after that,
  every commit re-arms the loop (`Browser.swift:119`), so the animation runs
  to completion without extra scheduling.
- Mouse wheel also lands here via `scrollAt` (`Tab.swift:617`), so wheel
  scrolling animates too on smooth pages. Real browsers keep wheel instant
  (`scroll-behavior` only affects keyboard/programmatic scrolls); doing that
  here would need an `animated:` parameter threaded through `scrollAt` and
  `ToyStack.swift` — left out to keep the change small.

Builds and runs after this step, but nothing consumes the animation yet, so
smooth pages appear to ignore the key. Step 4 wires it up.

## Step 4 — `Tab.swift`: advance the animation in `runAnimationFrame`

Insert after the `needsFocusScroll` block (`Tab.swift:484-488`) and before
`let docHeight` (`Tab.swift:490`):

```swift
if let anim = scrollAnimation {
    if let value = anim.animate() {
        let maxY = max((document?.height ?? 0) + 2 * VSTEP - tabHeight, 0)
        scroll = max(0, min(value, maxY))
        checkInterestRegion()
    } else {
        scrollAnimation = nil
    }
}
```

Why this exact spot:
- After `render()`, so the offset applies to this frame's layout.
- Before the commit (`Tab.swift:496`), which already carries `scroll` to the
  browser — no new plumbing.
- `checkInterestRegion()` only *marks* layout dirty; the re-raster happens
  next frame, exactly like the instant-scroll path does today. Doing the
  re-render in the same frame would fight the `needsComposite` snapshot taken
  at `Tab.swift:430`.
- Re-clamping against `maxY` here guards against the document height changing
  mid-animation (e.g. a JS mutation relayouts the page).

## Step 5 — `Tab.swift`: cancel points

An in-flight animation must not overwrite scroll positions set by other code
one frame later. Three spots:

1. **Page load** — `parseHTML`, next to `scroll = 0` (`Tab.swift:138`):
   `scrollAnimation = nil`
2. **Fragment jump** — `scrollToFragment` (`Tab.swift:515`), inside the
   `if let target` branch: `scrollAnimation = nil`
3. **Focus scroll** — `scrollTo` (`Tab.swift:506`), before the early return:
   `scrollAnimation = nil` as the first line of the function.

(`goBack`/`goForward` and zoom go through these or through `setNeedsRender`,
and the per-frame clamp from Step 4 keeps any survivor sane.)

## Step 6 — proof page

`www/ch13/exercise-13-11.html` + `.css` (already created). Serve `www/` on
localhost:3000 and open `http://localhost:3000/ch13/exercise-13-11.html`.

Verify:
- Down/up arrow glides ~100px over ~12 frames instead of jumping.
- Mashing down arrow accumulates distance smoothly.
- Scrollbar thumb moves smoothly during the glide.
- `exercise-13-3.html` (transform transition example): scrolling now smooth.
- Remove `scroll-behavior: smooth` from the page → instant scroll again
  (fast `applyScroll` path, unchanged).

## Follow-ups (not in this exercise's scope)

- Wheel/trackpad staying instant on smooth pages (see Step 3 note).
- Animating `scrollToFragment` and `scrollTo(focus)` — real browsers animate
  those under `scroll-behavior: smooth` too.
- Fling/momentum scrolling: replace the fixed-frame `ScrollAnimation` with a
  velocity + friction model (`v *= 0.95` per frame, stop under a threshold).
- Browser-thread scroll animation (Option B) if tab frames ever get expensive.

## Colors

Proof page uses only colors already in `PaintCommand.swift`: lightblue,
lightgreen, salmon, khaki, gold, orchid, tomato, steelblue, whitesmoke.

## Recording review — 2026-07-04 (`Screen Recording 2026-07-04 at 20.54.52.mov`)

Reviewed frame-by-frame (60fps slit-scan of the scroll position over time).

### What checks out ✓

- **Single press (section 1):** one smooth ease-out ramp per key press,
  roughly a dozen frames — fast at the start, flattens at the end. No jump.
- **Mashing (section 2):** presses accumulate into one taller, longer ramp
  instead of restarting — the retarget-from-`target` logic works.
- **Mixed directions (section 6):** down-then-up shows a V-shaped notch in
  the scroll trace: the up press retargets from where the animation was
  heading, exactly as designed.
- **Scrollbar thumb** moves smoothly during glides, not in 100px steps.
- **No raster artifacts:** no white flashes or checkerboards during glides —
  the interest-region re-raster keeps up.
- **Fragment links jump instantly** — expected; animating them is a listed
  follow-up, not a bug.

### Suspicious — real bug found

**Fragment jump overshoots the document bottom.** At ~0:39 and again at
~0:42, clicking "jump to the end" (`#end`) leaves the bottom half of the
viewport blank white — the page has scrolled *past* the end of the document.

- Cause: `scrollToFragment` (`Tab.swift:534`) does `scroll = target.y` with
  **no clamp** against the maximum scroll. Every other scroll writer clamps
  (`scrollDown` `Tab.swift:603`, `scrollTo` `Tab.swift:524`, the Step 4
  per-frame clamp) — this one predates the exercise and was never fixed.
- Knock-on effect (visible at ~0:43): with `scroll` stuck beyond the max,
  the arrow keys misbehave. `scrollDown` clamps its *target* to `maxY`,
  which is now *above* the current position — so pressing **down** glides
  the page **up**. The recording shows a chaotic multi-section swing right
  after the second `#end` jump.
- Same unclamped path is reused by same-document back/forward navigation
  (`Tab.swift:731`, `Tab.swift:750`), so going back/forward to a `#end`
  entry overshoots the same way.
- Why Step 4's clamp doesn't save us: it only runs while a `scrollAnimation`
  is in flight. A fragment jump is instant — the bad value commits directly.

### Step 7 — fix: clamp the fragment scroll

Old (`Tab.swift:528-537`):

```swift
private func scrollToFragment(_ id: String) {
    guard let doc = document else { return }
    let target = treeToList(doc).first(where: {
        ($0.node as? Element)?.attributes["id"] == id
    })
    if let target = target {
        scroll = target.y
        scrollAnimation = nil
    }
}
```

New:

```swift
private func scrollToFragment(_ id: String) {
    guard let doc = document else { return }
    let target = treeToList(doc).first(where: {
        ($0.node as? Element)?.attributes["id"] == id
    })
    if let target = target {
        let maxY = max(doc.height + 2 * VSTEP - tabHeight, 0)
        scroll = max(0, min(target.y, maxY))
        scrollAnimation = nil
    }
}
```

Same `maxY` formula as `scrollTo` (`Tab.swift:524`) one function above.

Verify after the fix:

- "jump to the end" → section 8 sits at the bottom of the viewport, no
  white void below it.
- Down arrow at the bottom → nothing moves (already clamped).
- Up arrow at the bottom → one normal upward glide, no chaotic swing.
- Back/forward across the `#end` entry → same clamped position.
