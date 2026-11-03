# MainActor Audit: What Is Load-Bearing, What Is Inherited

Companion to [oop-findings.md](./oop-findings.md) item 6, Step 4 ("Shrink the main actor").
That step was not part of items 1–5; this file is the audit it needs before any code moves.

## Verdict

There are **182 `@MainActor` mentions**: 115 in `Sources` and 67 in `Tests` (193 before the
applied cleanup in section 5). Only ~8 places are **roots** — objects that own mutable state with
no lock. The other ~99 declarations are isolated only because they touch a root. Deleting
annotations does not shrink the main actor; removing the shared mutable graph does.

Four removals are applied and verified: 14 annotations deleted, 3 added, no behavior change
(net −11). Everything else waits for the value-state rewrite described in item 6.

---

## 1. What `@MainActor` is

A global actor whose executor is the main thread's run loop. It is a **declaration-level
concurrency contract**, not a comment:

- Every member of the annotated type (or the annotated function) may only run on the main actor.
- Calling it from another actor requires `await` (a suspension + hop).
- Calling it synchronously from code already on the main actor costs nothing but a debug check.
- In this repo the contract is **not compile-enforced** for data: all three targets use
  `.swiftLanguageMode(.v5)` in [Package.swift](../../Package.swift). Swift 6 tokens produce
  warnings here, not errors.

### Example in this repo

[`Sources/Engine/Parsing/DOMTree.swift:8`](../../Sources/Engine/Parsing/DOMTree.swift) is a
`final class` arena of plain Swift storage — `nodes`, `side`, `links`, and a `StyleFields` per
node. No lock, no queue. Annotating it says "one thread owns this", and the compiler then spreads
that requirement to every reader:

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

So [`TagSelector.matches`](../../Sources/Engine/Style/Selectors/TagSelector.swift:8) is
`@MainActor` for one reason: it dereferences `node.dom`. It has no state of its own.

```swift
@MainActor
func matches(_ node: DOMRef) -> Bool {
    node.element?.tag == tag     // reads the arena through DOMRef
}
```

The alternative shape, once the data is safe to pass, is:

```swift
nonisolated struct TagSelector {   // no shared state, pure value
    let tag: String
    func matches(_ snapshot: ElementSnapshot) -> Bool { snapshot.tag == tag }
}
```

That requires `ElementSnapshot` to be usable off-main, which is exactly the rewrite item 6 defers.

---

## 2. Cost of an unnecessary `@MainActor`

| Effect | Evidence in this repo |
|---|---|
| **It is viral.** A call to an isolated member is itself isolated; the annotation propagates outward until it hits a boundary. | Removing `@MainActor` from `StyleFields.notifyLayout` (`Style/StyleFields.swift:91`) produces 3 new "main actor-isolated … in a synchronous nonisolated context" errors at its callers (`apply`, `set`, `mutate`). Removing all 107 declarations required editing 57 files. |
| **It pins the slowest work to the UI thread.** Style, layout, paint, and composite all run on main, so a relayout blocks event handling and raster presentation. | Layout and paint still walk `DOMTree`/`LayoutTree`, which are the roots below. `oop-findings.md:974-978` describes this exact cost. |
| **It adds hops and reordering.** Every cross-boundary call is an unstructured `Task`. | 12 sites: `Core/Browser.swift:163`, `Core/Frame.swift:506,557`, `Platform/JSRuntime.swift:442,461,514`, `Raster/RasterScheduler.swift:56`, `ToyStack/ToyStack.swift:86,180,207,225,252`. Each one can interleave with other work in a different order than written. |
| **It serializes the test suite.** Test trees carry the same isolation. | 30 of 30 test files with `@MainActor` suites; e.g. `Tests/ToyStackTests/HoverTests.swift:6-7` combines `@Suite(.serialized)` with `@MainActor`. |
| **It creates `unsafe` escape hatches where the boundary is real.** | `Core/BrowserTab.swift:17,20,24,28` (`nonisolated(unsafe)` statics), `Platform/BrowserFont.swift:73` (`nonisolated(unsafe) var fontCache`), `Style/Selectors/HasSelector.swift:3`, `Diagnostic/Profiler.swift:58`. Each is an unchecked claim that main-actor isolation was supposed to make unnecessary. |
| **It buys no enforced safety today.** | A probe copy with every `@MainActor` removed from `Sources/Engine` compiles after two mechanical fixes (a protocol requirement and the raster callback). Under Swift 5 mode the annotation is a convention, not a check. |

### Is it in `oop-findings.md`?

Yes, as an **ownership symptom**, not as an annotation audit:

- `oop-findings.md:278` — implicit sharing: "`Frame` and `Element` shared mutable graph, `@MainActor`, `@unchecked Sendable`".
- `oop-findings.md:914` — "Because everything shares it, everything stays on the main actor".
- `oop-findings.md:947` — "A mutation can originate from several places, which is why so much of the engine must be main-actor isolated".
- `oop-findings.md:970-980` — item 6, Step 4 "Shrink the main actor": keep the coordinator and AppKit/JS callbacks on main; make layout and paint `nonisolated` over value state; the `BrowserFont` cache became thread-safe already (`FontMeasureCache` locks).
- `oop-findings.md:987` — "The main actor covers the UI boundary, not the entire engine".

[oop-refactor-order.md](./oop-refactor-order.md:41) places this inside item 6, and item 6 was
delivered without the layout/paint part. So the count below is the un-migrated remainder, not new debt.

---

## 3. Current count

| Target | before | now | Files |
|---|---|---|---|
| `Sources/Engine` | 110 | 100 | 58 |
| `Sources/ToyStack` | 10 | 9 | 4 |
| `Sources/ToyStackHeadless` | 6 | 6 | 2 |
| `Tests` | 67 | 67 | 30 |
| **Total** | **193** | **182** | **94** |

Shape of the 115 in `Sources`:

| Shape | Count |
|---|---|
| Type declaration (`class`/`struct`/`enum`/`protocol`) | 30 |
| Function / method | 62 |
| Other member (`init`, protocol requirement, stored closure) | 4 |
| `Task { @MainActor in }` hop | 12 |
| Function-type attribute (`@MainActor (…) -> …`) | 7 |

Hot spots: `Style/StyleFields.swift` 1, `Display/PaintTree.swift` 8, `Platform/CanvasBridge.swift` 6,
`Layouts/EmbedLayoutPass.swift` 6, `Core/FocusNavigation.swift` 6, `ToyStack/ToyStack.swift` 5.

---

## 4. Which parts MUST be on the main actor

These own mutable state with no lock, or talk to a main-thread-only API. The annotation is the
correct (and only) current confinement mechanism.

| Root | Location | Why |
|---|---|---|
| `DOMTree` | `Engine/Parsing/DOMTree.swift:8` | Unsynchronized arena: `nodes`, `side`, `links`, per-node `StyleFields`. |
| `LayoutTree` | `Engine/Layouts/LayoutTree.swift:10` | Unsynchronized arena: `nodes`, `primaryByNode`, `dependencies`. |
| `StyleCascade` | `Engine/Style/StyleCascade.swift:17` | Carries `oldStyles` / `appliedNodes` across one style pass. |
| `Frame` | `Engine/Core/Frame.swift:13` | Owns both arenas (`FrameState.document`, `.layout`), the animation tick, and the paint/present sequencing. |
| `BrowserTab`, `Browser` | `Engine/Core/BrowserTab.swift:15`, `Engine/Core/Browser.swift:5` | Own the frame graph; `Browser` is an `ObservableObject` with `@Published` state. |
| `JSRuntime`, `CanvasBridge` | `Engine/Platform/JSRuntime.swift`, `Engine/Platform/CanvasBridge.swift:8-16` | `JSContext` is not thread-safe; every callback re-enters the DOM. |
| `RasterScheduler.Job.then` | `Engine/Raster/RasterScheduler.swift:9` | Installs the raster result into main-owned display state; the worker side is already `Sendable`. |
| AppKit / SwiftUI shells | `Sources/ToyStack/*`, `Sources/ToyStackHeadless/*` | `NSApplication`, `NSView`, SwiftUI views, and the headless run loop. |

Everything downstream of these inherits isolation. That is 99 of the 107 declarations, for example
`Display/PaintTree.swift:3`, all of `Style/Selectors/*`, `Core/FocusNavigation.swift:1-51`,
`Core/TreeTraversal.swift:5-28`, `Layouts/LayoutInputTable.swift:8`,
`Core/DependencyIndex.swift:7`, `Layouts/InlineTextRun.swift:5`, `Layouts/InlineItem.swift:1`.

### Which parts do NOT need it on their own

| Group | Members | Only reason for isolation |
|---|---|---|
| Ref wrappers | `DOMRef`, `ElementRef`, `TextRef`, `LayoutRef`, `InlineItem`, `InlineTextRun`, `InlinePlacement`, `InlinePlacementContext`, `AccessibilityNode`, `FrameAccessibilityNode` | They store a reference to an arena class. |
| Read-only helpers | `PaintTree` (8), selectors (12), `ApplyStyle` (3), `ForcedColor` (2), `TextDirectionResolver`, `InlineStyle`, `BrokenImage` (2), `ImageLoading.init`, `BrowserFont.fontInputs`/`fontForElement` (2), `DisplayOp.fromStyle`/`fromBorderStyle` (2), `PaintEffectStyle`, `DrawCursor`, `FocusRing`, `effectiveZIndex`, `EmbedLayoutPass` image/canvas helpers (6), `inPaintOrder` | They read style/DOM state. |
| Invalidation | `LayoutInvalidation`, `StyleInvalidation`, `LayoutInputTable`, `DependencyIndex`, `StyleTransitions`, `LayoutDependencyDump` | They walk an arena. `DependencyIndex.endLayout(from:)` is the only member that needs it. |
| Pass values | `BlockStyle`, `BlockBoxStyle`, `BlockStyleFlags` | Only `BlockStyle.init(node:)` reads the DOM. |

---

## 5. Removable now (applied)

Four changes, net −11 annotations, zero behavior change. Applied in the working tree and verified:
`swift build --build-tests` clean, `swift test` 208 tests in 33 suites pass, and
`ToyStackHeadless` still renders `www/ch16/granular-style.html` to a screenshot.

### 5.1 Pass values carry no state of their own

`Sources/Engine/Layouts/BlockStyle.swift`

```diff
-@MainActor
 struct BlockStyle {
     let display: LayoutStyle.Display
     let position: LayoutStyle.Position
     let box: BlockBoxStyle
     let flags: BlockStyleFlags
 
+    @MainActor
     init(node: DOMRef) {
```

```diff
-@MainActor
 struct BlockBoxStyle {
```

```diff
-@MainActor
 struct BlockStyleFlags {
```

`BlockBoxStyle` and `BlockStyleFlags` hold only `CGFloat`/`Bool`/`EdgeInsets`. Isolation belongs
on the initializer that reads `DOMRef`, not on the type.

### 5.2 `StyleFields`: 10 annotations for one real dependency

`Sources/Engine/Style/StyleFields.swift` is declared `nonisolated` only because
`DOMBase.init()` (a nonisolated struct initializer) constructs it. That forces each member to
re-add isolation individually:

```diff
-nonisolated final class StyleFields {
+@MainActor
+final class StyleFields {
     private(set) var owner: NodeID?
     private var storage: StyleStorage = StyleStorage()
     private(set) var revision: UInt64 = 0
     private var invalidation: StyleInvalidationState = StyleInvalidationState()
     weak var layoutTree: LayoutTree?
```

The 10 member annotations that used to sit above `unknownValue` (`:18`), `markAll` (`:23`),
`hasDirtyDescendant` (`:29`), `markDirtyDescendants` (`:34`), `clearDirtyDescendants` (`:39`),
`apply` (`:44`), `set` (`:65`), `mutate` (`:73`), `isDirty` (`:84`), and `notifyLayout` (`:90`)
were deleted with that change; the line numbers are the pre-edit ones.

`Sources/Engine/Parsing/DOMBase.swift`

```diff
 extension DOMBase {
+    @MainActor
     init() {
```

`DOMBase()` is only constructed from `DOMTree` (`DOMTree.swift:23,109,116`) and from
`DOMDataTests`, both already main-isolated. One annotation states the rule instead of ten
restating it.

### 5.3 SwiftUI already supplies it

`Sources/ToyStack/ToyStack.swift`

```diff
-@MainActor
 public struct BrowserView: View {
```

`View` conformance is already main-actor isolated by SwiftUI. Verified by building the `ToyStack`
target with the annotation removed.

---

## 6. Why nothing else is worth touching yet

Removing the remaining ~99 annotations would either fail to compile (they call into an arena) or
compile and delete a safety claim without removing the sharing. The actual fix is item 6's
`nonisolated` layout/paint over value state, and it needs:

1. `DOMRef` / `ElementRef` / `LayoutRef` to stop carrying a non-`Sendable` class reference, or to
   become per-phase copies (`LayoutSnapshot`) — the tree owns the storage, passes get read-only values.
2. `StyleFields.layoutTree` (the only back-edge from style to layout) to become a callback the
   layout tree installs, so style writes stop needing `@MainActor` transitively.
3. `RasterInput` is already a real `Sendable` snapshot (`Raster/RasterInput.swift:3`), so raster
   is the model to copy, not the exception.

Until then, the boundary rule is: annotate the roots in section 4, let the compiler propagate,
and never annotate a type that only holds `Sendable` values. One declaration per fact, in this
file as in any other.

## 7. Verification recipe

```sh
swift build --build-tests
swift test --filter 'BlockLayoutTests|DOMDataTests|StyleFieldsTests'
```

For counterfactual checks (what is load-bearing), copy the repo outside the working tree, strip the
annotation you are testing, and build there. Never test annotations by deleting them in the repo:
the compiler accepts a stripped Engine, so a green build does not prove the isolation was unused.
