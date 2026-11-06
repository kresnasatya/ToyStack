# Growing past the breakpoint leaves the font size stale until a hover

Status: **open** (2026-11-06). Trace timeline captured; the trace file was later
overwritten by a test harness, so the numbers below are from the parsed data
before that.

## Scenario

Window starts small (489 pt). The user drags it to medium (1192 pt), crossing
the `max-width: 800px` breakpoint in `book.css` (`html { font-size: 24px }` vs
`18px`). The text stays at the small size until the pointer hovers over a link.

## Trace timeline

| t (s) | Event | Detail |
|---|---|---|
| 6.451-6.760 | 19 resize events | 489 -> 505 -> ... -> 1192 |
| 6.453-6.770 | preview presents | one per resize, old frame |
| 6.577 | width 841 | breakpoint crossed |
| 6.587 | `style.invalidate.viewport` | flip detected |
| 6.590 | style pass | flipped=1, applied=368, force=367, **changed.font-size=1** (html only), fields.set=42 |
| 6.789 | paint | nodes=231, ops=100, `stB=113`, `stL=52` (full re-emit) |
| 6.796 | present | new generation: placements=100, added=100, deferred=70 |
| 6.833 / 6.868 | drains | deferred 40 / 10 |
| 6.898 | present | deferred=0, sublayers=100: generation complete, swap |
| 6.898-7.811 | **no presents** | ~0.9 s idle |
| 7.811 | hover | 4 nodes invalidated |
| 7.814 | style pass | applied=12, force=9, direct=3, **changed.font-size=6**, fields.set=504 |
| 7.832 | paint | nodes=231, ops=100, `stB=113`, `stL=52` (another full re-emit) |
| 7.835 | present | new generation: added=100, deferred=70, sublayers=200 |
| 7.976 | present | deferred=0, sublayers=100 |

Every later hover repeats the same pattern: style pass -> full 100-tile
generation (about 1.97 MP of layer binds across three presents).

## What the trace says

1. The media flip ran at 6.590 and propagated through all 368 style nodes
   (`force=367`). The first post-grow paint at 6.789 re-emitted every block and
   line, and the presenter bound and swapped a 100-tile generation at 6.898.
2. A second style pass at 7.814 (hover) still reports a **font-size change on
   6 nodes** and triggers another layout and another full generation. A hover
   rule in `book.css` changes colour, background, opacity, or cursor, never
   font-size. So those 6 nodes were still holding the pre-flip font size after
   the resize, and the hover's forced subtree re-applied them.
3. The present at 6.898 completed, so the small text on screen was not a
   missing present. It is a style-tree problem: part of the tree did not take
   the flip, and nothing until the hover forced it.

## Open questions

- Which 6 nodes are they? Candidate cause: force propagation stops at a node
  whose own text did not change (`StyleCascade.inheritedChanged`), so a
  descendant whose inherited text should change is not visited. Needs a
  diagnostic that logs the node tag/class of each `font-size` change in the
  hover pass, or a test page with an absolute-size wrapper and a
  percentage-size child.
- The same trace also shows the presenter cost: every hover starts a new
  100-tile generation (`setNeedsComposite` per paint), which is recommendation
  #2/#3 in `resize-flow-diagrams.md`.

## Note on the trace artifact

The GUI trace was overwritten at 23:08 by an in-process harness constructing
`Browser(tracePath: nil)`, which defaults to `./browser.trace`. Harnesses must
pass an explicit temp path. Re-capture if a follow-up needs the raw events.

## The 6 nodes are named (2026-11-06)

Reproduced the hover pass with the audit log on the same page and chain. The
"font-size changes" on hover are one-ULP floating-point differences:

```text
font-size 28.8 -> 28.799999999999997 <ol>#  . parent=<section>#introduction ''
font-size 28.8 -> 28.799999999999997 <text># . parent=<ol># ''
font-size 28.8 -> 28.799999999999997 <a>#   . parent=<li># 'Preface'
font-size 28.8 -> 28.799999999999997 <text># . parent=<a># 'Preface'
font-size 28.8 -> 28.799999999999997 <text># . parent=<ol># ''
font-size 28.8 -> 28.799999999999997 <text># . parent=<ol># ''
```

So the six nodes in the recording are the hovered TOC chain:

1. the `<ol>` inside `<section id="introduction">`
2. the `<a>` title (for example "Preface") inside its `<li>`
3-6. the text nodes under that `ol`/`a`

The change is not a real style change: `28.8` and `28.799999999999997` are
adjacent doubles. It comes from `applyNodeStyle` serializing a percentage
font size back into CSS (`newStyle["font-size"] = "\(percentage/100.0 *
Double(parentPx))px"`) and reparsing it, which can round one ULP differently
than plain inheritance. `ComputedStyle.changed(from:)` compares the two
exactly, so the phantom difference:

- sets `hasLayoutChanges` and schedules a full layout,
- misses every block paint cache (`stB=113`) and every line cache
  (`stL=53`) in the trace,
- starts a new 72-81 tile composite generation on every hover.

The hover's second layout is what appears to "fix" the text size. The first
layout after the flip must be leaving the value-line boxes with the old font
(`refreshReusedLine` returns early for value lines because they have no text
children); the hover's phantom change forces another pass that rebuilds them.

## Fix direction

1. Compare `font-size` with a small tolerance in `ComputedStyle.changed`
   (or keep the converted px value instead of the percentage string round
   trip), so a hover cannot manufacture a style change.
2. Do not rely on that extra pass: refresh the value lines' box fonts in
   `refreshReusedLine` (or force the plan-reuse branch to rebuild lines when
   the font changes). Otherwise removing the phantom change could leave the
   text small until an unrelated layout.
3. Test: grow across the breakpoint, paint, and assert every line box font
   equals the owning element's computed font size; no hover needed.

## Resolution (2026-11-07)

The cause is confirmed, and it is the first item in "Fix direction": the
percentage font size was resolved twice with different arithmetic.

`applyNodeStyle` rewrote `font-size: 120%` into a px string
(`percentage / 100.0 * parentPx`, i.e. `1.2 * 24` -> `28.799999999999997`),
then the parser re-parsed it. The flip path took a different route and got
`24 * 120 / 100` -> `28.8`. One ULP apart, but `ComputedStyle.changed` compares
exactly, so the next style pass that re-applied those nodes (a hover) saw a
real change, marked layout dirty, and rebuilt the page. That rebuild is what
the user perceived as "the text grows when I hover".

Fix: delete the pre-conversion. `ComputedStyleParser.fontSize` is now the only
place a percentage is resolved, from the numeric parent.

Regression test: `hoverAfterFontFlipKeepsPercentageSizesStable` in
`StyleInheritanceTests.swift`. Before the fix it reported

- the chain changing from `[28.8, ...]` to `[28.799999999999997, ...]`
- `layout.visited == 2`

on the first hover pass. It now passes with no layout.

### Correction to the earlier value-line note

The `refreshReusedLine` hypothesis above does not hold. A line without a text
child is never eligible for reuse: `placeInlineItems(plan:oldPlan:...)` requires
`childrenIDs(of: old.line).contains(where: isText)` (BlockLayoutPass.swift:912),
so value lines are rebuilt with their boxes. The first layout after the flip
refreshes every box in both the synchronous and the background-layout paths;
`growingBackAcrossTheBreakpointRefreshesLineBoxFonts` (sync) and
`asyncBreakpointFlipRefreshesLineBoxFonts` (opt-in async) assert that contract.

### Still open: the missing block of text

The recording also shows a band of paragraphs whose space is laid out but whose
glyphs are not painted, after the round trip. That is a different symptom and
it did not reproduce in the engine harness: a headless 1308 -> 603 -> 1308 run
(with and without background layout) produced identical rasters before and
after at the same scroll position. The remaining suspect is the GUI presenter:
the resize preview / staged tile generation, not layout. The trace that showed
the resize was overwritten, so the next capture needs the GUI and should log,
at the end of each present: `deferred`, `needsMoreTiles`,
`tileContinuationPasses`, `store.missNew`/`missEvicted`, `entries`, `pixels`,
and the paint window. If `needsMoreTiles` is still true while the animation
clock is idle, the blank band is the unavailable tiles; if it is false, the
band is missing from the display list and the paint window is the suspect.
