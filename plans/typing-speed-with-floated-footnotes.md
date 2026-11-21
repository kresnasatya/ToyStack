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

## Still open

- At 1300px layout still visits 43 blocks per keystroke against 4 at 800px: the floats
  and the paragraphs that read them are re-checked on every pass (`markFloatDependents`).
  The checks find nothing to do, yet the walk to them and their float lookups cost about
  1.1 ms. Tracking which floats changed in a pass would let unchanged readers be skipped.
- Style (3.9 ms) and paint (4.5–4.6 ms) are now most of each keystroke.
