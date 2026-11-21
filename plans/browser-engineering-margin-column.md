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
5. `feat: text wraps around floated boxes`: each line gets its own left/right inset
   from the floats beside it, and drops below them when its first item does not fit
   (CSS 2.1 §9.5). On browser.engineering itself nothing changes on screen: the margin
   column's floats end at the body's right edge, so they never reach the text.
6. `fix: tall lines no longer run into floats below them`: the band a line is checked
   against grows with the line (`InlineExtent`); an item that would push the line into
   a float starts the next line. Embeds report their exact height (`embedExtent`).
7. `fix: floats on the same side line up instead of overlapping`: `FloatPlacer`
   applies CSS 2.1 §9.5.1 rules 2, 3, 5, and 7. `clear` now reads the registry too.
8. `fix: floats without a width shrink to fit their content`: §10.3.5, with preferred
   widths from `IntrinsicWidthPass`.
9. `fix: overflow: hidden boxes sit beside floats instead of under them`: §9.5,
   through `FloatPlacer.room`.
10. `feat: floated text and images inside a paragraph move to the side`: §9.7 makes
    floats block-level; floats inside inline content are placed while the lines break.
    The book's footnotes now sit in the margin column, stacked below the table of
    contents by their `clear: right`.

## How floats stay correct when layout reuses old results

Floats move things that are not their layout inputs:

- `clear` must look at every earlier float in the same block formatting context
  (CSS 2.1 §9.5.2). On this page the table of contents clears the ad, and the ad lives
  inside a different parent (`aside`).
- A paragraph's lines must avoid every earlier float beside it, wherever that float
  sits in the tree.

The document keeps a `FloatRegistry` (`DocumentData.floats`):

| Part | What it holds | How it is kept fresh |
| --- | --- | --- |
| `boxes` | each float's margin box | written by `recordFloatBox` once the float's height is final |
| `positioned` | floats, blocks with `clear`, blocks moved beside floats | `y` marked dirty on every layout pass that does work |
| `wrapped` | paragraphs with shortened lines or floats of their own, plus the floats they were laid out against | `y` marked dirty on every pass; they re-break only if those floats differ |
| `anchors` | where a paragraph put each float inside its inline content | written while the paragraph breaks its lines |

When a float's margin box changes, `markBlocksBeside` walks forward through the
formatting context and marks only the paragraphs that overlap the new box. It stops at
the first block that starts below the float. Paragraphs beside the old box are already
in `wrapped`, so shrinking, moving, or removing a float frees them on the next pass.
Paragraphs far from any float keep reusing their lines.

`FloatLayoutTests` and `FloatWrapLayoutTests` check the cross-parent cases against a full
rebuild. Turning off the forward walk breaks `showingAFloatWrapsAParagraphThatWasFullWidth`.
Turning off the recheck breaks `hidingTheFloatGivesLinesTheirFullWidthBack`.

## Known gaps

- A float inside inline content that does not fit beside the current line goes below
  the line's height so far; the line can still grow after the float is placed.
- A paragraph with floats of its own re-breaks all its lines whenever it is visited,
  and it is visited on every pass while an earlier float reaches below its top. On
  browser.engineering that is every footnoted paragraph beside the margin column; the
  cost was not measured.
- A block that starts its own formatting context keeps its whole margin box off the
  floats (the spec allows this; browsers let the margin slide under). An earlier float
  that starts lower than the block's top still narrows it from the top.
- CSS 2.1 §9.7 also makes absolutely positioned boxes block-level; only floats are.
- A parent only grows to contain its floats through a clearing block (the
  `clear: both` trick). New formatting contexts (CSS 2.1 §10.6.7) do not grow around
  their floats on their own.
- `list-style: none`, `::before`/`::after` content, and CSS counters are not supported,
  so the table of contents shows bullets and no heading, and footnotes have no numbers.

## Next steps

1. Measure footnoted paragraphs during typing on browser.engineering (`browser.trace`)
   before deciding whether their re-breaking needs to be narrower.
2. Let new formatting contexts grow around their floats (CSS 2.1 §10.6.7).
3. Generated content (`::before`, counters) so the footnote numbers appear.
