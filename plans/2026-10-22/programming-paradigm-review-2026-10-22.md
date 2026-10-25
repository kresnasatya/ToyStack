# Programming paradigm review

Date: 2026-10-22
Source data: [`browser-trace-findings-2026-10-22.md`](./browser-trace-findings-2026-10-22.md)
Scope: OOP vs protocol-oriented (POP) vs data-oriented (DOP) for the ToyStack engine.

## 1. Summary

The numbers in this section are the **pre-step-0 baseline** (2026-10-22).
Current A and D values are in
[`step-0-closeout-and-dop-readiness-2026-10-24.md`](./step-0-closeout-and-dop-readiness-2026-10-24.md)
§2 and §9.

The engine already mixes all three approaches. The trace does not show a
dispatch-style problem; it shows a **per-item data representation** problem.
The expensive paths are the ones where object graphs and existential arrays are
walked every frame:

- `[any LayoutObject]` with 994 block boxes.
- `[any DisplayItem]` with ~6,800 re-recorded items per animated frame.
- `[any CSSSelector]` tested per element, 87% of candidate tests universal.
- `[String: Animation]` per node, walked by a full-tree `treeToList` every rAF.
- `[String: String]` style per node, rebuilt per style pass.
- Tile dictionaries, layer dictionaries, and per-frame key hashing.

The right shift is **DOP for the per-frame hot data**, **POP at the platform
and parser boundaries**, and **OOP for identity/lifecycle objects**.

DOP alone does not fix the three largest algorithmic problems visible in the
pre-step-0 trace:

1. 165 of 168 layouts rebuild all 994 blocks.
2. Paint caches almost never hit (`cached.blocks = 30` of 990).
3. Animation frames miss 73.4% of tiles.

Those were invalidation and cache-key problems, and step 0 fixed them: A now
rebuilds 3 boxes and reuses 1 per steady frame, paint is 2.95 hits / 1.05 stores
per frame, and D misses only 0.99% of tiles. The remaining costs are constant
per-frame work: on D, paint is 5.08 ms, composite flatten 3.99 ms, and layout
2.20 ms over 2,027 visits. The representation changes below still target that
work; they no longer target misses.

## 2. The three approaches

| Approach | What it optimizes | Swift mechanism | Good for | Cost |
|---|---|---|---|---|
| **OOP** | Identity, lifecycle, encapsulation | `class`, inheritance, vtable dispatch | DOM nodes, tabs, loaders, parser, accessibility | Heap object per node, pointer chasing, ARC traffic, poor locality |
| **POP** | Variability and substitutability | `protocol`, extensions, generics, `any P` / `some P` | Platform seams (`Renderer`), loaders, test doubles | Witness-table dispatch, boxing of large struct payloads, `as?` recovery |
| **DOP** | Memory layout and batch throughput | Contiguous `[Struct]`, indices instead of references, tagged enums, SoA, generations, reused buffers | Layout boxes, display commands, style slots, animations, tiles | Manual indices/invariants, harder debugging, strings/references still indirect |

### Decision rules

- More than one implementation selected at runtime → protocol.
- One implementation over many elements → generic/concrete, not `any`.
- Per-frame collection of homogeneous records → flat array, index, or enum tag.
- Identity and lifecycle → class.

`any P` is not inherently slow, but it costs a witness-table call, prevents
inlining, and boxes struct payloads that exceed Swift's small inline buffer.
`[any LayoutObject]` is a contiguous array of pointers to separately allocated
objects; DOP's win is removing both the indirection and the per-object
allocation.

## 3. Current shape vs target shape

### 3.1 Display list and paint cache — DOP

**Current**

- `[any DisplayItem]` across `Frame.displayList`, `PaintCache`, `LinePaintCache`,
  and `CompositedLayer.displayItems`.
- Most commands (`DrawText`, `DrawRect`, `DrawImage`) exceed the existential
  inline buffer, so each is heap-boxed.
- `PaintTree` copies ranges into caches with
  `Array(displayList[ownStart...])`.
- `LinePaintCache.shifted` casts every item before translating it.

**Target**

- One contiguous command buffer, e.g. `[DisplayOp]` with a tagged enum or a
  fixed-size struct.
- Per-node cache as `Range<Int>` plus a generation stamp, not a copied
  `[any DisplayItem]`.
- Command coordinates relative to the owning box, so layout movement alone does
  not invalidate the range.
- Raster replay becomes a `switch` over the tag instead of an existential
  `execute` per item.

**Evidence (pre-step-0, 2026-10-22)**

| Trace fact | Value |
|---|---:|
| `BrowserTab.paint` total | 3.86 s |
| Steady `paint.own.items` | ~6,800 |
| `paint.cached.blocks` | 30 of 990 |

Current: scenario A has 2.95 hits / 1.05 stores per frame on 4 blocks. Scenario
D paints 5.08 ms/frame with 2,026 hits, 4.4 stores and 238.7 own items. The
30-of-990 figure is historical.

**Files**

- `Sources/Engine/Display/DisplayItem.swift:4`
- `Sources/Engine/Display/PaintCache.swift:4`
- `Sources/Engine/Display/PaintTree.swift:22`
- `Sources/Engine/Display/LinePaintCache.swift:53`
- `Sources/Engine/Layouts/LayoutObject.swift:36`

**Caveat:** step 0 fixed the key policy: `PaintKey` is width, height and epoch,
and cache coordinates are relative to the owner. The remaining cost is
replaying 2,026 cached blocks per frame, not missing them. `[any DisplayItem]`
still boxes every command and block stores still copy their range; those are
step 1's cost.

### 3.2 Layout boxes — DOP

**Current**

- `LayoutObject` is a class protocol.
- `BlockLayout`, `LineLayout`, and `TextLayout` each own
  `children: [any LayoutObject]`.
- Each block additionally owns dictionaries (`paintCache`, `fontByNode`,
  `itemsByNode`) and inline item arrays.
- Traversal is pointer chasing plus dynamic dispatch.

**Target**

- Flat `[LayoutBox]` store with index links:
  `nodeID`, `parent`, `firstChild`, `nextSibling`, `kind`, geometry fields.
- Separate passes over contiguous arrays for block measure, line breaking, and
  placement.
- Keep a thin facade if existing call sites need it, or move callers to explicit
  passes.

**Evidence (pre-step-0, 2026-10-22)**

| Trace fact | Value |
|---|---:|
| `BrowserTab.layout` total | 4.99 s |
| `layout.block.build` total | 2.77 s |
| `layout.inline.place` total | 1.56 s |
| Full 994-block rebuilds | 165 of 168 |

Current: scenario A rebuilds 3 boxes and reuses 1 per steady frame, with
`dirtyFlag` matching the animation marks and no `noReuse` after frame 2.
Scenario D rebuilds 6.4 boxes, reuses 2,024, and still visits 2,027 in
2.20 ms/frame. DOP now targets traversal and allocation, not invalidation.

**Files**

- `Sources/Engine/Layouts/LayoutObject.swift:4`
- `Sources/Engine/Layouts/BlockLayout.swift:15`
- `Sources/Engine/Layouts/BlockLayout.swift:56`
- `Sources/Engine/Layouts/BlockLayout.swift:88`
- `Sources/Engine/Layouts/LineLayout.swift:16`
- `Sources/Engine/Layouts/TextLayout.swift:10`

**Caveat:** DOP makes the remaining traversal cheaper but does not skip it.
Dirty tracking is correct after 0b: the 145-layouts-without-a-style-pass
observation is historical. The current cost is visiting 2,027 boxes to rebuild
6.4, so the flat store must reduce traversal and allocation, not invalidation.

### 3.3 Style storage and selector matching — DOP

**Current**

- `node.style: [String: String]` per node.
- `applyNodeStyle` allocates a fresh dictionary for each applied node and copies
  inherited defaults into it.
- Selector matching walks `[any CSSSelector]` recursively.
- `RuleIndex.candidateIndices` builds, sorts, and deduplicates a `[Int]` per
  element.

**Target**

- Intern property names to `PropertyID` at parse time.
- Store common properties in a fixed `ComputedStyle` struct; keep a small
  overflow dictionary for rare/custom properties.
- Compile selectors into a flat instruction array; match with a small stack
  machine over parent indices.
- Store the rule index as CSR-style `offsets + indices` arrays, not dictionaries
  of arrays.

**Evidence (pre-step-0, 2026-10-22)**

| Trace fact | Value |
|---|---:|
| Style total | 1.16 s |
| Style pass #1 | 81.1 ms |
| Universal candidate tests | 6,130 of 7,044 (87%) |
| Steady style passes | ~50 ms each |

Current: A has one style pass at load. D has one too, 22.1 ms over 6,049
nodes. Neither scenario produces per-frame style passes, so step 3 needs a
class-toggle or media-query workload before its ROI can be judged.

**Files**

- `Sources/Engine/Parsing/DOMNode.swift:8`
- `Sources/Engine/Parsing/DOMNode.swift:23`
- `Sources/Engine/Style/ApplyStyle.swift:44`
- `Sources/Engine/Style/Selectors/RuleIndex.swift:43`
- `Sources/Engine/Style/Selectors/SelectorSequence.swift:10`
- `Sources/Engine/Style/Selectors/DescendantSelector.swift:8`

**Note:** the pre-step-0 50 ms passes occurred inside animated frames and
contributed to the 56 ms median frame. Current A and D do not style per frame,
so style is not on the critical path until a workload exercises it. Step 3 must
be gated on that workload, not on the historical 50 ms figure.

### 3.4 Animation state — DOP

**Current**

- `node.animations: [String: Animation]` per node.
- `Animation` is a class protocol with one property and one method.
- Every rAF calls `treeToList(nodes)` to find animated nodes, allocating a full
  tree list.

**Target**

- Flat active-animation table:
  `{ nodeID, propertyID, start, duration, kind }`.
- One pass over the table per frame; write into compact style slots.
- Remove the full-tree scan and per-node animation dictionaries.

**Evidence (pre-step-0, 2026-10-22)**

| Trace fact | Value |
|---|---:|
| `BrowserTab.animFrame` total | 6.20 s |
| rAF ticks | 422 |
| rAF ticks doing no work | 247 |
| Animation frame mean | 63.4 ms |

Current: A has rAF 0.07 ms and animScan 0.10 ms over 8 nodes. D has animScan
1.08 ms over 2,027 nodes, with animFrame 3.36 ms. The full-tree scan is still
the animation constant cost.

**Files**

- `Sources/Engine/Parsing/DOMNode.swift:13`
- `Sources/Engine/Core/Frame.swift:867`
- `Sources/Engine/Animation/Animation.swift:3`

**Benefit beyond speed:** a flat table makes it explicit which animated
properties force layout and which can use the CA fast path already present in
`Browser.applyEffectFastPath`.

### 3.5 Raster tiles and planning — DOP

**Current**

- `TileStore` is `[TileKey: Entry]`; eviction scans all entries with `min(by:)`.
- `CompositedLayer.rasterIfNeeded` allocates `rowItems: [Int: [DisplayCommand]]`
  every call.
- `contentHash` runs an `as?` chain over every command.
- Tile keys are rebuilt per composite.

**Target**

- Dense tile grid per layer: `row * cols + col` into `[TileSlot]`, with a
  generation stamp instead of dictionary lookup.
- Precompute command hashes once when the display op is created.
- Reuse strip and row buffers across frames.
- Keep strips as flat slices with offsets for parallel dispatch.

**Evidence (pre-step-0, 2026-10-22)**

| Trace fact | Value |
|---|---:|
| `raster.plan` total | 6.06 s |
| Animation `raster.plan` mean | 15.35 ms |
| Animation tile misses | 10,124 vs 3,667 hits (73.4%) |
| `raster.worker` total | 5.68 s |

Current: A hits 86.4% of tiles (59.4% over the first 240 frames),
`missNew = 4`, `missEvicted = 0`, and no misses after frame 242. C scrolls at
87.97%. D hits 99.01%: 49 new tiles on frame 1,
then one stale tile per frame while the animated edge crosses a tile, none
after frame 240. On D, `raster.plan` is 6.33 ms (composite 5.83 ms, tile
bookkeeping 0.48 ms) and worker strips total 0.63 ms. Planning, not misses, is
the remaining cost.

**Files**

- `Sources/Engine/Raster/TileStore.swift:12`
- `Sources/Engine/Raster/TileStore.swift:58`
- `Sources/Engine/Raster/CompositedLayer.swift:111`
- `Sources/Engine/Raster/CompositedLayer.swift:155`
- `Sources/Engine/Display/DisplayCommand.swift:10`

**Caveat:** the 73.4% miss rate was an invalidation-policy problem and is now
historical. Current misses are stale content at real pixel changes (D: one tile
per frame while the animated edge crosses a tile). Dense tiles would target the
0.48 ms of tile bookkeeping, not misses; defer it until planning is material.

### 3.6 Layer presentation — dropped

**Current (pre-step-0)**

- `layersByPlacement: [LayerPlacementKey: CALayer]`.
- A `Set<LayerPlacementKey>` is built per presentation.
- 5,239 layer additions and 5,104 removals.

**Target — dropped**

- Stable integer placement IDs and array slots.
- Recycled `CALayer` pool. **Dropped**: the grace period never returns a key.
- Diff by index instead of hashing enum keys.

**Evidence (pre-step-0, 2026-10-22)**

| Trace fact | Value |
|---|---:|
| `view.apply` total | 6.18 s |
| `view.commit` total | 5.96 s |
| `updateSublayers` total | 152 ms |
| Layer additions / removals | 5,239 / 5,104 |
| Commit p95 / max | 30.8 / 53.6 ms |

Current: A adds 13 layers and removes 9 over 718 frames, with
`view.hidden = 90`, `view.unhidden = 0`, and 9 purges. The 10-frame grace is
shorter than the 120–240-frame key cycle, so no key returns.

**Files**

- `Sources/ToyStack/ContentPresenter.swift:12`
- `Sources/ToyStack/ContentPresenter.swift:98`

**Decision:** keep the 10-frame grace and drop the layer pool. A's 13 adds / 9
removals over 718 frames is the real tile-boundary floor; a pool would optimize
a path no measured workload exercises. Reopen only if a trace shows
`view.unhidden > 0` and rising adds/removes.

## 4. What should not change

- **Keep `Renderer` as a protocol.** It is a real platform seam with
  `CGRenderer` and `SwiftUIRenderer` implementations; it is called at the draw
  boundary, not per style match.
- **Keep DOM identity as OOP.** Parser, JS bridge, focus, and hit testing rely
  on reference identity. Add a stable `NodeID` and side tables for
  style/layout/animation instead of rewriting the DOM as SoA.
- **Keep `BrowserTab`, load pipeline, networking, and accessibility as OOP.**
  They are not per-frame hot paths, and reference semantics simplify them.
- **Do not use POP as a performance strategy.** Replacing a class hierarchy
  with `[any Protocol]` changes dispatch, not allocation or locality. For hot
  paths prefer a concrete enum or a generic that can specialize; reserve
  `any P` for boundaries.
- **Do not rely on cross-module specialization.** `Engine` is a separate Swift
  module; generic specialization across that boundary may require `@inlinable`.
  DOP avoids betting on it.
- **Do not move selector matching to generics alone.** Keep the protocol for
  parsing; compile selectors into a flat program for matching.

## 5. Suggested order

| Step | Change | Paradigm | Depends on |
|---|---|---|---|
| 0a | Trace metadata: categories, thread names, frame correlation ID, fixed span nesting and counter meanings | none | — |
| 0b | Layout invalidation: node-level dirty bounds, correct ancestor propagation, remove the full-tree fallback; fix `layout.skip` semantics | none | 0a |
| 0c | Paint cache keys: node identity + paint generation, coordinates relative to the owner; scope the epoch correctly | none | 0b |
| 0d | Tile invalidation: derive dirty tiles from 0b/0c instead of hashing the whole draw list; preserve the scroll hit rate | none | 0c |
| 0e | Placement stability: stable IDs, no `usesSublayers` toggling, layer reuse | none | 0d |
| 0f | Close-out: deny-list, tests, deterministic runner, A–D baselines, re-baselined D | none | 0e |
| 1 | Contiguous display list + range-based paint cache | DOP | 0c |
| 2 | Flat layout boxes, index links, dirty index sets | DOP | 0b |
| 3 | Interned style properties + compiled selector program / CSR rule index | DOP | — |
| 4 | Flat active-animation table, remove per-rAF `treeToList` | DOP | 0b, 3 |
| 5 | Dense tile grid, precomputed hashes, reused strip buffers | DOP | 0d, 1 |
| 6 | Layer pool — dropped (§3.6) | none | — |

Do not execute 1→5 in the fixed order. The measured order is step 1, step 2,
then a style workload, then step 4; step 5 is deferred and step 6 is dropped.
The gates are in the close-out doc §5 and the measurements in §9.

Step 0 is mandatory, and it must be scoped as **invalidation correctness**,
not only instrumentation. The close-out results and measured order are in
[`step-0-closeout-and-dop-readiness-2026-10-24.md`](./step-0-closeout-and-dop-readiness-2026-10-24.md)
§5 and §9.

Step 0 is done only when these are observable in the same trace:

| Check | Before (pre-step-0) | Current | Met |
|---|---|---|---|
| Layout work | 165 of 168 full 994-block rebuilds | A: 3 rebuilt / 1 reused; D: 6.4 rebuilt / 2,024 reused over 2,027 visits | Yes |
| Paint cache | `paint.cached.blocks` 30 of 990 | A: 2.95 hits / 1.05 stores per frame; D: 2,026 hits / 4.4 stores | Yes |
| Animation tile misses | 73.4% | A: 86.4% total, none after frame 242; C: 87.97% scroll; D: 0.99%, stale content only | Yes |
| Layer add/remove | 5,239 / 5,104 | 13 / 9, `unhidden = 0`, 9 purged | Yes |
| `view.commit` | 30–53 ms tail | GUI A: p50 0.095 ms, p95 1.542 ms; headless D: N/A | Partial |
| Span attribution | composite/scrollAt/load.page mis-nested | 0 pairing warnings; composite split into copy/flatten/layers | Yes |

Do not mark 0b–0e complete by inspection. Each one needs a before/after trace
comparison; otherwise the old limitation column remains true in practice.

## 6. Expected outcome

The original "Limitation" column mixed three different things:

1. **Ordering artifacts** — DOP was scheduled before the invalidation fix, so
   the limitation described a sequencing choice, not an inherent property.
2. **ROI facts** — style is a small share of total time.
3. **Subsystem problems** — tile misses and layer churn need their own fix.

Split by that distinction:

| Change | Primary cost attacked | Dissolved by step 0? | Why |
|---|---|---|---|
| Display list DOP | 6,800 existential items and cache copies | **Partially, 0c** | Invalidation is fixed. D still spends 5.08 ms painting 2,026 cached blocks and 3.99 ms flattening the list. Boxing and block-store copies remain. |
| Layout DOP | 994 class boxes and per-block allocations | **Partially, 0b** | Dirty tracking is fixed: D rebuilds 6.4 boxes but visits 2,027 in 2.20 ms. Traversal and allocation remain. |
| Style DOP | Per-node dictionaries and recursive selector tests | **No** | One 22.1 ms pass on D, one at load on A. There is no per-frame style workload yet; gate step 3 on one. |
| Animation DOP | Full-tree scan and per-node dictionaries | **Partially** | A: 0.10 ms; D: 1.08 ms over 2,027 nodes. The full-tree scan remains. |
| Raster DOP | Tile dictionaries, row arrays, per-item hash casts | **Partially** | D hits 99.01%; tile bookkeeping is 0.48 ms of a 6.33 ms plan. Planning is composite-bound, not miss-bound. |
| Presentation DOP | Placement bookkeeping (152 ms) | **Churn floor** | 13 adds / 9 removals, `unhidden = 0`; the layer pool is dropped. |

Revised residual table:

| Change | Residual after step 0 |
|---|---|
| Display list DOP | Per-item boxing and cached-range replay remain; paint is 5.08 ms/frame on D. |
| Layout DOP | D rebuilds 6.4 boxes but visits 2,027; DOP reduces traversal and allocation. |
| Style DOP | One 22 ms pass on D; per-frame style needs a workload before it can be ranked. |
| Animation DOP | Full-tree scan is 1.08 ms/frame on D; layout-affecting properties still relayout. |
| Raster DOP | Stale tiles at real pixel changes remain; planning is composite-bound. |
| Presentation DOP | Churn floor; the pool is dropped, not deferred. |

Two limitations cannot be engineered away by step 0:

- **Style ROI:** style costs 22 ms on D at load. Step 3 needs a class-toggle or
  media workload before its per-frame cost is known; the 50 ms figure is
  historical.
- **Semantic relayout:** changing `width` or `height` must reflow the affected
  subtree. Step 0 narrowed "affected" from the whole document to the dirty
  region. It cannot make a layout-affecting animation layout-free; that requires
  animating compositor properties (`transform`, `opacity`) instead.

The order is therefore not "step 0 then DOP". It is "0a–0f, then step 1 and
step 2 on the remaining constant cost; style waits for a workload; tile
planning and the layer pool are not justified".

The engine should end up as a hybrid: OOP for identity and lifecycle, POP for
platform seams and parser extensibility, DOP for everything traversed or
recorded once per frame.
