# Bugfix: Clicks on text inside a box are silently ignored

**Date:** 2026-07-04
**Evidence:** `Screen Recording 2026-07-04 at 10.19.45.mov`
**Affected exercise:** 13-9 (hit testing), but the bug affects *every* click listener in the engine.

## Symptom

In the recording, box 1 ("Plain box - no transform") on `/exercise-13-9` is clicked
four times. The first three clicks do nothing. Only the fourth updates the status
line to `Hit: plain`.

| Time in video | Where the click landed | Result |
|---|---|---|
| ~3.8s | On the text glyphs ("1. Plain...") | Ignored |
| ~6.3s | On the text glyphs | Ignored |
| ~7.0s | On the text glyphs | Ignored |
| ~10.2s | Past "(baseline)." — bare gray area of the box, no text | `Hit: plain` appears on the next frame |

The pattern is position-dependent, not a lag: clicking the **text** inside the box
is dead, clicking the **empty painted area** of the same box works. In a real
browser both clicks fire the div's listener, because events bubble from the text
up to the element.

## Root cause

Three pieces combine:

1. **Hit testing returns the deepest layout object.**
   `Sources/Engine/Layouts/LayoutObject.swift:37-44` checks children first, so a
   click on glyphs returns the `TextLayout`, and `source.node` is a `TextNode`.
   A click on the bare gray area returns the `BlockLayout` for `div#plain`.

2. **The click is dispatched on that innermost node.**
   `Sources/Engine/Tab.swift:790`:
   ```swift
   let prevented = js.dispatchEvent(type: "click", elt: source.node)
   ```
   This is correct in principle — `runtime.js` is supposed to bubble the event up
   the parent chain (`Sources/Engine/Resources/runtime.js:87-92`).

3. **The bug — `Sources/Engine/JSRuntime.swift:29`:**
   ```swift
   let handle = nodeToHandle[ObjectIdentifier(elt)]
   ```
   This is a raw dictionary lookup, not a call to `getHandle(_:)`. Handles are
   only minted when JS first sees a node (e.g. via `querySelectorAll`). A
   `TextNode` has never been seen by JS, so the lookup returns `nil`:
   - `__handle` is set to null in the JS context,
   - `new Node(null)` has no listeners under `LISTENERS[null]`,
   - bubbling dies too, because `_getParent` (`JSRuntime.swift:181`) can't
     resolve a node from a null handle.

   The event therefore never reaches the `div#plain` listener registered in
   `www/ch13/exercise-13-9.js`.

Clicking the div's bare area works only because the exercise script happened to
call `querySelectorAll("#plain")`, which minted a handle for the div itself.

## Fix

One line in `Sources/Engine/JSRuntime.swift:29`, inside `dispatchEvent(type:elt:)`:

| | Code |
|---|---|
| Old | `let handle = nodeToHandle[ObjectIdentifier(elt)]` |
| New | `let handle = getHandle(elt)` |

`getHandle(_:)` (defined at `JSRuntime.swift:38`) returns the existing handle or
mints a fresh one on demand. With a valid handle, `Node.prototype.dispatchEvent`
in `runtime.js` finds no listener on the `TextNode` itself, then bubbles to its
parent `div#plain`, whose listener fires — matching real browser behavior.

No other call sites need to change: `dispatchEvent` is the only place that read
`nodeToHandle` directly instead of going through `getHandle`.

## Verification checklist

After the fix, on `/exercise-13-9`:

1. Click directly on the **text** of box 1 → status must show `Hit: plain`
   immediately (this was the broken case).
2. Click box 2 **where it is drawn** (shifted by translate(150px, 40px)) →
   `Hit: shifted`. Click its **original, pre-transform spot** → must NOT report
   `shifted`.
3. Click box 3 (yellow, inside a transformed parent) → `Hit: inner` — proves
   stacked transforms are undone correctly on the way down.
4. Click the **overlap** of boxes 4 and 5 → must report `Hit: over` (box 5 is
   painted later; topmost wins because children are hit-tested in reverse order).

Cases 2-4 were never exercised in the recording — worth testing on text *and*
on bare box areas now that both paths work.

## Broader impact

Any page where a listener sits on an element whose clickable area is mostly
text (links, buttons, list items) had the same dead-click behavior whenever the
click landed on glyphs and the text node had no JS handle yet. The fix resolves
all of these at once.
