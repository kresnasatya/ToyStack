# Typing speed on browser.engineering with floated footnotes

## Question

Floating the book's footnotes (`span.note { float: right }`) made every footnoted
paragraph beside the margin column re-break its lines on every layout pass. How much
does that cost while typing?

## Method

`ToyStackHeadless` (release build) clicks the chapter's own `contenteditable` box and
types 60 characters, one per tick, so each keystroke renders on its own:

```bash
TEXT=$(python3 -c "print('abcdefghij'*6)")
.build/release/ToyStackHeadless https://browser.engineering/invalidation.html \
  --width 1300 --height 1800 --scale 1 \
  --click-at 1:300:1296 --type-at 1.5:$TEXT \
  --frame-limit 180 --trace /tmp/typing/head-1300-1.trace
```

The box sits at a different height in each layout, so the click's `y` changes: 1296 at
1300px, 948 at 800px, 1348 in the build before floated footnotes (its footnotes are
inline and push the box down). Each setup ran three times, and a screenshot confirmed
the typed text landed in the box.

Per keystroke, the analysis takes the last 60 `profile.layout` events and pairs the
`BrowserTab.style`, `BrowserTab.layout`, and `BrowserTab.paint` spans of the same frame.

| Setup | Commit | Footnotes |
| --- | --- | --- |
| Before | `deefec9` + headless typing | inline, in the text |
| Now, 1300px | `d8949ea` | floated into the margin column |
| Now, 800px | `d8949ea` | hidden by the page's narrow layout |
| Full layout | `d8949ea`, `--force-full-layout` | floated; nothing reused |

## Results

Medians over 180 keystrokes (60 for full layout), in milliseconds:

| Setup | Style | Layout | Paint | Total | p90 total | Blocks visited | Paragraphs re-broken |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Before, 1300px | 3.94 | 8.51 | 4.87 | 17.37 | 18.02 | 9 | 1 |
| Now, 1300px | 4.21 | 10.81 | 5.31 | 20.43 | 22.42 | 49 | 9 |
| Now, 800px | 3.91 | 8.37 | 4.90 | 17.23 | 17.75 | 4 | 1 |
| Full layout | 4.32 | 298.11 | 5.75 | 308.39 | 321.58 | 1849 | 1645 |

Inside layout, from the `profile.layout` counters (medians per keystroke):

| Metric | 800px | 1300px |
| --- | --- | --- |
| `layout.inputs.build` | 7.24 | 7.64 |
| `layout.document` (the whole tree walk) | 1.06 | 3.07 |
| `layout.inline.refresh` (the edited block) | 0.70 | 0.73 |
| `layout.inline.place` | 0.01 | 0.41 |

## What it means

- Floated footnotes cost about **2 ms of layout per keystroke** (the tree walk goes from
  1.06 to 3.07 ms), about 3 ms in total. The 8 extra re-broken paragraphs are the
  footnoted paragraphs that an earlier float reaches below (`FloatRegistry.wrapped`).
  They are rechecked and fully re-broken on every pass even though nothing near them
  changed.
- That is not the biggest cost. **`layout.inputs.build` takes about 7.5 ms on every
  keystroke at every width**: most of the 8.4 ms baseline layout. Rebuilding the layout
  inputs for the whole document per keystroke matters more than floats.
- Incremental layout works: a full rebuild costs 308 ms per keystroke against 20 ms.
- Every setup is over a 60 fps frame (16.7 ms) once style and paint are added; the
  footnotes move it from 17.4 to 20.4 ms.

## After the fixes

1. `52e7beb` `perf: typing no longer re-reads the whole page before layout`: the DOM
   stamps each node with the revision it last changed at, `LayoutInputs` carry the key
   they were built at, and the builder rebuilds only nodes changed since then, on the
   sync and the async (GUI) path. `LayoutInput` became an immutable final class, so a
   build shares unchanged entries instead of copying them; that also made every layout
   read of an input cheaper (the 800px tree walk went from 1.04 to 0.33 ms).
2. `d31ee5d` `perf: paragraphs beside floats keep their lines while typing elsewhere`:
   a block whose lines depend on floats re-breaks only when its content, its float
   signature, its position or width, or one of its own floats changed. "Moved" now
   compares stored geometry instead of trusting the dirty flags.

Same method, three runs each, medians per keystroke in ms:

| Setup | Layout | Total | p90 total | Blocks visited | Paragraphs re-broken |
| --- | --- | --- | --- | --- | --- |
| 1300px, before both fixes | 10.81 | 20.43 | 22.42 | 49 | 9 |
| 1300px, after fix 1 | 3.41 | 12.01 | 12.26 | 49 | 9 |
| 1300px, after fix 2 | 2.93 | 11.50 | 11.77 | 43 | 1 |
| 800px, before both fixes | 8.37 | 17.23 | 17.75 | 4 | 1 |
| 800px, after both fixes | 1.78 | 10.17 | 10.46 | 4 | 1 |

Typing is now inside a 60 fps frame at both widths.

## Style and paint

3. `67884ad` `perf: typing no longer re-copies the page for style matching`: each
   keystroke copied all ~15,000 nodes into the snapshot selector matching reads (about
   3 ms of the 3.9 ms style pass) while only three nodes were restyled. The snapshot now
   keeps the DOM revision it was copied at and recopies only nodes changed since.
4. Paint leaves out blocks far from the viewport: every keystroke built a paint node for
   all 1,849 blocks and walked them, although lines and text outside the paint window
   (viewport plus two screens above and below) were already skipped. Layout now records
   each block's ink extent, its box plus everything inside it, and the scene builder
   skips a block whose extent misses the window. The scene shrank from 2,186 to 501
   nodes; `paint.scene.build` went from 3.31 to 1.17 ms and `paint.pass` from 1.11 to
   0.32 ms.

| Setup | Style | Layout | Paint | Total | p90 total |
| --- | --- | --- | --- | --- | --- |
| 1300px, after fix 2 | 3.94 | 2.93 | 4.67 | 11.50 | 11.77 |
| 1300px, after fix 3 | 0.42 | 2.91 | 4.73 | 8.07 | 8.35 |
| 1300px, after fix 4 | 0.40 | 2.84 | 1.58 | 4.83 | 5.32 |
| 800px, after fix 2 | — | 1.78 | — | 10.17 | 10.46 |
| 800px, after fix 3 | 0.41 | 1.73 | 4.54 | 6.71 | 7.05 |
| 800px, after fix 4 | 0.41 | 1.67 | 1.58 | 3.67 | 4.27 |
| 1300px, after fix 5 | 0.40 | 1.52 | 1.58 | 3.53 | 4.00 |
| 800px, after fix 5 | 0.39 | 1.50 | 1.53 | 3.44 | 3.90 |

5. Floats and the blocks that read them are re-checked only when a float changes: every
   pass marked all of them (`markFloatDependents`), so at 1300px a keystroke visited 43
   blocks against 4 at 800px. Now a float whose box appears, moves, grows, or goes away
   marks the readers after it, and a float dropped from its parent's child list marks
   the readers inside or after that parent. A keystroke at 1300px visits 4 blocks.
   Floats used to be re-placed every pass, which had also been covering a missing input:
   an auto-width float's width comes from its content. It is now re-placed whenever
   layout reaches it, which happens when something inside it changed.

## Still open

- `composite_raster_and_draw` (~1.9 ms, mostly `raster.plan.tiles`) is now the largest
  per-keystroke cost.
