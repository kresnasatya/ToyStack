# Plan: Exercise 14-5 — Mixed Inlines

Make the focus ring correct for two cases:

1. **Nested inlines** — `<a>a <b>bold</b> link</a>`: ring must cover all three
   words together (and one rectangle per line if the link wraps).
2. **Block focus** — `<div tabindex=2>many<br>lines</div>`: one ring around the
   whole block, not one per line.

## Why it is broken today

- `Sources/Engine/Layouts/LineLayout.swift:94-95` only checks the word's
  *direct* parent: `child.node.parent?.isFocused`. The word "bold" has parent
  `<b>`, not the focused `<a>`, so it is left out of the ring.
- A focused `<div tabindex=2>` gets no ring at all: its words' direct parent
  *is* the line's own container node, which line 95 excludes on purpose, and
  `BlockLayout.paint()` (`Sources/Engine/Layouts/BlockLayout.swift:385`)
  never looks at `isFocused`.

## Design choice

**Option A (chosen)**: helper in `LineLayout` that walks up the DOM from each
word to the line's container, looking for a focused element on the way. The
walk stops *at* the container, so a focused block never triggers per-line
rings — the block draws its own ring in `BlockLayout`.

**Option B (rejected)**: tag each `TextLayout` with its focused ancestor during
layout. Faster in theory, more plumbing; lines hold few words so the walk is
cheap.

## Step 1 — Whole-block ring in BlockLayout

`Sources/Engine/Layouts/BlockLayout.swift` — in `paint()`, after the
border-style block (after line 410), add:

```swift
if node.isFocused {
    commands.append(DrawOutline(rect: selfRect(), color: "white", thickness: 4))
    commands.append(DrawOutline(rect: selfRect(), color: "black", thickness: 2))
}
```

Same white-then-black double ring the line version already uses
(`LineLayout.swift:104-105`), so the ring stays visible on any background.

Project still builds after this step. Focused `<div tabindex=2>` now shows
one ring around the whole block.

## Step 2 — Ancestor walk in LineLayout

`Sources/Engine/Layouts/LineLayout.swift` — replace the direct-parent check.

Old (`LineLayout.swift:92-102`):

```swift
var outlineRect: Rect? = nil
for child in children {
    let isFocusedChild =
        (child.node.parent?.isFocused ?? false) && child.node.parent !== node
    if isFocusedChild {
        let childRect = Rect(
            left: child.x, top: child.y, right: child.x + child.width,
            bottom: child.y + child.height)
        outlineRect = outlineRect?.union(childRect) ?? childRect
    }
}
```

New:

```swift
var outlineRect: Rect? = nil
for child in children {
    if hasFocusedInlineAncestor(child.node) {
        let childRect = Rect(
            left: child.x, top: child.y, right: child.x + child.width,
            bottom: child.y + child.height)
        outlineRect = outlineRect?.union(childRect) ?? childRect
    }
}
```

And add the helper below `paint()`:

```swift
// Walks from a word's node up toward this line's container element.
// True when a focused element sits strictly between the two. Such an
// element is inline (it has no layout box of its own), so the line is
// responsible for its ring. The walk stops at the container itself:
// a focused block paints one ring for the whole box in BlockLayout,
// never one per line.
private func hasFocusedInlineAncestor(_ start: any DOMNode) -> Bool {
    var current: (any DOMNode)? = start.parent
    while let ancestor = current, ancestor !== node {
        if ancestor.isFocused { return true }
        current = ancestor.parent
    }
    return false
}
```

How each case resolves:

| Case | Walk | Result |
|---|---|---|
| `<a>a <b>bold</b> link</a>`, "bold" | text → `<b>` → `<a>` (focused) | included in ring |
| `<a>` wraps across lines | each `LineLayout` builds its own rect | one rectangle per line |
| `<div tabindex=2>many<br>lines</div>` | text → parent is the container, walk stops | no line ring; Step 1 draws block ring |
| `<div tabindex=1><p>text</p></div>` | text → `<p>` is the line's container, stop | block ring from `<div>`'s BlockLayout |

## Step 3 — Verify

1. `swift build`
2. Open `www/ch14/exercise-14-5.html`, press Tab:
   - Stop 1: nested-inline link — ring covers "a bold link" as one box.
   - Stop 2: long link that wraps — one rectangle per line, each covering
     that line's words including bold/italic ones.
   - Stop 3: `<div tabindex=2>many<br>lines</div>` — single ring around
     both lines, not two stacked rings.

## Colors

Uses only `white` and `black` — both already exist in
`Sources/Engine/PaintCommand.swift`. No new colors.
