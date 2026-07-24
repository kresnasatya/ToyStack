# Fix: Exercise 14-5 — div with tabindex never gets focus

## Symptom (from Screen Recording 2026-07-24 at 20.49.48.mov)

Pressing Tab in ToyStack: ring on link 1, ring on link 2, then focus jumps
to the address bar. The `<div tabindex="2">` is skipped entirely, so the
whole-block ring from Step 1 of the plan never draws. In Firefox the div
gets its ring.

## Root cause

The plan's Step 1 and Step 2 edits are correct and working — the two link
rings prove it. The problem is upstream: the div never becomes focused.

`Sources/Engine/Tab.swift:797-801` builds the tab-order list with a
hardcoded tag check:

```swift
let focusableElements = treeToList(nodes).compactMap({ n -> Element? in
    guard let el = n as? Element else { return nil }
    let tag = el.tag
    return (tag == "input" || tag == "button" || tag == "a") ? el : nil
})
```

A `<div tabindex="2">` is not `input`/`button`/`a`, so it is filtered out.
`node.isFocused` never becomes true for it, and the ring code in
`BlockLayout.paint()` never fires.

The engine already has the right helpers, unused here:

- `isFocusable()` — `Sources/Engine/DOMUtils.swift:551` — treats any
  element with a `tabindex` attribute as focusable (plus input/button/a).
- `getTabIndex()` — `Sources/Engine/DOMUtils.swift:556` — parses the
  attribute, defaults to 9,999,999 when absent.

## The fix — one file

`Sources/Engine/Tab.swift`, inside `advanceTab()`.

Old (`Tab.swift:797-801`):

```swift
let focusableElements = treeToList(nodes).compactMap({ n -> Element? in
    guard let el = n as? Element else { return nil }
    let tag = el.tag
    return (tag == "input" || tag == "button" || tag == "a") ? el : nil
})
```

New:

```swift
let focusableElements = treeToList(nodes)
    .compactMap { $0 as? Element }
    .filter { isFocusable($0) }
    .enumerated()
    .sorted { (getTabIndex($0.element), $0.offset) < (getTabIndex($1.element), $1.offset) }
    .map(\.element)
```

Why each piece:

- `filter { isFocusable($0) }` — replaces the hardcoded tag list; now any
  element with `tabindex` joins the tab order.
- `sorted` by `getTabIndex` — elements with a small positive tabindex come
  first, everything without the attribute (index 9,999,999) after, which is
  how real browsers order sequential focus.
- `.enumerated()` + comparing `($0.offset)` as tiebreaker — Swift's
  `sorted` does not promise to keep equal elements in their original
  order, so document order is made an explicit second sort key. Without
  this, two links with no tabindex could swap places between runs.

## Expected behavior after fix

Tab order changes: the div (`tabindex=2`, index 2) now comes FIRST, before
the two links (no attribute, index 9,999,999, document order). So:

1. Tab 1 → whole-block ring around "many / lines" (both lines, one ring).
2. Tab 2 → ring around "a bold link".
3. Tab 3 → ring around the long link.
4. Tab 4 → focus leaves the page (address bar), as before.

This matches spec behavior (positive tabindex first), same ordering the
book's Python version gets from `sort(key=get_tabindex)`.

## Note on Stop 2 (wrapping link)

In the recording the ToyStack window is wide enough that the long link
fits on one line, so "one rectangle per line" cannot be observed. Not a
bug — narrow the window (or widen the browser chrome less) until the link
wraps, then Tab to it: one rectangle per line.

## Colors

No paint changes. No new colors.
