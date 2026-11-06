# Line Fragments as Values

Status: design. No production code changed yet.

## Goal

Remove layout-tree nodes for text line fragments. A line keeps its text
fragments as values; only lines and embeds remain nodes under a block.

Target: `www/bench/large.html` 450 -> 300 below 60 ms, with byte-identical
screenshots and the same hit-test, accessibility, and paint behavior.

## Evidence

Profile after the prepared-node change:

| Stage | Cost |
|---|---:|
| `layout.document` | 71-75 ms |
| `layout.visit` | 46-51 ms |
| `layout.inline.place` | 32-36 ms |
| `place.finish` | 16.7 ms |
| `place.flush` | 12.5 ms |
| 1,000 new text nodes | 10.4 ms |
| 3,000 reused text nodes | 0.8 ms |

The new-node cost is per-node initialization and dependency registration.
Removing the node removes that cost; it does not remove line breaking, item
placement, or text measurement.

## Current shape

There are two text paths in `BlockLayoutPass`:

1. `placeInlineItems(_:)` creates word-level text nodes with `fragment == nil`.
2. `placeInlineItems(_:plan:oldPlan:refreshMetrics:)` creates one text node per
   contiguous line fragment with `TextFragment(start, count)`.

Both paths put text nodes under a line node. Paint reads `.text` nodes in
`PaintSceneBuilder`; accessibility and hit-testing also use their layout IDs.
`DOMRef.layoutID` for a DOM text node is currently set through
`LayoutTree.setPrimary`.

## Proposed model

Add `InlineBox` as a value type. It is not a `LayoutKind` case and has no
layout links, field store, dirty bits, or dependency entry.

Fields, grouped to stay under four:

```swift
struct InlineBox {
    let dom: NodeID
    let fragment: TextFragment
    let geometry: InlineBoxGeometry
    let text: InlineBoxText
}
```

`InlineBoxGeometry` holds `x`, `width`; `InlineBoxText` holds `font`,
`ascent`, `descent`, and run reference. A line owns `[InlineBox]`. Embeds stay
as child nodes because they have their own image/frame/canvas state.

Order must be preserved: paint, hit-test, and accessibility walk the same
`boxes` array. If embeds interleave with text, the line also needs an ordered
`InlineItemRef` list; do not silently paint all text before all embeds.

## File map

- `Sources/Engine/Layouts/InlineBox.swift` (new): value types.
- `Sources/Engine/Layouts/LineData.swift`: line boxes and ordered inline refs.
- `Sources/Engine/Layouts/BlockLayoutPass.swift`: fill boxes instead of creating
  text nodes for line fragments.
- `Sources/Engine/Layouts/LineLayoutPass.swift`: place boxes, derive ascent,
  descent, height, and line width without text children.
- `Sources/Engine/Layouts/TextLayoutPass.swift`: keep non-line text nodes;
  stop the line-fragment path.
- `Sources/Engine/Display/PaintSceneBuilder.swift` / `PaintScene.swift` / `PaintEmit.swift`:
  paint line boxes as text ops, keeping inline order.
- `Sources/Engine/Layouts/LayoutPaintPass.swift` and `Sources/Engine/Core/Frame.swift`:
  hit-test returns a line + DOM target, not a text layout ID.
- `Sources/Engine/Accessibility/AccessibilityNode.swift`:
  text bounds come from line boxes.
- `Sources/Engine/Parsing/DOMRef.swift`: decide what `layoutID` means for a DOM
  text node after it has no layout node.

## Migration order

### Step 1: shadow boxes

Status: **applied** (2026-11-06), gated by `LayoutTree.collectsInlineBoxes`.

`InlineBox` and `LineData.content.boxes` exist. `syncInlineBoxes` fills them
from the existing text children after line placement. The collection is off by
default, so production does not pay the extra array build until paint starts
reading boxes. `InlineBoxTests.lineBoxesMatchTextChildren` enables the flag,
forces a relayout, and checks DOM, fragment, x, y, and width against every text
child.

Verification: 271 tests / 49 suites pass. Release `layout.document` for
450 -> 300 stays at **71.0 ms** median with boxes off; earlier with boxes always
on it was 76.3 ms, which is why the flag exists. Shadow screenshots matched the
baseline byte-for-byte.

### Step 2: paint from boxes

Status: **applied** (2026-11-06) for text-only lines.

`PaintLine` now carries `[PaintInlineText]` values, built from `LineData.boxes`.
The scene builder skips text children for those lines. Lines with embeds stay on
the node path until inline order is modelled; incremental stale boxes fall back
to text nodes.

Two correctness findings:

- Box y must use `textAbsoluteY`, including the line's inline y offset.
- The line paint cache is disabled while the migration collects boxes; a cached
  line could otherwise replay an old text position even when the box path was
  current. Re-enable it only with a box-aware cache key.

Verification: a simple page produces line nodes with non-empty `inlineText` and
no text child paint nodes. The large-page screenshot is byte-identical to the
baseline. `layout.document` is 74.1 ms median because boxes are now collected
alongside nodes; that overhead disappears when the text nodes do.

### Step 3: hit-test and accessibility from boxes

Status: **applied** (2026-11-06) for text-only lines.

`LayoutHit` now carries `(layout, dom)`. A line with current boxes is hit by
scanning its boxes in reverse and skipping text children; the result keeps the
line for scroll-focus geometry but the DOM text node for link/click/hover
semantics. `Frame`, `linkHref`, hover, and click use that DOM target.
Accessibility text bounds are computed from the parent line's boxes, with the
old node path as fallback.

Verification: `hitTestAndAccessibilityUseLineBoxes` checks a link hit, its DOM
target, `linkHref`, and accessibility bounds. Full suite: 273 tests / 49 suites.
Large-page screenshot is byte-identical; `layout.document` is 72.9 ms.

Line paint cache remains disabled while boxes are collected, and text nodes
still exist. Step 4 removes the fragment-node creation.

### Step 4: stop creating fragment nodes

Remove the fragment path from `flushText`/`commitLine`; line children become
only embeds. Keep the word-level path only until its callers are migrated.
Then remove `.text` nodes entirely if the audit shows no non-line producer.

Exit: 450 -> 300 target and no `layout.text` entries for line fragments.

## Risks

- `DOMRef.layoutID` currently gives text nodes identity; removing it changes
  invalidation and accessibility lookup.
- The two placement paths must converge; fixing only the plan path leaves a
  slow and inconsistent fallback.
- Paint order with inline embeds is easy to break.
- A line paint cache keyed by text child IDs must gain a box-generation key.
- Hit-testing must preserve link and iframe semantics.

## Recommendation

Use the shadow path first. Do not delete text nodes until paint, hit-test, and
accessibility all read boxes and screenshots match. The first measurable win is
expected at Step 4, not Step 1.

### Step 4 attempt: blocked (2026-11-06)

Value-only lines were implemented in the plan and word placement paths: no
text children, line-local boxes, and box placement. The width path produced
the expected shape, but incremental text edits and font changes broke:

- `refreshReusedLine` and line invalidation still discover changes through
  text children;
- boxes can be stale while a line's fields look clean;
- the line paint cache can replay old box geometry;
- accessibility/hit-test fallbacks masked the problem at first, then display
  signatures diverged from a full rebuild.

The fragment-node creation was reverted. The current stable state is Step 3:
text-only lines are painted, hit-tested, and measured from boxes, while text
nodes still exist for incremental invalidation and line maintenance. 273 tests
pass.

Prerequisite work started: `InlineBox` is Equatable; `syncInlineBoxes` updates
`paint.generation` only when box content changes; line paint cache is enabled
again only while `currentInlineBoxes` is valid. `boxRevisionChangesWithLineGeometry`
covers the revision change. Still missing before retrying Step 4: an explicit
inline-content revision, box rebuild through the placement path, and
incremental text/style tests over boxes. Do not remove text nodes yet.

### Prerequisites applied (2026-11-06)

- `LinePaint.boxRevision` stores the owning block's `inlineContent` revision.
- `currentInlineBoxes` rejects boxes whose revision is stale and falls back to
  text nodes; it never reads an unset/dirty `inlineContent` (embed lines).
- `syncInlineBoxes` updates the revision even when geometry is unchanged and
  bumps `paint.generation` only when box content changes.
- Vertical-only line moves now resync boxes, and the line cache is enabled again
  only when `currentInlineBoxes` is valid.
- Tests added: box revision tracks inline content, text edit refreshes boxes,
  font-size change refreshes metrics, vertical move refreshes box y, box
  revision changes with line geometry.

Full suite: **278 tests / 49 suites**. Large-page screenshot after 450 -> 300
is byte-identical; `layout.document` is 76.3 ms while boxes are still collected
alongside text nodes. Step 4 is ready to retry, but node removal remains the
point where the 60 ms target can move.

### Step 4: value-only width reflow (2026-11-06)

Status: **applied** for the width-reflow placement path.

The fix was the missing invariant from the retry: box geometry is now stored
**relative to the line**. A line move changes only the line's y; every box
follows without waiting for a box rewrite or cache invalidation. Paint,
hit-test, and accessibility add the line origin when they read a box.

The width/plan path now creates no text children. The old word path still
creates text nodes for initial layout and fallback cases, so this is not yet a
global removal.

Measurements, `www/bench/large.html` 450 -> 300, release headless:

| Run | `layout.document` | text nodes |
|---|---:|---:|
| 1 | 57.9 ms | 0 |
| 2 | 57.8 ms | 0 |
| 3 | 57.4 ms | 0 |

Median **57.8 ms**, target met. Screenshot is byte-identical to the baseline.
Full suite: **278 tests / 49 suites**.
