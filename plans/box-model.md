# Box model: borders that take space, and `box-sizing`

## Where we started

- A block's `x`/`y`/`width`/`height` is its **content box**. Padding sits outside it
  (`blockSelfRect`, `Sources/Engine/Layouts/BlockLayoutPass.swift`).
- Borders were **painted only**: drawn just outside the padding box, but layout never
  made room for them. A 5px border spilled over the parent's edge and under the next
  sibling, and the parent did not grow.
- `width`/`height` already behaved like `box-sizing: content-box`. `box-sizing` itself
  was not parsed.

## Design decision

- **Option A**: add `box-sizing` only and subtract padding + border from `width`.
  Small, but borders still overlap their neighbours.
- **Option B (chosen)**: first make borders take layout space, then add `box-sizing`.
  Matches real browsers. Touches flow layout, paint rectangles, and clipping.

## Step 1: borders take space (commit `feat: borders take up room on the page`)

| File | Change | Why |
| --- | --- | --- |
| `Style/BoxStyle.swift` | `Border.usedWidth` | CSS Backgrounds 3 §3.3: none/hidden border has used width 0, so the initial `medium` (3px) takes no space |
| `Layouts/BlockLayoutPass.swift` | `border(_:)` helper; `placeBlockFrame` moves content in by the border, subtracts it from auto width, and moves the next sibling below the previous one's bottom border; `flowHeight` and `boxHeight` add top + bottom border; `blockSelfRect` is now the border box | Border sits between padding and margin |
| `Layouts/LayoutInputTable.swift`, `blockHeightInputs` | `border-width` and `border-style` are inputs of `x`, `y`, `width`, parent `height`, document `height` | Incremental layout must redo the box when its border changes |
| `Display/PaintScene.swift` | `PaintGeometry.border` + `paddingBox` | Paint uses the border layout computed, including anonymous blocks (no border) |
| `Display/PaintEmit.swift`, `DisplayOp.swift` | Stroke is drawn inside the border box at the zoomed width; background image is placed in the padding box (§2.8 `background-origin`) and clipped to the border box (§2.7 `background-clip`) | Painted border must fill exactly the space layout reserved |
| `Display/PaintPass.swift` | `overflow: hidden/clip/scroll` clip to the padding box | CSS Overflow 3 §2.3 / §3.2 |
| `Core/Rect.swift` | `inset(by:)` | Shared helper |

Tests: `Tests/ToyStackTests/Layouts/BorderLayoutTests.swift`,
`Tests/ToyStackTests/Display/BorderPaintTests.swift`.

## Step 2: `box-sizing` (commit `feat: box-sizing: border-box keeps a box at the size you set`)

| File | Change |
| --- | --- |
| `Style/BoxSizing.swift` (new) | `BoxSizing` enum (`contentBox`, `borderBox`) and `contentSize(specified:paddingAndBorder:)`: CSS Sizing 3 §3.3, floored at zero |
| `Style/BoxStyle.swift` | `Size` gains `boxSizing`; `maxWidth` + `aspectRatio` move into `Size.Constraints` to keep four stored properties |
| `Style/StyleProperty.swift`, `ComputedStyle.swift`, `ComputedStyleParser.swift` | parse `box-sizing`, diff it, treat it as a layout property. Not inherited |
| `Layouts/BlockStyle.swift` | `BlockBoxStyle` carries `BoxStyle.Size` instead of loose `width`/`height` |
| `Layouts/BlockLayoutPass.swift` | specified `width` and `height` go through `contentSize` |
| `Layouts/LayoutInputTable.swift`, `blockHeightInputs` | `box-sizing` is an input of `width` and `height`; `height` also depends on the box's own padding and border |

Tests: `Tests/ToyStackTests/Layouts/BoxSizingLayoutTests.swift`,
`Tests/ToyStackTests/Style/BoxSizingStyleTests.swift`.

Demo: `www/box-sizing.html` (`swift run ToyStackHeadless file://$PWD/www/box-sizing.html --screenshot out.png`).

## Step 3: follow-up fixes

| Commit | What changed | Where |
| --- | --- | --- |
| `fix: pages using CSS zoom on an element no longer trip layout` | `setFrame` announces a zoom change before it marks the box's frame clean | `Layouts/LayoutTree.swift` |
| `fix: the resize layout test no longer fails on a busy machine` | the test ticks until the new width is painted; slow frames show a scaled preview first | `Tests/.../Core/ResizeLayoutStartTests.swift` |
| `feat: each side of a border can have its own width, style and color` | shorthands expand to per-side longhands; `Border.Sides`; layout and paint per side; `EdgeInsets` moves to `Core/` | `Parsing/CSSParser.swift`, `Style/BoxStyle.swift`, `Layouts/BlockLayoutPass.swift`, `Display/PaintEmit.swift` |
| `feat: rounded borders follow their curve, and content clips to the inner curve` | `CornerRadii.inner` (CSS Backgrounds 3 §4.2); `ring` display op filled even-odd | `Style/CornerRadii.swift`, `Display/DisplayOp.swift`, `Platform/CGRenderer.swift` |
| `feat: images, iframes and form controls take room for their padding and border` | embeds keep a content-box frame; the line reserves their edges; margin box sits on the baseline (CSS 2.1 §10.8.1); box-sizing applies to `width`/`height` attributes; the iframe 1px hack is gone | `Layouts/EmbedLayoutPass.swift`, `Layouts/LineLayoutPass.swift`, `Core/Frame.swift` |
| `fix: text after a link or bold word no longer starts with a stray space` | `TextRun` records a word's start after its separator | `Layouts/TextRun.swift` |
| `feat: spans, links and other inline elements show their padding, border and background` | `InlineItem.boxEdge` marks, `InlineFlowEvent` per line, `InlineBoxFragment` per element per line (CSS 2.1 §8.6, §10.6.1); paint and hit test read the fragments | `Layouts/BlockLayoutPass.swift`, `Layouts/LineLayoutPass.swift`, `Display/PaintSceneBuilder.swift` |

Demo: `www/box-model.html`.

## Step 4: the old known limits

| Limit | What changed | Where |
| --- | --- | --- |
| A rounded border was painted in the color of its first visible side | A border that is not one solid color is painted side by side. CSS Backgrounds 3 §4.4 only bounds where two sides may change over and leaves the look undefined; like Chromium, each side owns the part of the corners on its side of the line from the outer corner through the padding-box corner, carried on to the chord of the inner curve. New `borderSide` display op: the band's ring, cut to the side's region | `Display/BorderPainter.swift`, `Display/BorderSidePaint.swift`, `Core/Quad.swift`, `Platform/CGRenderer.swift` |
| Right-to-left inline boxes put their start edges on the left | The start edge of a right-to-left element is its right one (CSS 2.1 §8.6): block placement reserves the start/end widths, the line puts the end edge at the fragment's left and the start at its right, and paint asks the fragment which side edges it carries. An inline element's `direction` is now a layout input | `Layouts/BlockLayoutPass.swift`, `Layouts/LineLayoutPass.swift`, `Layouts/InlineBoxFragment.swift`, `Display/PaintSceneBuilder.swift` |
| A background-only inline element covered the space after its last word | Every text piece's measured width ends with one space; paint takes it off before covering the piece, the same rule the line uses for fragments | `Display/PaintSceneBuilder.swift` |
| Every border style painted solid | `double` is two bands of a third each; `groove`/`ridge` split the width into a sunken and a raised half; `inset`/`outset` shade the top-left or bottom-right side; `dotted` and `dashed` stroke the side's middle line (`BorderSideLine`), which runs through the whole corner curve, with dots or dashes at both ends and even gaps (§3.2 note on symmetrical corners) | `Style/BoxStyle.swift`, `Display/BorderPainter.swift`, `Display/BorderSideLine.swift` |

Mixed colors on square corners are now cut on the corner line too, so
`eachSidePaintsItsOwnWidthAndColorUpToTheCornerLine` replaced the old rectangle check.
The side regions are clipped without antialiasing: two antialiased clips meeting on the
same diagonal leave a faint seam.

Tests: `Tests/ToyStackTests/Display/BorderPaintTests.swift`,
`Tests/ToyStackTests/Display/BorderStylePaintTests.swift`,
`Tests/ToyStackTests/Display/InlineBoxPaintTests.swift`,
`Tests/ToyStackTests/Layouts/InlineBoxModelTests.swift`. Pixel checks read the display
list back through `Tests/ToyStackTests/Support/PagePixels.swift`.

Demo: `www/border-styles.html`.

## Known limits

- Inline element backgrounds ignore `border-radius`.
- Where two sides of different styles meet (for example dotted and solid), the corner is
  simply cut on the corner line; CSS leaves the look of that join undefined.
- A border painted side by side (several colors or a non-solid style) has its corner
  lines clipped without antialiasing, which also snaps its straight outer and inner edges
  to whole pixels. On a box at a fractional position (inline pieces, zoomed pages) those
  edges can sit up to half a pixel off, unlike a single solid color.
- Dots and dashes are spaced per side, so on a rounded corner the pattern of one side
  can meet the other's unevenly at the corner line.

## Colors

The demos only use colors from `BrowserColor.swift`. Painting adds one computed color:
the shadow tone of a black `groove`, `ridge`, `inset` or `outset` border is
`rgb(84, 84, 84)`, since black has no darker tone. Other colors shade by scaling their
channels down.
