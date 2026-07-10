# Plan: Exercise 14-2 — Focus method and events

## Problem

The engine already has an internal notion of focus, but pages cannot
see or drive it:

- `Sources/Engine/Tab.swift:23` holds `focus: Element?`; changes go
  through `focusElement` (`Tab.swift:778-786`), which the Tab key
  (`advanceTab`, `Tab.swift:789`) and mouse clicks (`click`,
  `Tab.swift:812-855`) already call.
- JavaScript has no `focus()` method on nodes
  (`Sources/Engine/Resources/runtime.js` — `Node.prototype` stops at
  `scrollTop`, line 182), and no `focus`/`blur` events are ever
  dispatched — `js.dispatchEvent` (`Sources/Engine/JSRuntime.swift:28`)
  is only used for `click`, `keydown`, and `submit`.

The exercise asks for three things:

1. A JavaScript `focus()` method on DOM elements.
2. `focus` and `blur` events fired when focus moves.
3. `focus()` must only work on focusable elements, and the browser must
   not read an element's position (to scroll it into view) before
   layout is up to date.

## What already exists and gets reused

- `isFocusable` (`Sources/Engine/DOMUtils.swift:537-540`) — the
  focusability rule: `input`, `button`, `a`, or any element with a
  `tabindex` attribute. The new code calls it; no new rule is invented.
- The event plumbing: `JSRuntime.dispatchEvent`
  (`JSRuntime.swift:28-34`) drives `Node.prototype.dispatchEvent` in
  `runtime.js:72-94`, which runs listeners and bubbles up the tree.
  `focus`/`blur` become just two more event type strings through the
  same pipe.
- The "layout up to date" machinery: `focusElement` sets
  `needsFocusScroll` (`Tab.swift:780`) and calls `setNeedsRender()`.
  The scroll itself happens later, inside the animation frame
  (`Tab.swift:482-490`): `render()` runs **first** (rebuilding style
  and layout), and only **then** does `scrollTo(f)` read the element's
  layout position (`obj.y`, `Tab.swift:518-526`). So the position is
  never read against a stale layout — the exercise's warning is
  satisfied by the existing frame ordering, and Step 3 keeps `focus()`
  on that same path instead of scrolling immediately.

## Design decision — where do focus/blur events fire?

- **Option A (recommended): inside `Tab.focusElement`.** It is the
  single choke point every focus change already goes through — Tab key,
  mouse click, and the new JS `focus()`. All of them fire events, which
  matches real browsers (clicking an input fires `focus` too, not just
  calling the method). Trade-off: clicking anywhere already calls
  `focusElement(nil)` first (`Tab.swift:813`), so a click on the
  currently focused element produces a `blur` + `focus` pair where a
  real browser would stay silent. Acceptable for a toy engine.
- **Option B: only in the new JS bridge function.** Events fire only
  when a script calls `focus()`; Tab key and clicks stay silent. Less
  code touched, but wrong behavior — a page listening for `blur` to
  validate an input would never hear about the user tabbing away.

Going with **Option A**.

One more choice inside Option A: `focusElement` gets an early return
when the element is already focused. Real browsers do the same
(re-focusing the focused element fires nothing), and it also prevents
an infinite loop when a `focus` listener calls `focus()` on the same
element — the event dispatch re-enters `focusElement` synchronously.

## Steps

Each step leaves the project building (`swift build`).

### Step 1 — runtime.js: the `focus()` method

Add after the `scrollTop` property (`runtime.js:182-186`):

```js
Node.prototype.focus = function () {
  _focusElement(this.handle);
};
```

The project still builds after this step; calling `focus()` before
Step 2 just crashes the script with `_focusElement is not defined`,
which the exception handler in `JSRuntime.run` (`JSRuntime.swift:22`)
prints without harming the browser.

### Step 2 — JSRuntime.swift: the `_focusElement` bridge

Register alongside the other callbacks, e.g. right after the
`_setScrollTop` block (`JSRuntime.swift:397-412`), inside
`registerCallbacks`:

```swift
jsContext.setObject(
    {
        [weak self] (handle: Int) in
        MainActor.assumeIsolated({
            guard let self, let tab = self.tab,
                let elt = self.handleToNode[handle] as? Element,
                isFocusable(elt)
            else { return }
            tab.focusElement(elt)
        })
    } as @convention(block) (Int) -> Void,
    forKeyedSubscript: "_focusElement" as NSString)
```

Notes:
- The focusability check lives here, on the Swift side, by calling the
  existing `isFocusable` (`DOMUtils.swift:537`) — one source of truth.
  A `focus()` call on a plain `div` hits the `guard` and silently does
  nothing, exactly what the exercise asks.
- `MainActor.assumeIsolated` matches the pattern of every other
  callback that touches the tab (e.g. `_setAttribute`,
  `JSRuntime.swift:101-110`).

### Step 3 — Tab.swift: fire the events in `focusElement`

**Old** (`Sources/Engine/Tab.swift:778-786`):

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

**New**:

```swift
func focusElement(_ node: Element?) {
    if node === focus { return }
    if let previous = focus {
        previous.isFocused = false
        _ = js?.dispatchEvent(type: "blur", elt: previous)
    }
    focus = node
    if let node = node {
        node.isFocused = true
        needsFocusScroll = true
        _ = js?.dispatchEvent(type: "focus", elt: node)
    }
    setNeedsRender()
}
```

Notes:
- `if node === focus { return }` — the early return from the design
  decision. `===` on two optionals compares identity and treats
  `nil === nil` as `true`, so `focusElement(nil)` with nothing focused
  is a no-op (no spurious render).
- Event order: `blur` on the old element first, then `focus` on the
  new one — same as real browsers.
- `_ = js?.dispatchEvent(...)` — the return value means "did a listener
  call preventDefault". Real `focus`/`blur` events are not cancelable,
  so the result is deliberately ignored.
- The `?` after `js` is deliberate: `js` is an implicitly-unwrapped
  optional (`var js: JSRuntime!`, Tab.swift:27) that stays nil until
  `load()` creates it (Tab.swift:153). `js?.` makes the dispatch a
  no-op in that window instead of crashing — same defensive pattern as
  the `guard js != nil` in `runAnimationFrame` (Tab.swift:430).
- `needsFocusScroll = true` now sits inside the `if let node` branch;
  combined with the early return this is equivalent to the old
  `node !== focus` condition.
- Known simplification: our runtime bubbles every event up the tree
  (`runtime.js:87-92`), so `focus`/`blur` bubble too. Real ones don't
  (they have non-bubbling variants; `focusin`/`focusout` are the
  bubbling versions). Fine for a toy engine — the book's runtime has
  the same quirk.

### Step 4 — Tab.swift: route `blur()` through the same choke point

`Tab.blur()` is called when the address bar steals focus
(`Sources/ToyStack/ToyStack.swift:147` and `:240`). It currently
bypasses `focusElement`, so it would skip the new `blur` event.

**Old** (`Sources/Engine/Tab.swift:771-776`):

```swift
public func blur() {
    focus?.isFocused = false
    focus = nil

    setNeedsRender()
}
```

**New**:

```swift
public func blur() {
    focusElement(nil)
}
```

Per the workflow rule this is a replace-after-verify: wire Step 3
first, verify Tab/click focus still works, then collapse `blur()`.

### Step 5 — layout up to date (no code — verify the reasoning)

Nothing to write here, but this is the part of the exercise text to
check off deliberately. When a script calls `focus()`, the chain is:

1. `_focusElement` → `focusElement` → sets `needsFocusScroll`, calls
   `setNeedsRender()` (`Tab.swift:924-928`) which schedules an
   animation frame.
2. Next frame (`Tab.swift:482-490`): `render()` runs first — style and
   layout are rebuilt — and only then `scrollTo(f)` reads the layout
   position.

So even if the script mutated the DOM right before calling `focus()`
(new elements, style changes — anything that moves the target), the
position is read *after* the re-layout, never from the stale tree. The
book's Python version calls `self.render()` explicitly before reading
positions; our port gets the same guarantee from the frame ordering
instead. If a future change ever makes `focus()` scroll immediately,
it must call `render()` first.

### Step 6 — Verify

1. `swift build`
2. Open `www/ch14/exercise-14-2.html`.
3. Click **"Focus the name input"** → the input gets the focus ring,
   the log shows `name input: focus`, and typing goes into the input.
4. Click **"Focus the plain div"** → nothing happens: no ring, no
   event in the log (the div is not focusable).
5. Click **"Focus the tabindex div"** → log shows `tabindex div:
   focus` (the `tabindex` attribute makes it focusable via
   `isFocusable`). No ring is expected — see page note.
6. Click into the name input, then press Tab → log shows
   `name input: blur` (blur fires on keyboard focus moves too —
   that's Option A working).
7. Click **"Focus the far-away input"** → the page scrolls down past
   the filler to the bottom input, which has the ring. This is the
   layout-up-to-date path: the scroll target position was read after
   render.
8. Click the address bar while the input is focused → log shows
   `name input: blur` (Step 4 working).

## Files touched

| File | Why |
|---|---|
| `Sources/Engine/Resources/runtime.js` | Step 1: `Node.prototype.focus` calling the bridge |
| `Sources/Engine/JSRuntime.swift` | Step 2: `_focusElement` callback with `isFocusable` guard |
| `Sources/Engine/Tab.swift` | Step 3: fire `blur`/`focus` events in `focusElement`; Step 4: `blur()` reroute |
| `www/ch14/exercise-14-2.html` + `.js` | Proof page |

## Colors

The proof page uses only `whitesmoke`, `khaki`, `lightblue`, and
`lightgray` — all already in `Sources/Engine/PaintCommand.swift`.
No new colors.

## Out of scope (noted, not done)

- `blur()` as a JS *method* (`elt.blur()`) — the exercise only asks for
  the `focus()` method plus both events. Adding it later is a copy of
  Steps 1-2 calling `tab.focusElement(nil)` when `handle` matches the
  current focus.
- `document.activeElement` — not requested.
- Non-bubbling focus/blur — see the note in Step 3.
