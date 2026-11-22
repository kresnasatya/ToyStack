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
inline box around an embed still ends at the embed, not after its space. Inside
a button, an input is followed by a space too (`ButtonLabelPiece.advance`), so
the label's width still matches where its words land.

## Still different from real browsers

- The label uses the page font, not the system font.
- No hover/pressed face (`#e5e5e5` / `#f5f5f5` in Chromium).
- A CSS `width` on a button is ignored.
- The space after an embed uses the embed's own font. In a real browser it
  belongs to the text that follows, so after a 13.333px button it is the
  paragraph's 16px space (about 0.6px wider).
- Two embeds with no whitespace between them (`<img><img>`) still get a space,
  because the engine does not remember where whitespace was.

## Tests

- `Tests/ToyStackTests/Resources/UserAgentButtonStyleTests.swift`: light and
  dark defaults, box size.
- `Tests/ToyStackTests/Display/ButtonPaintTests.swift`: rounded face and gray
  ring, `border: none`, transparent face, forced colors.
- `Tests/ToyStackTests/Layouts/ButtonLayoutTests.swift`: width fits the label,
  centered short line, wrapping in a narrow paragraph, one space after the
  button, an input inside the label, and incremental layout matching a full
  rebuild after label edits, font changes, and narrowing.
- `Tests/ToyStackTests/Layouts/EmbedSpacingTests.swift`: one space before and
  after an image, and a bordered span that ends at the image inside it.
