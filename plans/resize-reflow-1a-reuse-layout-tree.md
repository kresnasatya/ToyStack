# Resize reflow 1a — keep the layout tree across a reflow

Status: **implemented and measured** (working tree, 2026-10-17). Applied in
`LayoutObject.swift`, `DocumentLayout.swift`, `BlockLayout.swift` and `Frame.swift`;
still needs a commit. See *1a measured* at the bottom for what it actually bought.

This is the first commit out of
[`resize-reflow-remaining-work.md`](./resize-reflow-remaining-work.md). It is the
step the plan calls "1a", scoped so it lands alone, changes no behaviour, and can be
measured on its own before anything else moves.

Line numbers are from the current working tree.

---

## Why this one first

Of the remaining items, 1a is the only one that is both:

- **Prerequisite-shaped** — 1b (dirty subtrees) and 1c (line re-break) are both
  "reuse some of this tree"; 2b (paint only what changed) is the same idea on the
  paint side. Getting a surviving tree in place is the thing they all stand on.
- **Independently landable and safe** — it needs no dirty bit, no new invalidation
  plumbing, no geometry logic. If it is wrong the tree is visibly wrong, which is
  loud, not subtle.

Items 3 and 4 (the `border-radius` parser and the `inPaintOrder` guard) are ten
minutes and can go in any time, but they are a few milliseconds. This is the 71ms.

---

## What the code does today

A reflow allocates a brand-new tree from the DOM root
(`Frame.swift:741-744`):

```swift
let doc: DocumentLayout = DocumentLayout(node: nodes)
doc.layout(availableWidth: frameWidth, zoom: zoom)
document = doc
rebuildScrollTargets(doc)
```

Everything below is thrown away:

- `DocumentLayout.layout()` builds a fresh root block and **appends** it
  (`DocumentLayout.swift:25-26`).
- `BlockLayout.layout()` rebuilds its children from `node.children` and
  **appends** each one (`BlockLayout.swift:89-133` for block children,
  `:134-141` + `newLine()` at `:303-308` for lines).
- `fontByNode` is a property of the `BlockLayout` that wraps an inline run
  (`BlockLayout.swift:24`, read at `:241`). A new tree means an empty cache, so
  every reflow redoes ~3247 font lookups (`profiler.count("text.fontNodes")`).

So re-running `layout()` on the old tree is **not** enough on its own — the two
`append` sites would duplicate the tree instead of reusing it. "Keep the tree" means
"make `layout()` consume the children it already has."

---

## Where the reuse is sound, and where it is not

This is the whole design argument, so it is worth stating plainly.

The **block layer** is decided by the DOM shape, not the width. At
`BlockLayout.swift:89-133` the children are chosen from `display`, tag names
(`h6`, `hiddenElements`), and mount/run-in bookkeeping. None of that changes when the
viewport width changes. So on a width-only reflow the children already sitting in
`children` are still exactly the right children, in the same order — take them by
index.

The **line layer** is width-dependent: `newLine()` (`:303`), `addWord()` (`:237`),
`addTextNode()` (`:214`), and the image/iframe/canvas used-width reads all depend on
`width` and `cursorX`. That layer must be rebuilt every time. 1a does not touch it —
only 1c does.

The win therefore comes from **reusing the blocks that wrap text**, because those are
the objects that own `fontByNode`. Reusing only the root `DocumentLayout` would save
nothing measurable.

### When is the structure stable?

`Frame` already knows, and it never needs a new flag from the outside:

| Path | Entry point | Structure can change? |
|---|---|---|
| style / class / DOM mutation / stylesheet | `setNeedsRender()` → `needsStyle = true` (`Frame.swift:1245-1250`) | **yes** |
| media query flipped | `setNeedsViewportResize()` → `setNeedsRender()` (`:1259-1261`) | **yes** |
| pure viewport resize, media unchanged | `setNeedsViewportResize()` → `setNeedsLayout()` (`:1262-1264`) | no |
| CSS `width`/`height` keyframe | `Frame.swift:794-796`, `:817` | no |
| lazy image decoded | `Frame.swift:439` | no |
| iframe frame resized | `IframeLayout.swift:47` | no |

The rule is: **reuse only when no style pass ran this render and the DOM root is the
same object.** That is exactly the set of rows with "no" above. Any element add/remove
or style change goes through `needsStyle`, so the guard can never be bypassed by a
mutation.

---

## Design decision (pick one)

**Option A — a flag on the layout call, set by `Frame`. (Recommended.)**

`Frame` decides reuse from facts it already holds (`needsStyle` and whether `nodes`
is the same object) and passes it down. Cost: one parameter, one protocol
requirement. It makes the invariant explicit and it is the same discriminator 1b
needs, so it is not throwaway work.

**Option B — always try reuse, fall back when the child's `node` does not match.**

No flag. Self-correcting, but it only catches mismatches one level at a time, hides
real bugs behind a silent rebuild, and still pays the walk in the mismatch case.
Rejected — the flag is one line and removes the guesswork.

Two smaller decisions fall out of A and are made here: rebuild the line layer
unconditionally (1c handles that properly), and keep the `DocumentLayout` **object**
stable even when its children are rebuilt, so anything holding `node.layoutObject`
or `document` stays valid (the plan's watch-out at `resize-reflow-remaining-work.md`).

---

## Files that change

| File | Why |
|---|---|
| `Sources/Engine/Layouts/LayoutObject.swift` | declare and default the new `layout(reusesChildren:)` |
| `Sources/Engine/Layouts/DocumentLayout.swift` | reuse the root block instead of appending a new one |
| `Sources/Engine/Layouts/BlockLayout.swift` | reuse block children by order; always rebuild lines |
| `Sources/Engine/Core/Frame.swift` | compute `reuse` and pass it in |

---

## Diffs

### `Sources/Engine/Layouts/LayoutObject.swift`

`layout(reusesChildren:)` must be a **protocol requirement**, not just an extension
method. A method that only exists in a protocol extension is dispatched statically,
so the `BlockLayout` override would never run and reuse would silently do nothing.

```diff
     func layout()
+    func layout(reusesChildren: Bool)
     func paint() -> [any DisplayItem]
     func shouldPaint() -> Bool
     func paintEffects(_ items: [any DisplayItem]) -> [any DisplayItem]
 
 }
 
 extension LayoutObject {
+    /// The default for objects that build no reusable children: just lay out.
+    /// Only the containers that assemble children from the DOM override this.
+    func layout(reusesChildren: Bool) {
+        layout()
+    }
+
     func paintEffects(_ items: [any DisplayItem]) -> [any DisplayItem] {
```

### `Sources/Engine/Layouts/DocumentLayout.swift`

Replace the unconditional `append` with "reuse the existing root block when told to".
Note `children = [child]` rather than `children.append(child)` — that single change is
what makes a second `layout()` idempotent.

```diff
     func layout() {
         layout(availableWidth: WIDTH)
     }
 
+    func layout(reusesChildren: Bool) {
+        layout(availableWidth: WIDTH, zoom: zoom, reusesChildren: reusesChildren)
+    }
+
-    func layout(availableWidth: CGFloat = WIDTH, zoom: CGFloat = 1.0) {
+    func layout(
+        availableWidth: CGFloat = WIDTH, zoom: CGFloat = 1.0, reusesChildren: Bool = false
+    ) {
         self.zoom = zoom
-        let child: BlockLayout = BlockLayout(node: node, parent: self, previous: nil)
-        children.append(child)
+        // The root block knows about itself, so it is the one thing worth keeping
+        // when the tree is reused; on a structural change it is built fresh.
+        let child: BlockLayout
+        if reusesChildren, let existing = children.first as? BlockLayout, existing.node === node {
+            child = existing
+        } else {
+            child = BlockLayout(node: node, parent: self, previous: nil)
+        }
+        children = [child]
 
         width = availableWidth - 2 * scaled(HSTEP)
         x = scaled(HSTEP)
         y = scaled(VSTEP)
 
-        child.layout()
+        child.layout(reusesChildren: reusesChildren)
         height = child.height
     }
```

### `Sources/Engine/Layouts/BlockLayout.swift`

Four changes: forward `reusesChildren` from the no-argument `layout()`, take block
children from a small pool instead of building them, clear the line layer before
rebuilding it, and hand the flag down the recursion.

A new helper at the bottom of the file. It lives here because it exists only to serve
`BlockLayout` (per the code-architecture note about `// MARK:`-grouped helpers):

```diff
@@
+// MARK: - ChildReuse
+
+/// Hands back the block children a previous layout already built, in order.
+/// A block's children are decided by the DOM shape, not the available width, so on
+/// a width-only reflow the old children are still the right ones. Reusing them keeps
+/// each block's `fontByNode` cache alive.
+private struct ChildReuse {
+    private let prior: [any LayoutObject]
+    private var index: Int = 0
+
+    init(prior: [any LayoutObject], enabled: Bool) {
+        self.prior = enabled ? prior : []
+    }
+
+    /// Everything that was on offer was used.
+    var finished: Bool { index == prior.count }
+
+    mutating func take(_ make: () -> BlockLayout) -> BlockLayout {
+        guard index < prior.count, let existing = prior[index] as? BlockLayout else {
+            return make()
+        }
+        index += 1
+        return existing
+    }
+}
```

Then the function head:

```diff
-    func layout() {
+    func layout() {
+        layout(reusesChildren: false)
+    }
+
+    func layout(reusesChildren: Bool) {
         profiler.measure("layout.block.build") {
```

The block branch. The three construction sites become pool lookups; the pool is
seeded from the children already present and `children` is cleared before refilling:

```diff
             let mode: String = layoutMode()
             if mode == "block" {
+                var pool: ChildReuse = ChildReuse(prior: children, enabled: reusesChildren)
+                children = []
                 var prev: (any LayoutObject)? = nil
                 var inlineRun: [any DOMNode] = []
                 var pendingRunIn: Element? = nil
 
                 for child in node.children {
@@
                         if let el = child as? Element, el.tag == "h6" {
                             if !inlineRun.isEmpty {
-                                let anon: BlockLayout = BlockLayout(nodes: inlineRun, parent: self, previous: prev)
+                                let anon: BlockLayout = pool.take {
+                                    BlockLayout(nodes: inlineRun, parent: self, previous: prev)
+                                }
                                 children.append(anon)
                                 prev = anon
                                 inlineRun = []
                             }
                             pendingRunIn = el
                         } else {
                             if !inlineRun.isEmpty {
-                                let anon: BlockLayout = BlockLayout(nodes: inlineRun, parent: self, previous: prev)
+                                let anon: BlockLayout = pool.take {
+                                    BlockLayout(nodes: inlineRun, parent: self, previous: prev)
+                                }
                                 children.append(anon)
                                 prev = anon
                                 inlineRun = []
                             }
                             if let runIn = pendingRunIn {
-                                let next: BlockLayout = BlockLayout(
-                                    nodes: [runIn, child], parent: self, previous: prev)
+                                let next: BlockLayout = pool.take {
+                                    BlockLayout(nodes: [runIn, child], parent: self, previous: prev)
+                                }
                                 children.append(next)
                                 prev = next
                                 pendingRunIn = nil
                             } else {
-                                let next: BlockLayout = BlockLayout(node: child, parent: self, previous: prev)
+                                let next: BlockLayout = pool.take {
+                                    BlockLayout(node: child, parent: self, previous: prev)
+                                }
                                 children.append(next)
                                 if child.style["position"] != "absolute" { prev = next }
                             }
                         }
@@
                 if !inlineRun.isEmpty {
-                    let anon: BlockLayout = BlockLayout(nodes: inlineRun, parent: self, previous: prev)
+                    let anon: BlockLayout = pool.take {
+                        BlockLayout(nodes: inlineRun, parent: self, previous: prev)
+                    }
                     children.append(anon)
                 }
                 if let runIn = pendingRunIn {
-                    let next: BlockLayout = BlockLayout(node: runIn, parent: self, previous: prev)
+                    let next: BlockLayout = pool.take {
+                        BlockLayout(node: runIn, parent: self, previous: prev)
+                    }
                     children.append(next)
                 }
+                assert(
+                    !reusesChildren || pool.finished,
+                    "block structure changed without a style pass; reuse is unsafe")
             } else {
+                // Line breaks depend on the available width, so the line layer is
+                // rebuilt every layout. The blocks around it are what survives.
+                children = []
                 newLine()
```

And the recursion:

```diff
-        for child in children { child.layout() }
+        for child in children { child.layout(reusesChildren: reusesChildren) }
```

### `Sources/Engine/Core/Frame.swift`

Capture whether a style pass ran, then decide reuse from that plus the DOM root
identity. `document` is kept as the same object across reflows; only a different root
node or a style pass rebuilds its children.

```diff
     func render() {
+        let styled: Bool = needsStyle
         if needsStyle {
             browser?.measure.start("BrowserTab.style")
```

```diff
         if needsLayout {
             browser?.measure.start("BrowserTab.layout")
             profiler.reset()
             defer { profiler.emitProfile(into: browser?.measure, named: "profile.layout") }
             defer { browser?.measure.stop("BrowserTab.layout") }
-            let doc: DocumentLayout = DocumentLayout(node: nodes)
-            doc.layout(availableWidth: frameWidth, zoom: zoom)
+            // Only a pure width change may reuse the tree: no style pass ran, and
+            // the DOM root is unchanged. Every structural change goes through
+            // `needsStyle`, so this cannot miss one.
+            let reuse: Bool = !styled && document?.node === nodes
+            let doc: DocumentLayout = document ?? DocumentLayout(node: nodes)
+            doc.layout(availableWidth: frameWidth, zoom: zoom, reusesChildren: reuse)
             document = doc
             rebuildScrollTargets(doc)
```

---

## Order of work

1. `LayoutObject.swift`, `DocumentLayout.swift`, `BlockLayout.swift`, `Frame.swift`
   in that order. The project builds after each file.
2. Run the app, resize a page, confirm nothing is duplicated or jumping.
3. Only then measure (below). If the numbers move, stop; do not start 1b.

---

## How to check it worked

> Answer is in *1a measured* below: reuse happened on 70 of 77 layouts, the font cache
> survived, and the tile cache stayed stable.

Two things must be true, and they measure different halves of the change.

**Reuse is happening and the font cache is surviving.** In the trace, on a resize:

- `text.fontNodes` should fall from ~3247 to ~0 on the second and later ticks.
- `text.words` should be unchanged (line breaking still runs — that is expected).
- `BrowserTab.layout` should drop; watch the `text.fontNodes` count, not the total.

**Nothing regressed in the raster cache.** Per the caution in the parent plan, the
`tiles` counter must still report `{hits: N, misses: 0}` on an unchanged frame. If
`hits` collapses to 0, something made the tree unstable between frames.

Per-tick cost, `browser.trace`:

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

Use `www/ch11/resize-check.html` (or `visual-effects.html`) and drag the width.

---

## If it looks wrong

The whole change is behind one boolean. To disable reuse without reverting anything,
force `let reuse: Bool = false` at the `Frame` site and the tree is rebuilt exactly as
before. If you see **duplicated content stacked vertically**, the `append`-to-`children`
sites were not cleared (check the `children = []` in the block branch). If you see
**stale geometry** after a class change, the `styled` guard is not catching the path.

---

## Explicitly out of scope

- **1b / 1c** — dirty subtrees and line-level reuse. They need a dirty bit and a layout
  root; write that plan once 1a's numbers are known.
- **2a** — flattening the paint list. Independent and mechanical; a natural next commit.
- **Items 3, 4, 5, 6, 7** from the parent plan. Untouched here.

---

## 1a measured

One drag session, debug build, profiling on, `browser.trace` written to the repo root
(2.3 MB). 994 blocks, 9740 words — **a different page from the parent plan's
`visual-effects.html` numbers, so treat these as their own baseline, not as a delta
against that table.**

77 layouts, of which **70 reused the tree and 7 did not**.

### The reuse is real

| Counter | Cold (rebuilt) | Warm (reused) |
|---|---|---|
| `text.fontNodes.count` | 3247 | **0** |
| `text.font.us` | ~1150–1500 µs | **6–12 µs** |
| `text.measure.us` | 9878 µs | **0** |

The `fontByNode` cache survives, which was the whole point. The
`assert(!reusesChildren || pool.finished)` never fired, so reuse-by-index never
disagreed with the DOM — the invariant held on every reused tick.

### The 7 cold layouts are correct, not a bug

Every cold layout is preceded by a style pass, by a consistent ~250 ms:

| Style pass | Cold layout |
|---|---|
| −0.28 s | 0.00 s (first load, `document == nil`) |
| 16.43 s | 16.69 s |
| 21.91 s | 22.16 s |
| 25.45 s | 25.69 s |
| 27.09 s | 27.34 s |
| 30.12 s | 30.37 s |
| 31.29 s | 31.53 s |

Those are `@media` breakpoint crossings — item 5, 176 ms each, matching the parent
plan exactly. A style pass must invalidate the tree, so `reuse` correctly goes false.
The guard is behaving as specified.

### But the tick barely moved

| | warm (reused) | cold (rebuilt) |
|---|---|---|
| `BrowserTab.layout` | avg **66.6 ms**, p50 64.4 | avg 73.4 ms, p50 66.6 |
| `layout.block.build` | avg **33.1 ms**, p50 31.7 | avg 42.2 ms |

So 1a bought **~7 ms per tick**. Warm and cold layout differ by only ~7 ms, because
the font work was ~10 ms, not the bulk. Breakdown of a warm tick (t + 13.56 s, `reuse`
true):

```
layout.block.build    30.9 ms   (994 blocks, ~31 µs each)  ← untouched by 1a
layout.line.place      9.8 ms
layout.text            9.6 ms
text.font / measure    ~0 ms    ← solved by 1a
(remainder)          ~15 ms     rebuildScrollTargets / treeToList / instrumentation
BrowserTab.paint      52.7 ms   ← untouched
```

### Two corrections to the assumptions in this plan

1. **`font.measure` was already globally cached.** A warm tick reports
   `text.measureCalls.count ≈ 40000` with `text.measureMisses.count = 0`. Destroying
   the tree never cost measurement. What 1a removed is the `getFont` *lookup*
   (~10.5 ms), not a 30 ms font pipeline.
2. **`layout.block.build` is 33 ms *with* reuse** (~42 ms without). Allocation of the
   child objects was never the cost. The per-node cost is geometry plus
   style-dictionary reads (`position`, `left`, `top`, `width`, `overflow`, margins)
   and `layoutMode()` (`BlockLayout.swift:174-185`) walking `node.children` with a
   style read per child, on every block, every reflow.

### Health checks both pass

- **Tile cache is fine.** 52 unchanged-frame events report `hits > 0, misses == 0`.
  Misses show up only on the 32 events where the content genuinely changed. The hash
  is still stable.
- `raster.composite` non-zero avg **34.3 ms**, max 36.7 — matches the 34–36 ms band.
- 35 dropped frames out of 985 present events.

### What this changes about the next commit

- **2a (flatten the paint list) is the right next move.** Paint is 52.7 ms, untouched,
  mechanical, and independent of any dirty model. It is the other half of the tick.
- **`layout.block.build` (33 ms) is the next layout target**, and 1a has made it
  easier rather than harder: stable object identity across reflows means a dirty bit
  is a smaller step than it was before. 1b attacks this 33 ms directly; 1c attacks the
  ~20 ms of `line.place + text`.
- Keep 1a despite the small direct win. It is the enabling change for 1b, and it
  stopped a per-reflow `getFont` burst from masking the cost that now needs attention.

### One open question

Nine warm ticks report **identical work** (994 blocks, 9740 words, 0 font misses) but
`layout.block.build` 46–47 ms instead of 31 ms, with line/text also ~45 % slower.
Same counts, no extra work — this looks like CPU contention from the raster workers
rather than a code path. Per the parent plan's advice, sample `BlockLayout.layout()`
before chasing it; do not design anything around it on the strength of one trace.

## Related

- `resize-reflow-remaining-work.md` — the full remaining list and where this sits.
- `resize-reflow-and-horizontal-overflow.md` — diagnosis and Rounds 1–3.
- `profiling.md` — trace format, `MeasureTime` vs `Profiler`, `--no-profile`.
