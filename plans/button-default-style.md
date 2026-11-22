# Button default style like real browsers

## What was wrong

`<button>` had a toy look: an orange face (`browser.css`), a 16px font, and a
1px black frame that `emitButton` (`Sources/Engine/Display/PaintEmit.swift`)
always drew, even when the page said `border: none`. A page that set
`background-color: transparent` still got a white face.

## What real browsers do

Chromium's own stylesheet gives a button `border: 2px outset ButtonBorder`,
`padding: 1px 6px`, `background-color: ButtonFace`, `color: ButtonText` and a
13.333px font. Because a button has `appearance: auto`, Chromium does not paint
that outset border. It paints its own look instead: a 1px ring with a 2px
rounded corner, filled with the face color
(`ui/native_theme/native_theme_base.cc`, `PaintButton`).

The system colors come from `third_party/blink/renderer/core/layout/layout_theme.cc`:

| Color | Light | Dark |
|---|---|---|
| ButtonFace | `#efefef` | `#6b6b6b` |
| ButtonBorder | `#767676` | `#6b6b6b` |
| ButtonText | `black` | `white` |

## What changed

- `browser.css`: the button gets the colors above, `border: 1px solid`,
  `border-radius: 2px`, `font-size: 13.333px` and `padding: 2px 7px`. One pixel
  of border plus 2px/7px of padding is the same outside size as Chromium's 2px
  border plus 1px/6px padding, and it draws the same 1px ring.
- `PaintEmit.swift`: the button paints only what its CSS says. The face uses
  the rounded corners; the border comes from the normal border painter. The
  same face code now serves `<input>` too (`emitEmbedBackground`).
- Forced colors keep a visible ring: `ForcedColor.swift` already turns every
  set border color into `ForcedColor.buttonBorder`.

## Colors not named in BrowserColor.swift

`#efefef`, `#767676`, `#6b6b6b` are written as hex in `browser.css`; they have
no CSS name in `namedColor`.

## Label width and centering

CSS 2.1 §10.3.9 gives an auto-width inline-block the shrink-to-fit width of
§10.3.5: `min(max(preferred minimum width, available width), preferred width)`.
Real browsers center the label with `button { text-align: center }`.

- `ButtonLabelPiece.swift`: the label as words, line breaks, and inputs, each
  measured once. `shrinkToFit` finds the narrowest (widest word) and widest
  (longest line) label, leaving out the space after each line's last word
  (CSS Text 3 §4.1.2).
- `EmbedLayoutPass.swift`: `layoutButton` and `embedLineWidth` both size the
  button from the same pieces, so the room the paragraph keeps for the button
  matches the button. Words wrap inside the button only when the paragraph is
  narrower than the label. Every button line is centered.
- `LineLayoutPass.swift`: a centered line leaves out the space after its last
  word, so the label sits in the middle instead of half a space to the left.
- `LayoutInputTable.swift`: the button's width now depends on its font, its
  padding and border, and the width of the block around it.

Choice: button lines always center, rather than adding a `text-align`
property. A page's `text-align` on a button is ignored, like every other
`text-align` in this engine today.

## Space around buttons and other embeds

Line breaking (`BlockLayoutPass.swift`, `placement.cursorX += w + font.spaceWidth`)
keeps one space after every embed. Line layout (`LineLayoutPass.swift`,
`place`) put that space before the embed instead. A word's width already
carries its own space, so an embed after a word got two spaces, and the word
after an embed got none.

Line layout now adds the space after an embed, as line breaking does. An
inline box around an embed still ends at the embed, not after its space.

### Which font the space uses

In a real browser the space after `</button>` is part of the text node that
follows, so it has that text's font, not the button's. The engine splits text
into words and forgets where the whitespace was, so it uses the closest match:

- Before a word: that word's font.
- Before another embed: the font of the text around that embed (its parent's),
  `surroundingTextFont` in `EmbedLayoutPass.swift`.
- At the end of a line: no space.

All the places that measure a line agree on this:

- Line breaking: `spaceAfterEmbed` in `BlockLayoutPass.swift` looks ahead to
  the next word or embed, skipping box edges, floats, and hidden inputs.
- Line layout: `spaceAfter` in `LineLayoutPass.swift` looks at the next piece
  on the line.
- Float sizing: `IntrinsicLine` in `IntrinsicWidthPass.swift` adds the space
  together with the next piece (`followsEmbed`), so a float keeps its words on
  one line.
- Button labels: `ButtonLabelPiece.append` sets an input's `spaceAfter` from
  the piece that follows it.

## Still different from real browsers

- The label uses the page font, not the system font.
- No hover/pressed face (`#e5e5e5` / `#f5f5f5` in Chromium).
- A CSS `width` on a button is ignored.
- Two embeds with no whitespace between them (`<img><img>`) still get a space,
  because the engine does not remember where whitespace was.
- `<img> <b>bold</b>`: the space is in the paragraph's text, but the engine
  uses the bold word's font, for the same reason.

## Tests

- `Tests/ToyStackTests/Resources/UserAgentButtonStyleTests.swift`: light and
  dark defaults, box size.
- `Tests/ToyStackTests/Display/ButtonPaintTests.swift`: rounded face and gray
  ring, `border: none`, transparent face, forced colors.
- `Tests/ToyStackTests/Layouts/ButtonLayoutTests.swift`: width fits the label,
  centered short line, wrapping in a narrow paragraph, one space after the
  button, an input inside the label followed by a space in the next word's
  font, and incremental layout matching a full rebuild after label edits, font
  changes, and narrowing.
- `Tests/ToyStackTests/Layouts/EmbedSpacingTests.swift`: one space before and
  after an image, a bordered span that ends at the image inside it, the space
  after a button in the next word's font, the space between two buttons in the
  paragraph's font (and after the span around them changes font), a word that
  just fits after a large button, and a float around a small button.
