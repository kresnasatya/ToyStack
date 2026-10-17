# Resize reflow — what is left

Status: **open work list**. Companion to
[`resize-reflow-and-horizontal-overflow.md`](./resize-reflow-and-horizontal-overflow.md),
which has the diagnosis and Rounds 1–3. This file is only the remainder, ordered by
measured cost, for a later pass.

Applied so far (working tree, 2026-10-17):

| Step | Change | State |
|---|---|---|
| 1 | tick timer in `.common` mode, so a live resize keeps reflowing | working tree |
| 2 | `resize` is a viewport (layout) invalidation, not a full render; no-op resizes skipped | working tree |
| 4 | images honour `max-width`; new `LengthPx.swift` | **committed** `51dd367` |
| 6 | transform regex compiled once | working tree |
| 7 | accessibility tree not built while a11y is off | working tree |
| 8 | display-item hash without per-item string allocation | working tree |

Line numbers below are from that working tree. Symbols are named too, so they survive
a refactor.

## Where it stands

Both columns are real app runs, debug build, `visual-effects.html`:

| Span | Before | Now | Δ |
|---|---|---|---|
| `BrowserTab.paint` | 122.7ms | 53.3ms | −57% |
| `BrowserTab.layout` | 75.8ms | 71.1ms | unchanged |
| `BrowserTab.a11y` | 37.2ms | not built | −37ms per tick |
| `raster.composite` | 49–53ms | 34–36ms | −31% |
| gap between resize ticks | 240–272ms | 132–160ms | ~7 reflows/s |

Main thread during a render is now: **layout ~49%, paint ~34%, load/parse ~14%**.

So the scheduling half is done — a resize reflows while you drag. What is left is
throughput: one tick is still ~124ms of main-thread work (layout 71 + paint 53).

**Target:** a resize tick at ~15–20ms, i.e. 50–60fps while dragging. That needs items
1 and 2. Items 3 and 4 are a few milliseconds each and already have diffs.

---

## 1. Layout rebuilds the whole tree on every reflow — ~71ms/tick

`Frame.swift:741` `let doc: DocumentLayout = DocumentLayout(node: nodes)` →
`doc.layout(availableWidth: frameWidth, zoom: zoom)` at `:742` →
`rebuildScrollTargets(doc)` at `:744`.

Everything is thrown away and rebuilt: every `LayoutObject`, every `LineLayout`, every
`TextLayout`. `BlockLayout.fontByNode` is an instance property, so a new tree also
means an empty font cache — `text.fontNodes.count` is ~3247 per layout, i.e. ~3247
font lookups per reflow that a surviving tree would already have.

Inside the same span, `rebuildScrollTargets` walks the whole new tree a second time to
rebuild the iframe and scroll-block targets.

This is the biggest item and the one that needs a design decision, so it is staged:

**1a — keep the tree.** Stop allocating a `DocumentLayout` per reflow; reuse the
existing one and re-run `layout()` on it. That means `layout()` has to be
idempotent: `DocumentLayout.layout()` currently does `children.append(child)`
unconditionally (`DocumentLayout.swift:25-26`), and `BlockLayout.layout()` does the
same, so a second call would duplicate children. Reuse the existing children when the
node set is unchanged. Expect the font-cache and allocation wins without any dirty
logic. Measure before going further.

**1b — dirty subtrees.** A block whose used width is known (a `px` width, an image's
intrinsic size) cannot be affected by a viewport width change, so its subtree needs no
layout at all. Mark the root dirty and walk down until you hit a subtree whose
available width is unchanged, then stop.

**1c — line-level reuse.** Only the *text wrapping* depends on the width. Blink keeps
the fragment tree and re-breaks lines from the first affected one; the boxes above are
untouched. This is the version that turns a reflow into a few milliseconds.

Decision to make first: how far to go. 1a is mechanical and safe; 1b/1c need dirty bits
on `LayoutObject` and a notion of "layout root". Worth its own plan before writing code.

Watch out: `LayoutObject.node.layoutObject = self` is assigned in the layout-object
initialisers, so anything holding `node.layoutObject` (a11y bounds, `scrollTo`,
`loadLazyImages`) must still see a live tree. 1a keeps that true by construction.

## 2. The paint list is rebuilt by copying, and every layout repaints all of it — ~53ms/tick

`PaintTree.swift:5` allocates a fresh `items` array per object, `:8` and `:31` append
into it, `:21-23` and `:37-39` recurse, and `:44` does
`displayList.append(contentsOf: items)` into the parent's array. A ~12k-item list is
therefore copied once per level of depth. `:7` calls `paint()` and `:42` calls
`paintEffects()` on every object.

`Frame.swift:748` sets `needsPaint = true` on every layout, so a width change always
repaints the whole document even though only the wrapping moved.

After the Round 3 fixes the leaf samples here are diffuse — `malloc`, `swift_retain`,
`swift_release`, metadata lookups — which is what thousands of small allocations look
like. Two stages:

**2a — build one flat list.** Thread a single `inout` accumulator through the
recursion instead of returning arrays up the tree, and `reserveCapacity` against the
previous frame's item count. Mechanical; no behaviour change.

**2b — paint only what changed.** The raster side is already incremental (per-tile
cache keyed by content), so re-rasterizing is not the cost — *building* the display
list is. Either keep the display list per subtree and rebuild only dirty subtrees, or
distinguish "geometry changed" from "text moved" in `setNeedsPaint` so a reflow that
only re-wraps does not touch subtrees whose items are identical.

Do 2a first and re-measure; 2b is the same design decision as 1b/1c and probably
belongs in the same plan.

Also inside paint, and cheap: `Frame.paint()` calls `maxRectBottom(list)` over the
whole list (`Frame.swift:764`), and `paint()`/`paintEffects()` build new structs for
every node on every paint.

## 3. `border-radius` still does a Foundation string replace per node — ~5µs × 12k ≈ 5ms/paint

Four sites, one of them on the paint path for **every** node and *before* the guard
that returns early for nodes with no radius:

- `BrowserVisualEffect.swift:37` — hot; 37 of 64 samples inside
  `paintBrowserVisualEffects` in the last profile
- `BlockLayout.swift:434`
- `IframeLayout.swift:55`
- `InputLayout.swift:67`

`(node.style["border-radius"] ?? "0px").replacingOccurrences(of: "px", with: "")`
bridges to `NSString` and builds a mutable string to turn `"0px"` into `"0"`.

Measured (12k nodes per paint, the value mix a page actually has):

```
                    debug (-Onone)     release (-O)
replacingOccurrences: 0.78 us/call   0.58 us/call
hasSuffix/dropLast  : 0.33 us/call   0.05 us/call  → ~5ms per paint
```

Add a parser next to `outlineWidth`, which already parses a length the cheap way
(`CSSValueParser.swift:50`):

```diff
+    /// A plain `Npx` length, for properties that only ever take one
+    /// (`border-radius`). 0 for anything else, including the multi-value form
+    /// `4px 8px`, which this engine does not support yet.
+    static func px(_ css: String?) -> CGFloat {
+        guard let css, css.hasSuffix("px"), let value = Double(css.dropLast(2)) else { return 0 }
+        return CGFloat(value)
+    }
```

then at each of the four sites:

```diff
-    let radiusStr: String = (node.style["border-radius"] ?? "0px").replacingOccurrences(of: "px", with: "")
-    let borderRadius: CGFloat = CGFloat(Double(radiusStr) ?? 0)
+    let borderRadius: CGFloat = CSSValueParser.px(node.style["border-radius"])
```

(use `element.style` at the `InputLayout` site). Results are identical for
`nil`/`0px`/`4px`/`8px`; `50%` and `4px 8px` give 0 both ways, which is why the
limitation is worth the comment.

## 4. `inPaintOrder` sorts children that are already in order

`PaintTree.swift:54-62`. It runs for **every** object with children and does
`.enumerated().sorted { … }.map { … }` — three array allocations per node, with
`effectiveZIndex` (`:48-51`) reading `position` and `z-index` from the style dictionary
per comparison. `effectiveZIndex` returns 0 for everything static, so on any page
without `position`/`z-index` — every page in `www/` — the sort is a no-op.

```diff
 @MainActor
 func inPaintOrder(_ children: [any LayoutObject]) -> [any LayoutObject] {
+    // Nothing is positioned: the sort would be a no-op, and it costs three array
+    // copies per node. This is the common case on every page in `www/`.
+    guard children.contains(where: { ($0.node.style["position"] ?? "static") != "static" })
+    else { return children }
     return children.enumerated()
         .sorted { a, b in
```

## 5. Crossing a `@media` breakpoint still costs a full style pass — ~176ms, only on a crossing

`Frame.swift:656-734`. When the verdict check from step 2 flips, `render()` re-sorts
all rules, rebuilds the `RuleIndex`, re-runs the `:has()` precompute, snapshots every
node's style, re-cascades the whole document, and diffs transitions — then lays out and
paints everything. It fired twice in a 27s drag session, each one a visible hitch when
crossing 800px.

Real engines invalidate only the rules behind the query that flipped. Direction: keep
the rules sorted and the `RuleIndex` between renders (they only change when a
stylesheet is added), and on a verdict flip re-cascade only nodes matched by rules in
the changed query. Correctness is fine today; only the cost is wrong.

## 6. Presentation waits for the raster round trip — latency, not throughput

`Browser.swift:485-533`. `dispatchPresent()` is called from the raster `then` callback,
so the window shows a new layout one round trip (~35ms `raster.composite` plus worker
time) after the main thread is done. While a job is in flight the next is refused
(`Browser.swift:251-253`) and superseded frames are dropped
(`ContentPresenter.swift:25-53`).

Real browsers always have the previous frame on screen and swap when the new one lands.
Direction: present the last committed frame immediately on `commit`, then present again
when the raster finishes.

Not a cost, but it is what "the picture lags behind the mouse" is. Do it after 1 and 2,
when the tick is fast enough for the round trip to be the visible term.

## 7. The other half of the original report — horizontal overflow (no reflow cost)

Untouched, and the user-visible half of "some parts overflow in horizontal":

- `overflow: auto` does not create a scroll container (`ApplyStyle.swift:80-84` only
  promotes `overflow-y/x: scroll`).
- The one block scroll container is vertical-only: `BlockLayout` tracks `contentHeight`
  and no `contentWidth` (`BlockLayout.swift:26-27`, `:169`), `Frame.scrollAt` compares
  heights only (`Frame.swift:980-1012`, maths at `:1006`), `BlockLayout.paintScrollbar`
  draws one bar (`:494-503`).
- There is no window-level horizontal scrollbar (`Browser.swift:64-80`), and the content
  layer clips (`BrowserContentView.swift:16`).

`www/ch11/resize-check.html` still shows the `<pre>` line running off the right edge
with no way to reach it. The image half of that page is fixed by `51dd367`.

---

## If you only do two things

**Items 1 and 2.** They are the same design decision — a dirty model shared by layout
and paint — and together they take a tick from ~124ms to ~15–20ms, which is 50–60fps
while dragging. Write that plan before touching code; 1a alone is safe and measurable
as a first commit.

Items 3 and 4 are ten minutes for a few milliseconds each and can go in any time.
Item 5 matters only when a drag crosses a breakpoint. Item 6 is polish.

## How to measure any of this

Per-tick cost, from `browser.trace` (written to the process working directory):

```bash
python3 -c "
import json, collections
d = json.load(open('browser.trace'))
evs = [e for e in d['traceEvents'] if e.get('ts') is not None]
stack, rows = collections.defaultdict(list), []
for e in sorted(evs, key=lambda e: e['ts']):
    nm, ph = e['name'], e['ph']
    if ph == 'B': stack[nm].append(e['ts'])
    elif ph == 'E' and stack[nm]: rows.append(((e['ts']-stack[nm].pop())/1000, nm))
agg = collections.defaultdict(lambda: [0.0, 0])
for du, nm in rows: agg[nm][0] += du; agg[nm][1] += 1
for k, (t, n) in sorted(agg.items(), key=lambda x: -x[1][0])[:12]:
    print('%8.1fms  x%-4d %-28s %6.1f ms avg' % (t, n, k, t/n))
"
```

Two cautions learned the hard way:

- `composite_raster_and_draw` is wall-clock and includes waiting, and the
  `raster.composite` aggregate includes no-op composites. Compare the **non-zero**
  values, not the averages.
- The `tiles` counter is the correctness check for anything that touches
  `contentHash` or the tile cache: unchanged frames must still report
  `{hits: N, misses: 0}`. If `hits` goes to 0, the hash stopped being stable.

Where a span does not exist yet (`paintTree` is one span today), sample instead —
build a long page, run the headless screenshot in the background, and attach:

```bash
python3 -c "
import random
w='lorem ipsum dolor sit amet consectetur adipiscing elit sed do'.split()
random.seed(1)
print('<html><body>' + '\n'.join('<p>'+' '.join(random.choice(w) for _ in range(40))+'</p>' for _ in range(3000)) + '</body></html>')
" > /tmp/big.html
.build/debug/ToyStackHeadless "file:///tmp/big.html" --screenshot /tmp/x.png --width 800 --height 600 --scale 1 &
sample $(pgrep -f 'ToyStackHeadless file://' | head -1) 8 -file /tmp/sample.txt
```

then read `Frame.paint()` / `Frame.runAnimationFrame()` in the call graph: the
top-level branch shares give the layout-vs-paint split, and `ToyStackHeadless`
symbols in *Sort by top of stack* give the leaves.

## Related

- `resize-reflow-and-horizontal-overflow.md` — diagnosis, Rounds 1–3, the applied
  diffs, and the design notes for the horizontal-overflow work.
- `profiling.md` — trace format, `MeasureTime` vs `Profiler`, `--no-profile`.
