# Resizing browser.engineering: the freeze at 1150px

## What the GUI trace showed

`browser.trace`, recorded on https://browser.engineering/invalidation.html, has about 12 s of
window resizing (no typing). Layout runs on the background thread, one pass per resize step:

| Resize pass | Count | Layout | Paragraphs re-broken |
| --- | --- | --- | --- |
| Normal drag frame | ~320 | 7.7 ms median, 11.5 ms p90 | 7 |
| Crossing 800px (`html { font-size: 18px }`) | 4 | ~26 ms | 737 |
| Crossing 1150px (margin column on/off) | 5 | 205–245 ms | ~1,400–1,480 |

## Why 1150px froze

`book.css` switches `div#toc` to `display: none` and `nav#toc` to `display: block` at
`min-width: 1150px`, so `body`'s list of child blocks has to be rebuilt.
`rebuildBlockChildren` made a new block for every child, so the whole page was laid out
from nothing: 1,849 new blocks (every one a block-style cache miss), 1,645 paragraphs
refreshed and broken into lines again.

## Fix

`a7da77f` `perf: no freeze when resizing across a page's layout breakpoint`: a rebuilt
child list takes back each old child block whose DOM nodes still form it, the same element
for a plain block, and the same run of nodes for an anonymous or run-in block. A kept block
only gets its new previous sibling; the dependency index moves whatever reads it.

Headless, crossing 1150px in both directions (`--resize-at`):

| | Before | After |
| --- | --- | --- |
| Layout pass | ~257–290 ms | ~30 ms |
| Blocks kept | 0 | 754 |
| Paragraphs refreshed | 1,570–1,645 | 28–101 |

The frame after each crossing is pixel-identical to a fresh load at that width.

## Still open

- A normal drag frame still lays out every block (7.7 ms), because every block's width
  changes. Most paragraphs reuse their line plan; the cost is the walk itself.
- `composite_raster_and_draw` is 5.1 ms median, 11.3 ms p90 during the drag.
- The float re-check (about 1.1 ms per keystroke while typing at 1300px) is unchanged; it
  does not affect resizing, where every block is visited anyway.
