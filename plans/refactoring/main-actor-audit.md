# MainActor Audit: What Is Load-Bearing, What Is Inherited

Companion to [oop-findings.md](./oop-findings.md) item 6, Step 4 ("Shrink the main actor").
This file records what is still isolated, why, and what the value refactors changed.
It is kept current after [main-actor-shrink.md](./main-actor-shrink.md) stages 0–4, D, and C.

## Verdict

There are **136 `@MainActor` mentions**: 70 in `Sources` and 66 in `Tests` (193 at the start of
this work). In `Sources` that is 51 declaration annotations (24 types, 25 functions, 2 other
members) plus 19 flow annotations (12 `Task { @MainActor in }` hops and 7 function types).

Layout and paint are now **value passes**: layout runs on `LayoutInputs` with a value
`LayoutTree`; paint runs on a frozen `PaintScene`; style matching runs on a `StyleSnapshot`.
What remains is 24 root annotations, 20 boundary adapters that read or write the DOM, and 11
read-only helpers that inherit isolation from a root.

**57 annotations were removed net** (193 → 136) by changing data ownership, not by deleting annotations.

---

## 1. What `@MainActor` is

A global actor whose executor is the main thread's run loop. It is a **declaration-level
concurrency contract**, not a comment:

- Every member of the annotated type (or the annotated function) may only run on the main actor.
- Calling it from another actor requires `await` (a suspension + hop).
- Calling it synchronously from code already on the main actor costs nothing but a debug check.
- In this repo the contract is **not compile-enforced for data**: the Engine target still uses
  `.swiftLanguageMode(.v5)` in [Package.swift](../../Package.swift). The test target uses the
  tools-version default (Swift 6). A `-swift-version 6` build of Engine currently fails with
  25 errors (section 6).

### Example in this repo

`Sources/Engine/Parsing/DOMTree.swift:8` is a `final class` arena of plain Swift storage —
`nodes`, `side`, `links`, and a `StyleFields` per node. No lock, no queue. Annotating it says
"one thread owns this", and the compiler spreads that requirement to every reader:

```swift
@MainActor
final class DOMTree {
    private(set) var nodes: [DOMNode?]
    var side: DOMSideTables
}

@MainActor
struct DOMRef {          // Parsing/DOMRef.swift:9
    let id: NodeID
    let dom: DOMTree     // the reason this struct is isolated
}
```

The same rule, applied to a value, disappears. `TagSelector` used to be `@MainActor` only because
it dereferenced that arena; it now matches a snapshot:

```swift
struct TagSelector: CSSSelector {
    let tag: String
    func matches(_ snapshot: StyleSnapshot, _ index: Int) -> Bool {
        snapshot.node(index).content.tag == tag   // no actor, no DOM
    }
}
```

---

## 2. Cost of an unnecessary `@MainActor`

| Effect | Evidence in this repo |
|---|---|
| **It is viral.** A call to an isolated member is itself isolated; the annotation propagates outward until it hits a boundary. | `LayoutTree.domRef` is main-only, and everything that needed a `DOMRef` (paint scene builder, accessibility, focus, traversal) inherited it. The reverse also held: each eliminated input removed a cluster of annotations. |
| **It pins the slowest work to the UI thread.** | Style application still walks `DOMTree` (`ApplyStyle` 3, selectors, `StyleInvalidation`). Layout and paint no longer do: they read `LayoutInputs`/`PaintScene`. `oop-findings.md:974-978` describes this cost. |
| **It adds hops and reordering.** Every cross-boundary call is an unstructured `Task`. | 12 sites: `Core/Browser.swift`, `Core/Frame.swift` (2), `Platform/JSRuntime.swift` (3), `Raster/RasterScheduler.swift`, `ToyStack/ToyStack.swift` (5). Each can interleave differently than written. |
| **It serializes the test suite.** | All 30 test files remain `@MainActor`; layout/paint/style *values* could be tested without it, but the helpers still reach `Frame`. |
| **It creates `unsafe` escape hatches where the boundary is real.** | `BrowserTab.swift:17,20,24,28` (`nonisolated(unsafe)` statics), `BrowserFont.swift:73` (`nonisolated(unsafe) var fontCache`), `Diagnostic/Profiler.swift:58`, `Style/Selectors/HasSelector.swift:3`; plus `@unchecked Sendable` on `JSRuntime`, `WebURL`, `RasterScheduler`, `TileStore`, `MeasureTime`, `AccessibilityThread`, `RasterInstallWait`, `RasterWorkerPool`, `FontMeasureCache`, `BrowserFont`. |
| **It buys no enforced safety today.** | Still `.swiftLanguageMode(.v5)`: violations are warnings, and a stripped Engine compiles (probe recorded in §7). |

### Is it in `oop-findings.md`?

Yes, as an **ownership symptom**, not as an annotation audit:

- `oop-findings.md:278` — implicit sharing: "`Frame` and `Element` shared mutable graph, `@MainActor`, `@unchecked Sendable`".
- `oop-findings.md:914` — "Because everything shares it, everything stays on the main actor".
- `oop-findings.md:947` — "A mutation can originate from several places, which is why so much of the engine must be main-actor isolated".
- `oop-findings.md:970-980` — item 6, Step 4 "Shrink the main actor".
- `oop-findings.md:987` — "The main actor covers the UI boundary, not the entire engine".

[oop-refactor-order.md](./oop-refactor-order.md:41) placed this inside item 6; the value
refactors in [main-actor-shrink.md](./main-actor-shrink.md) are the continuation.

---

## 3. Current count

| Target | start | now | Files with annotations |
|---|---|---|---|
| `Sources/Engine` | 110 | **55** | 31 |
| `Sources/ToyStack` | 10 | **9** | 4 |
| `Sources/ToyStackHeadless` | 6 | **6** | 2 |
| `Tests` | 67 | **66** | 30 |
| **Total** | **193** | **136** | **67** |

Shape of the 70 in `Sources`:

| Shape | Count |
|---|---|
| Type declaration (`class`/`struct`/`enum`/`protocol`) | 24 |
| Function / method | 25 |
| Other member (`init`, protocol requirement) | 2 |
| `Task { @MainActor in }` hop | 12 |
| Function-type attribute (`@MainActor (…) -> …`) | 7 |

Hot spots: `Platform/CanvasBridge.swift` 6, `Core/FocusNavigation.swift` 6,
`Platform/JSRuntime.swift` 5, `Style/ApplyStyle.swift` 3, `Core/TreeTraversal.swift` 3,
`Core/Frame.swift` 3, `Layouts/LayoutTree.swift` 2, `Core/Browser.swift` 2,
`Style/Selectors/SelectorMatching.swift` 2, `Raster/RasterScheduler.swift` 2.

---

## 4. What still needs the main actor

### Roots — own unsynchronized state or a main-only API (24)

| Root | Location | Why |
|---|---|---|
| `DOMTree` | `Engine/Parsing/DOMTree.swift:8` | Unsynchronized arena: `nodes`, `side`, `links`, per-node `StyleFields`. |
| `HTMLParser`, `HTMLSyntaxHighlighter` | `Engine/Parsing/HTMLParser.swift:5`, `HTMLSyntaxHighlighter.swift:1` | Build and mutate `DOMTree`. |
| `StyleFields` | `Engine/Style/StyleFields.swift:3` | Style store inside `DOMTree`; writes notify layout through inputs now, but the store itself is shared class state. |
| `StyleCascade` | `Engine/Style/StyleCascade.swift:17` | Carries `oldStyles` / `appliedNodes` across one style pass. |
| `Frame` | `Engine/Core/Frame.swift:13` | Owns `FrameState` (DOM, layout box, display), the animation tick, and pass sequencing. |
| `BrowserTab`, `Browser` | `Engine/Core/BrowserTab.swift:15`, `Engine/Core/Browser.swift:5` | Frame graph; `Browser` is an `ObservableObject` with `@Published` state. |
| `JSRuntime`, `CanvasBridge` | `Engine/Platform/JSRuntime.swift`, `Engine/Platform/CanvasBridge.swift:8-16` | `JSContext` is not thread-safe; callbacks re-enter the DOM. |
| `RasterScheduler.Job.then` | `Engine/Raster/RasterScheduler.swift:9` | Installs raster output into main-owned display state; worker side is `Sendable`. |

`LayoutTree` is **no longer a root**. It is a value owned by `LayoutBox` (frame owns the box, DOM
holds a weak reference). Only two members stay main: `domRef(_:)` for paint/dump and the
`init(dom:)` convenience that snapshots inputs.

### Boundary adapters — read/write the DOM or layout on main (20)

`DOMBase.init` (1), `DOMRef`/`ElementRef`/`TextRef` (3), `StyleInvalidation` (1),
`StyleSnapshotBuilder` (1), `ApplyStyle` (3), `SelectorMatching` (2), `InlineStyle` (1),
`ForcedColor` (1), `StyleTransitions` (1), `LayoutInvalidation` (1), `LayoutTree.domRef` +
`init(dom:)` (2), `LayoutInputsBuilder` (1), `PaintSceneBuilder` (1), `LayoutDependencyDump` (1).

These exist because their input is still a class: the DOM arena, or a `DOMRef` into it. They are
the next removable group, and they disappear only by giving the DOM pass a value model.

### Inherited read-only helpers (11)

`FocusNavigation` (6), `TreeTraversal` (3), `AccessibilityNode` + `FrameAccessibilityNode` (2).
They hold `DOMRef`/layout ids and read both trees.

---

## 5. What was removed, and why it stayed removed

Milestones, measured after each step:

| Step | Sources | Tests | Total |
|---|---|---|---|
| start | 126 | 67 | 193 |
| stage 0 — value shells (`BlockStyle`, `StyleFields` class-level, `DOMBase.init`, `BrowserView`) | 115 | 67 | 182 |
| stage 3a — paint helpers take `ComputedStyle`/geometry | 110 | 67 | 177 |
| stage 3b — paint runs on `PaintScene` | 104 | 67 | 171 |
| stage 4 — selectors/cascade matching on `StyleSnapshot` | 87 | 67 | 154 |
| D — layout reads `LayoutInputs` | 81 | 65 | 146 |
| C — `LayoutTree` becomes a value; layout leaves the actor | **70** | **66** | **136** |

Notes that matter for future edits:

- **Value first, actor second.** Flipping `@MainActor` off a class graph fails to compile at the
  first DOM read. The successful order was: freeze the inputs into values, then drop isolation.
- **Computed storage copies on write.** `LayoutTree.nodes` as a computed `get/set` over storage
  made every field write copy the whole node array (COW), hanging large pages. It is stored now;
  see `main-actor-shrink.md`, stage C.
- **DOM effects leave the pass.** Canvas resize and iframe viewport are `LayoutEffect` values that
  `Frame` applies after layout; the pass itself never writes the DOM.

---

## 6. What is left, and why

The remaining Engine annotations are three groups:

1. **The DOM is still a class** (24 roots + 20 adapters). Style application, accessibility, focus
   navigation, and DOM-side invalidation cannot leave the main actor until `DOMTree` becomes a
   value (or is borrowed), because they mutate it. This is the same rewrite that made layout and
   paint value passes, applied to the document.
2. **The app/JS boundary** (`Sources/ToyStack` 9, `Sources/ToyStackHeadless` 6, `JSRuntime` 5,
   `CanvasBridge` 6). This boundary is correct: AppKit, SwiftUI, and `JSContext` require main.
3. **Read-only helpers** (11) that inherit from `DOMRef`.

Flipping the **Engine** target to `.swiftLanguageMode(.v6)` today produces 25 errors, all at
real boundaries:

| File | Errors | Cause |
|---|---|---|
| `Platform/JSRuntime.swift` | 17 | `sending 'self'` into JS callback closures |
| `Core/Frame.swift` | 6 | task closures capturing the frame for image/script loads |
| `Scheduling/TaskRunner.swift` | 2 | `schedule` closure not `@Sendable` |

None of them are layout or paint any more. A mode flip still needs those closures redesigned with
value payloads, and the `nonisolated(unsafe)` sites justified or replaced.

---

## 7. Verification recipe

```sh
swift build --build-tests            # no warnings expected
swift build -c release               # no warnings expected
swift test                           # 209 tests, 33 suites
```

Value-pass checks used throughout this refactor:

- Render `www/ch16/granular-style.html`, `www/bench/large.html` (`--scroll-at`), `ch13` width
  animation, `ch15` dynamic iframe, `ch15` canvas, `ch14` inputs, `ch16` contenteditable, and
  compare screenshots pixel-for-pixel against the previous commit.
- Compare profiler counters from `--trace` (`layout.visited`, `layout.skipped`,
  `layout.field.set`, `paint.cache.hit.*`, `style.*`) instead of trusting visual sameness.

For counterfactual checks (what is load-bearing), copy the repo outside the working tree, strip
the annotation you are testing, and build there. Never test annotations by deleting them in the
repo: under Swift 5 mode the compiler accepts a stripped Engine, so a green build does not prove
the isolation was unused. Today, flipping Engine to `.swiftLanguageMode(.v6)` in a copy yields
25 errors; the file list above is the current boundary inventory.
