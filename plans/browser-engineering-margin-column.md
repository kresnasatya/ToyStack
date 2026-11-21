# browser.engineering margin column: table of contents and cover ad

## Problem

On https://browser.engineering/invalidation.html the table of contents disappeared,
and once it came back, the cover ad drew as a huge box across the top of the page.

The book's stylesheet builds a right-hand margin column only on wide windows:

```css
nav#toc { display: none; }
@media only screen and (min-width: 1150px) {
    body { width: 60ch; padding: 0 17ex 0 0; }
    nav#toc { display: block; }
    aside.ad .wide {
        float: right; width: 25ex; clear: right; margin: 0 -28ex 1em 0;
        display: block; box-sizing: border-box;
    }
}
nav#toc { float: right; width: 25ex; clear: right; margin: 0 -28ex 1em 0; }
```

ToyStack could not follow any of this:

| Missing piece | Effect |
| --- | --- |
| `@media only screen and (...)` | The whole block was thrown away, so the table of contents stayed `display: none` |
| `em`, `ex`, `ch` lengths | `width: 25ex`, `margin: ... -28ex 1em 0`, `body { width: 60ch }` were ignored |
| `margin-left` / `margin-right` | The negative right margin could not push anything into the page margin |
| `float` / `clear` | The ad and the table of contents stayed in the normal flow at full width |

## Decisions

- **Floats, option A.** A block-level float leaves the normal flow, sits against the
  left or right edge at its place in the flow, and adds nothing to its parent's height.
  Text does **not** wrap around it. That is enough for this page, because every float
  is pushed into the margin. Wrapping text around floats is a separate, larger step:
  the line breaker assumes one width per block (`inlineTextLinePlan`,
  `canSkipInlineChildren` in `BlockLayoutPass.swift`).
- **Units: em + ex + ch** resolved once when the style is computed, using real font
  measurements (`CTFontGetXHeight` for ex, the width of `"0"` for ch), as CSS Values 4
  §6.1.1 asks.
- **Horizontal margins** apply to element blocks only. Anonymous blocks keep zero
  margins, just as they keep zero padding.

## Commits

1. `fix: the table of contents shows again on wide windows`.
   `CSSParser.mediaQuery` accepts `only`, a media type (`screen`/`all`), and
   `and (feature)`. `print` and other types still drop their block.
2. `fix: sizes written in em, ex, and ch now take effect`: `FontRelativeUnits`
   (`Sources/Engine/Style/FontRelativeUnits.swift`). The text part of
   `ComputedStyleParser.parse` now runs first, so box lengths know the element's own
   font. A node with em/ex/ch box lengths skips the text-only `reapplyInherited`
   shortcut, which would otherwise keep old pixel values after a media query changes an
   ancestor's font size.
3. `fix: left and right margins now move and narrow blocks`: `placeBlockFrame`
   adds `margin-left` to x and takes both margins out of an auto width.
4. `feat: boxes can float to the left or right edge`: `float`/`clear` in
   `LayoutStyle.Positioning`, plus `FloatLayoutPass.swift`.

## How clear stays correct when layout reuses old results

`clear` must look at every earlier float in the same block formatting context
(CSS 2.1 §9.5.2). On this page the table of contents clears the ad, and the ad lives
inside a different parent (`aside`). Those floats are not layout inputs of the clearing
block, so a change to them would never mark it dirty.

Instead, the document keeps the set of clearing blocks (`DocumentData.clearingBlocks`).
`markClearingBlocks()` marks their `y` dirty on every layout pass that does work, so
they re-place themselves after every earlier float is already laid out. Clearing blocks
are rare, so this costs little. `FloatLayoutTests` checks both the cross-parent cases
(`showingAnEarlierFloatMovesTheClearingBlock` and
`growingAnEarlierFloatMovesTheClearingBlock`) against a full rebuild.

## Known gaps

- Text does not wrap around floats.
- An auto-width float takes the full available width. It does not shrink to fit its
  content (CSS 2.1 §10.3.5).
- Two floats on the same side without `clear` can overlap. They are not placed side by
  side.
- Inline-level floats (for example the book's `span.note { float: right }`) are still
  laid out inline.
- A parent only grows to contain its floats through a clearing block (the
  `clear: both` trick). New formatting contexts (CSS 2.1 §10.6.7) do not grow around
  their floats on their own.
- `list-style: none` and `#toc:before { content: ... }` are not supported, so the table
  of contents still shows bullets and has no "Table of Contents" heading.

## Next steps

1. Wrap text around floats: give each line its own available width, taken from the
   floats beside it.
2. Shrink-to-fit width for floats, which needs each box's preferred width.
3. Place same-side floats next to each other (CSS 2.1 §9.5.1 rules 2, 3, 7).
