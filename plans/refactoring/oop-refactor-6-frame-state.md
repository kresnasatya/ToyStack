# Frame state refactor: item 6

Implementation plan for **item 6 (frame state)** from [oop-findings.md](./oop-findings.md). Ordering rationale lives in [oop-refactor-order.md](./oop-refactor-order.md).

**Yes, this is last.** Items 1 through 5 are committed. The fixed sequence is:

```
1 → 2 → 5 → 3 → 4 → 6
```

This file is the plan only. No engine code is edited here.

## Scope

**In scope**

- Replace `Frame`'s flat stored-property bag (`Frame.swift:17-138`) with four grouped value states: document, layout, display, runtime.
- Make `Frame` a coordinator: identity links plus one `FrameState` value. All cross-group resets go through methods, not `didSet` observers.
- Move per-tab presentation state out of `Browser` (`Browser.swift:30-39`) and into the tab that owns it.
- Replace stored `Frame` object references with stable `FrameID` values and one registry owner (`BrowserTab`).
- Make the raster input a real frozen snapshot: `FrameSnapshot`, `DisplaySnapshot`, value `RasterLayer`s, `BrowserFont` with a locked measure cache.
- Remove `@unchecked Sendable` from snapshot payloads (`RasterInput`, `RasterScene`, `RasterOutput`, `RasterPlan`, `RasterComposition`, `TileStrip`, `TileBatch`).
- Move raster planning/compositing code out of the main-actor `Browser` type.
- Keep behavior identical: paint output, scroll, iframe lifetime, focus/hover, animations, accessibility, raster tiles, and presentation.

**Out of scope**

- Converting `DOMTree`, `LayoutTree`, or `StyleFields` into `Sendable` values. `FrameState` groups them; it does not replace them.
- Moving layout and paint off the main actor. They read the main-actor arenas and `StyleFields` classes; the snapshot boundary is the part this item can make nonisolated.
- New CSS, layout, JS, or rendering behavior.
- The `Renderer`, `JSRuntime`, AppKit, network, and font-registry seams.
- Changing `StyleFields` invalidation semantics. Item 4 established the table; this plan only moves where `Frame` keeps the scheduling flags.

## Baseline

Verified before writing this plan:

```sh
git status --short          # clean
swift build                 # Build complete!
swift test                  # 205 tests in 30 suites passed
```

Current shape, with anchors:

| Concern | Current location |
|---|---|
| Frame stored state | `Sources/Engine/Core/Frame.swift:17-138` |
| DOM replacement side effects | `Frame.swift:23-39` |
| Style rule replacement side effects | `Frame.swift:75-80` |
| Frame paint | `Frame.swift:943-970` |
| Frame animation | `Frame.swift:975-1066` |
| Frame commit | `Frame.swift:1067-1083` |
| Browser per-tab frame map | `Sources/Engine/Core/Browser.swift:30-39` |
| Browser commit and writeback | `Browser.swift:209-248` |
| Raster scheduling | `Browser.swift:282-597` |
| Raster helpers on `Browser` | `Browser.swift:600-892` |
| Tab frame registry | `Sources/Engine/Core/BrowserTab.swift:34-36` |
| Raster input is unchecked | `Sources/Engine/Raster/RasterInput.swift:3` |
| Raster scene holds class layers | `Sources/Engine/Raster/RasterScene.swift:1-5` |
| Layer is a class | `Sources/Engine/Raster/CompositedLayer.swift:3-31` |
| Display list embeds layer objects | `Sources/Engine/Display/DisplayOp.swift:11` |
| Font cache is an unlocked class | `Sources/Engine/Platform/BrowserFont.swift:6-9` |
| iframe side table stores `Frame` | `Sources/Engine/Parsing/DOMSideTables.swift:34-39` |

Capture visual baselines before A1:

```sh
swift run ToyStackHeadless "file://$PWD/www/ch11/index.html" \
  --trace /tmp/before-frame-paint.trace --frame-limit 5 --screenshot /tmp/before-frame-paint.png
swift run ToyStackHeadless "file://$PWD/www/ch15/index.html" \
  --trace /tmp/before-frame-embed.trace --frame-limit 5 --screenshot /tmp/before-frame-embed.png
swift run ToyStackHeadless "file://$PWD/www/ch16/exercise-16-2-protecting-layout-phases.html" \
  --trace /tmp/before-frame-incremental.trace --frame-limit 5 --screenshot /tmp/before-frame-incremental.png
swift run ToyStackHeadless "file://$PWD/www/ch13/exercise-13-6.html" \
  --trace /tmp/before-frame-anim.trace --frame-limit 30 --screenshot /tmp/before-frame-anim.png
```

Keep the four screenshots as the stop signal for A, B, C, and D.

## End state

### 1. Grouped frame state

`Frame` has two stored properties:

```swift
@MainActor
final class Frame {
    let links: FrameLinks
    var state: FrameState
}
```

The state is grouped by the pass that owns it, not by individual flag:

```swift
struct FrameState {
    var document: FrameDocumentState
    var layout: FrameLayoutState
    var display: FrameDisplayState
    var runtime: FrameRuntimeState
}
```

```swift
struct FrameDocumentState {
    var meta: DocumentMeta
    var dom: DOMTree
    var sheets: StylesheetState
    var resources: ResourceState
}

struct DocumentMeta {
    var url: WebURL!
    var title: String
    var isSecure: Bool
    var loaded: Bool
}

struct StylesheetState {
    var rules: [RuleIndex.Rule]
    var keyframes: [String: [Keyframe]]
    var index: RuleIndexState
    var pending: StylePendingState
}

struct RuleIndexState {
    var list: RuleList
    var media: MediaState
}

struct RuleList {
    var sorted: [RuleIndex.Rule]
    var index: RuleIndex
    var rulesRevision: Int
    var indexedRevision: Int
}

struct MediaState {
    var queries: Set<String>
    var matches: [String: Bool]
}

struct StylePendingState {
    var needsHasPrecompute: Bool
    var counters: [String: Int]
    var byViewport: Bool
    var byOther: Bool
}

struct ResourceState {
    var network: NetworkPolicy
    var loadedScripts: Set<String>
    var images: ImageResourceState
}

struct NetworkPolicy {
    var allowedOrigins: [String]?
    var referrerPolicy: String
}

struct ImageResourceState {
    var requestedBackgrounds: Set<String>
    var backgroundCache: [String: CGImage]
    var lazy: [NodeID]
}
```

```swift
struct FrameLayoutState {
    var tree: FrameLayoutTree
    var viewport: FrameViewportState
    var scroll: FrameScrollState
    var targets: ScrollTargetState
}

struct FrameLayoutTree {
    var value: LayoutTree?
    var isDirty: Bool
}

struct FrameViewportState {
    var width: CGFloat
    var height: CGFloat
    var zoom: CGFloat
}

struct FrameScrollState {
    var offset: CGFloat
    var interestTop: CGFloat
}

struct ScrollTargetState {
    var iframes: [IframeTarget]
    var blocks: [ScrollBlockTarget]
    var isValid: Bool
    var needsRebuild: Bool
}
```

`maxScroll` and `interestBottom` stay computed on `Frame`; they read both layout and display state.

```swift
struct FrameDisplayState: Sendable {
    var paint: FramePaintState
    var composite: FrameCompositeState
    var painted: FramePaintedState
}

struct FramePaintState: Sendable {
    var ops: [DisplayOp]
    var revision: UInt
    var epoch: UInt
    var isNeeded: Bool
}

struct FrameCompositeState: Sendable {
    var updates: [NodeID: EffectUpdate]
    var isNeeded: Bool
    var isNeededForPaint: Bool
}

struct FramePaintedState: Sendable {
    var bottom: CGFloat
    var window: PaintWindow
}
```

```swift
struct FrameRuntimeState {
    var script: JSRuntime!
    var schedule: FrameScheduleState
    var interaction: FrameInteractionState
    var animation: FrameAnimationState
}

struct FrameScheduleState {
    var needsRender: Bool
    #if DEBUG
    var debugDumpDependencies: Bool
    #endif
}

struct FrameInteractionState {
    var focus: NodeID?
    var hovered: [NodeID]
    var scrollFocus: NodeID?
    var needsFocusScroll: Bool
}

struct FrameAnimationState {
    var activeCount: Int
    var tween: ScrollTween?
}
```

Every struct has four or fewer stored properties. `FrameState` is the only place the four groups meet.

### 2. Identity and ownership

```swift
struct FrameID: Hashable, Sendable {
    let raw: Int
}

struct FrameLinks {
    weak var tab: BrowserTab?
    let id: FrameID
    let parent: FrameID?
    let element: NodeID?
}
```

```swift
@MainActor
final class BrowserTab {
    private var nextFrameID: Int = 0
    private var framesByID: [FrameID: Frame] = [:]
    private(set) var rootFrameID: FrameID!
    private(set) var focusedFrameID: FrameID!

    var rootFrame: Frame { framesByID[rootFrameID]! }
    var focusedFrame: Frame { framesByID[focusedFrameID]! }
}
```

`BrowserTab` is the only strong owner of frames. `Frame.links.tab` is weak. Parent links are IDs. The iframe side table stores IDs:

```swift
struct EmbedTable {
    var frames: [NodeID: FrameID]
    var frameSources: [NodeID: String]
}
```

`DOMTree` reaches its frame owner through a weak link so `ElementRef.frame` can resolve a `FrameID` without making the DOM own the frame:

```swift
struct DOMLinks {
    weak var layoutTree: LayoutTree?
    weak var owner: Frame?
}
```

This replaces the stored `weak var layoutTree` on `DOMTree`, keeping `DOMTree` at four stored properties.

### 3. Presentation state

The tab owns the state that was in `Browser.TabFrame`:

```swift
struct TabPresentation {
    var display: PresentedDisplay
    var scroll: ScrollState
    var render: PresentedRender
    var preferences: ColorPreferences
}
```

`PresentedDisplay` and `PresentedRender` are the renamed `FrameDisplay` and `FrameRender`. `Browser` no longer has `frames`, `activeFrameID`, or `activeFrame`.

### 4. Snapshot

```swift
struct FrameSnapshot: Sendable {
    let scroll: ScrollState
    let display: DisplaySnapshot
    let preferences: ColorPreferences
}

struct DisplaySnapshot: Sendable {
    let ops: [DisplayOp]
    let updates: [NodeID: EffectUpdate]?
    let revision: UInt
}
```

`FrameSnapshot` replaces `FrameCommit`; `DisplaySnapshot` replaces `FrameDisplayOutput`.

Layers become values:

```swift
struct RasterLayer: Sendable {
    var identity: LayerIdentity
    var content: LayerContent
    var effect: LayerEffectImage
    var tiles: [TileIndex: CGImage]
}

struct LayerIdentity: Sendable {
    let id: LayerID
    let firstCommandIndex: Int
    let ancestorChain: [EffectScope]
}

struct LayerContent: Sendable {
    var items: [DisplayOp]
    var bounds: Rect
    var tileCache: LayerTileCache
}

struct LayerTileCache: Sendable {
    var keys: [TileIndex: TileKey]
    var scale: Int
}

struct LayerEffectImage: Sendable {
    var image: CGImage?
    var key: EffectImageKey?
}
```

`DisplayOp.compositedLayer` becomes:

```swift
indirect case compositedLayer(
    layer: RasterLayer,
    rect: Rect,
    visibleTop: CGFloat,
    visibleBottom: CGFloat
)
```

`indirect` is required: without it, every `DisplayOp` grows to the size of a layer snapshot. The payload is boxed only for composited layers, which are few.

### 5. Main-actor boundary

- Stays `@MainActor`: `Browser`, `BrowserTab`, `Frame`, `DOMTree`, `LayoutTree`, `StyleFields`, `JSRuntime` boundary.
- Becomes nonisolated values: `FrameSnapshot`, `DisplaySnapshot`, `RasterInput`, `RasterScene`, `RasterOutput`, `RasterLayer`, `RasterPlan`, `RasterComposition`, `TileBatch`, `TileStrip`, `RenderedContent`, `LayerPlacement`.
- Raster planning, compositing, tile planning, and effect-image generation move to `Sources/Engine/Raster/` and take only snapshot values.
- `Frame`/layout/paint remain main-actor because they read `DOMTree`, `LayoutTree`, and `StyleFields`. Moving those is a separate value-store rewrite, not an item 6 shortcut.

## Decisions

### D1. Group by pass ownership, nest to satisfy the four-property rule

`FrameState` has exactly the four names from the findings. Those four groups are too large by themselves, so each nests by cohesion:

- `document`: metadata, DOM, style sheets, resources.
- `layout`: tree, viewport, scroll, scroll targets.
- `display`: paint output, composite updates, last painted region.
- `runtime`: script, scheduling, interaction, animation.

No catch-all `FrameParameters`; each nested struct has an invariant (`RuleList` is the sorted rule index pair, `StylePendingState` is one style pass's pending work, `FramePaintedState` is the last painted region).

### D2. `Frame` stays a class; its state becomes a value

`JSRuntime`, `CanvasRenderingContext2D`, AppKit, and the `DOMSideTables` registry need a stable object identity. Making `Frame` a struct would push a handle table into every one of those boundaries.

The class keeps only identity links and `FrameState`. Passes work on `state`; the display and snapshot portions are plain values that can be tested without a browser. `document` and `layout` still hold the main-actor arenas, so they are grouped state, not value state.

### D3. Cross-group invariants use methods, not `didSet`

Current `dom` and `rules` observers touch layout, display, and runtime state (`Frame.swift:23-39,75-80`). Once those fields live in sibling structs, a `didSet` cannot reach them safely.

Replace the observers with methods on `Frame`:

```swift
func replaceDOM(_ dom: DOMTree)
func setLayoutTree(_ tree: LayoutTree?)
func setStyleRules(_ rules: [RuleIndex.Rule])
func appendStyleRules(_ rules: [RuleIndex.Rule])
func mergeKeyframes(_ frames: [String: [Keyframe]])
func setViewport(width: CGFloat, height: CGFloat)
func setPageZoom(_ zoom: CGFloat)
func clearPaintRequest()
```

Each method is the one place that resets the dependent groups. A direct assignment to `state.document.dom` is not allowed outside `replaceDOM`.

### D4. Per-tab presentation belongs to the tab

`Browser.frames: [ObjectIdentifier: TabFrame]` exists only because `Browser` is both tab coordinator and presentation store. That produces:

- writes to both `activeFrame` and `frames[id]` in `commit` (`Browser.swift:212-246`);
- a stale-frame branch for raster completions (`Browser.swift:562-567`);
- `selectTab` reconstructing state from a dictionary (`Browser.swift:992-1015`).

`TabPresentation` lives on `BrowserTab`. The raster completion captures the tab weakly and writes that tab's presentation. No dictionary, no writeback copy.

### D5. `FrameID`, not object references, for stored links

`windowID` is already the stable identity exposed to JS and history. Promote it to `FrameID` and use it for parent links and the iframe side table.

Keep weak object references only where a language boundary demands identity: `JSRuntime.frame`, `Frame.links.tab`. Local `Frame` handles inside one function are fine; stored cross-tree references are not.

### D6. `CompositedLayer` becomes a value; the composited op is `indirect`

The class exists because raster mutates tiles and effect images in place. That mutation belongs to the raster job, not to the display list.

`RasterLayer` is a value. `rasterIfNeeded` mutates a local layer array; install returns the updated layers in `RasterOutput`. `TileStrip` carries a `layerIndex` instead of a layer reference.

The layer-local key cache stays with the layer but moves into `LayerContent` as a small `LayerTileCache` value:

```swift
struct LayerContent: Sendable {
    var items: [DisplayOp]
    var bounds: Rect
    var tileCache: LayerTileCache
}

struct LayerTileCache: Sendable {
    var keys: [TileIndex: TileKey]
    var scale: Int
}
```

That preserves reuse across deferred continuation passes, invalidates when items change, and keeps `RasterLayer` at four stored properties. It is a cache value, not a live object.

### D7. `FontMeasureCache` gets a lock; `BrowserFont` becomes `Sendable`

`BrowserFont` appears in every text `DisplayOp` and owns a mutable cache class (`BrowserFont.swift:6-9`). A snapshot containing text is not safe to send until that cache is synchronized.

```swift
final class FontMeasureCache: @unchecked Sendable {
    private let lock = NSLock()
    private var widths: [String: CGFloat] = [:]

    func width(for text: String, compute: () -> CGFloat) -> CGFloat { ... }
}
```

`CTFont`, `CGImage`, and `CGColor` are already `Sendable` (verified with the Swift 6.2 compiler). The only fix is the cache.

### D8. The nonisolated seam is the snapshot, not the layout engine

The findings ask to shrink the main actor "where dependencies allow". Here the dependencies do not allow layout or paint to leave main yet:

- `LayoutTree` and `DOMTree` are `@MainActor` arenas (`LayoutTree.swift:9`, `DOMTree.swift:7`).
- Paint reads `StyleFields`, still one class per DOM node.
- Animation and JS mutate the same DOM.

What can move is everything after commit: raster planning, compositing, tile planning, effect images, and presentation. Those functions become nonisolated pure functions over `FrameSnapshot`. This is the real `Sendable` boundary and the part that can be verified by the compiler.

Do not claim layout/paint are off-main after item 6. That requires converting the style store and both arenas to values, which is a separate refactor.

### D9. Rename the history `FrameState`

`BrowserTab` already has a private `FrameState` for navigation history (`BrowserTab.swift:4-7`). Rename it to `NavigationLocation` before introducing the grouped frame state.

## Field map

Every current stored property has one destination.

| Current `Frame` field | Target path |
|---|---|
| `tab`, `parentFrame`, `frameElement`, `windowID` | `links` (`FrameLinks`) |
| `url`, `title`, `isSecure`, `loaded` | `state.document.meta` |
| `dom` | `state.document.dom` |
| `rules`, `keyframes` | `state.document.sheets` |
| `rulesRevision`, `sortedRules`, `ruleIndex`, `indexedRulesRevision`, `mediaQueries`, `mediaMatches` | `state.document.sheets.index` |
| `needsHasPrecompute`, `pendingStyleInvalidations`, `styleInvalidatedByViewport`, `styleInvalidatedByOther` | `state.document.sheets.pending` |
| `allowedOrigins`, `referrerPolicy` | `state.document.resources.network` |
| `loadedScriptURLs`, `requestedBackgroundImages`, `backgroundImageCache`, `lazyImages` | `state.document.resources` |
| `documentValue`, `documentDirty` | `state.layout.tree` |
| `frameWidth`, `frameHeight`, `pageZoom` | `state.layout.viewport` |
| `scroll`, `interestTop` | `state.layout.scroll` |
| `iframeTargets`, `scrollBlockTargets`, `scrollTargetsValid`, `scrollTargetsNeedRebuild` | `state.layout.targets` |
| `displayList`, `paintRevision`, `paintEpoch`, `needsPaint` | `state.display.paint` |
| `compositedUpdates`, `needsComposite`, `needsCompositeForPaint` | `state.display.composite` |
| `paintedBottom`, `paintedWindow` | `state.display.painted` |
| `js` | `state.runtime.script` |
| `needsRender`, `debugDumpDependencies` | `state.runtime.schedule` |
| `focus`, `hoveredElements`, `scrollFocusNode`, `needsFocusScroll` | `state.runtime.interaction` |
| `activeAnimations`, `scrollTween` | `state.runtime.animation` |
| `maxScroll`, `interestBottom` | computed on `Frame` |
| `hasScrollElement` | computed on `Frame` |

## File map

### New files

| File | Type |
|---|---|
| `Core/FrameState.swift` | `FrameState` |
| `Core/FrameDocumentState.swift` | `FrameDocumentState`, `DocumentMeta` |
| `Core/StylesheetState.swift` | `StylesheetState` |
| `Core/RuleIndexState.swift` | `RuleIndexState`, `RuleList`, `MediaState` |
| `Core/StylePendingState.swift` | `StylePendingState` |
| `Core/ResourceState.swift` | `ResourceState`, `NetworkPolicy`, `ImageResourceState` |
| `Core/FrameLayoutState.swift` | `FrameLayoutState`, `FrameLayoutTree`, `FrameViewportState`, `FrameScrollState` |
| `Core/ScrollTargetState.swift` | `ScrollTargetState`, `IframeTarget`, `ScrollBlockTarget` |
| `Core/FrameDisplayState.swift` | `FrameDisplayState`, `FramePaintState`, `FrameCompositeState`, `FramePaintedState` |
| `Core/FrameRuntimeState.swift` | `FrameRuntimeState`, `FrameScheduleState`, `FrameInteractionState`, `FrameAnimationState` |
| `Core/FrameLinks.swift` | `FrameLinks` |
| `Core/FrameID.swift` | `FrameID` |
| `Core/FrameSnapshot.swift` | `FrameSnapshot` |
| `Core/DisplaySnapshot.swift` | `DisplaySnapshot` |
| `Presentation/TabPresentation.swift` | `TabPresentation` |
| `Presentation/PresentedDisplay.swift` | renamed `FrameDisplay` |
| `Presentation/PresentedRender.swift` | renamed `FrameRender` |
| `Presentation/PresentationSignature.swift` | renamed `FrameSignature` |
| `Presentation/PresentationViewport.swift` | renamed `FrameViewport` |
| `Presentation/PresentationRevisions.swift` | renamed `FrameRevisions` |
| `Raster/RasterLayer.swift` | replaces `CompositedLayer` |
| `Raster/LayerIdentity.swift` | `LayerIdentity` |
| `Raster/LayerContent.swift` | `LayerContent` |
| `Raster/LayerEffectImage.swift` | `LayerEffectImage`, `EffectImageKey` |
| `Raster/RasterCompositor.swift` | layer construction and reuse |
| `Raster/RasterDrawList.swift` | draw-list construction |
| `Raster/RasterEffectCache.swift` | effect bitmap generation |
| `Tests/ToyStackTests/RasterCompositorTests.swift` | layer composition behavior |

Nested support types may share the owning file (for example `LayerContent` may live in `RasterLayer.swift`); one concept per file still applies to top-level types.

### Deleted files

- `Core/FrameCommit.swift`
- `Core/FrameDisplayOutput.swift`
- `Core/FrameParent.swift`
- `Raster/CompositedLayer.swift`
- `Core/FrameDisplay.swift`
- `Core/FrameRender.swift`
- `Core/FrameSignature.swift`
- `Core/FrameViewport.swift`
- `Core/FrameRevision.swift`

### Modified files

- `Core/Frame.swift` — state grouping, methods, snapshot.
- `Core/Browser.swift` — presentation ownership, raster extraction.
- `Core/BrowserTab.swift` — registry, IDs, presentation, history rename.
- `Parsing/DOMTree.swift` — `DOMLinks`.
- `Parsing/DOMSideTables.swift` — `EmbedTable.frames: [NodeID: FrameID]`.
- `Parsing/ElementRef.swift` — frame resolution through the registry.
- `Core/FocusNavigation.swift` — `FrameID` targets.
- `Accessibility/FrameAccessibilityNode.swift` — state reads.
- `Display/DisplayOp.swift` — sendability, `RasterLayer` payload.
- `Display/PaintWindow.swift` — remove `@MainActor`.
- `Platform/BrowserFont.swift` — locked cache.
- `Raster/*` — value layer pipeline and conformance cleanup.
- `Tests/ToyStackTests/LayoutTestPage.swift`, `FrameReloadTests.swift`, `PaintCacheTests.swift` — migrated accessors and layer construction.
- `plans/refactoring/oop-refactor-order.md` — link this plan.

## Steps

Each step ends with `swift build` and `swift test` green. Do not park between A and B on forwarding accessors: they are a migration bridge, not a second API.

### Step A0 — Pin the baseline

- Confirm clean `main`, `swift build`, `swift test` (205 tests).
- Capture the four screenshots from the Baseline section.
- Gate: baseline images exist and tests pass.

### Step A1 — Add `FrameState` and move the document group

Add `FrameState` with only `document` at first:

```diff
 @MainActor
 class Frame {
-    var url: WebURL!
-    var dom: DOMTree = DOMTree() {
-        didSet {
-            guard oldValue !== dom else { return }
-            documentValue = nil
-            documentDirty = true
-            scrollTargetsValid = false
-            scrollTargetsNeedRebuild = true
-            iframeTargets.removeAll()
-            scrollBlockTargets.removeAll()
-            scrollFocusNode = nil
-            compositedUpdates.removeAll()
-            needsRender = true
-            needsPaint = true
-        }
-    }
-    var title: String = "New Tab"
-    var isSecure: Bool = false
-    var rules: [(String?, any CSSSelector, [String: String])] = [] { ... }
-    var keyframes: [String: [Keyframe]] = [:]
-    private var allowedOrigins: [String]?
-    private var referrerPolicy: String = ""
-    private var loadedScriptURLs: Set<String> = []
-    private var requestedBackgroundImages: Set<String> = []
-    private var backgroundImageCache: [String: CGImage] = [:]
-    private var lazyImages: [NodeID] = []
+    var state: FrameState = FrameState()
 }
```

Move the document fields into `FrameDocumentState`, `DocumentMeta`, `StylesheetState`, `RuleIndexState`, `StylePendingState`, `ResourceState`, `NetworkPolicy`, and `ImageResourceState`.

Two invariants become methods:

```swift
// A1 body: layout, display, and runtime are still flat until A2-A4.
func replaceDOM(_ newDOM: DOMTree) {
    let old = state.document.dom
    guard old !== newDOM else { return }
    state.document.dom = newDOM
    documentValue = nil
    documentDirty = true
    scrollTargetsValid = false
    scrollTargetsNeedRebuild = true
    iframeTargets.removeAll()
    scrollBlockTargets.removeAll()
    scrollFocusNode = nil
    compositedUpdates.removeAll()
    needsRender = true
    needsPaint = true
}

func setStyleRules(_ rules: [RuleIndex.Rule]) {
    state.document.sheets.rules = rules
    state.document.sheets.index.list.rulesRevision += 1
    state.document.sheets.pending.needsHasPrecompute = true
}

func appendStyleRules(_ rules: [RuleIndex.Rule]) {
    state.document.sheets.rules.append(contentsOf: rules)
    state.document.sheets.index.list.rulesRevision += 1
    state.document.sheets.pending.needsHasPrecompute = true
}

func mergeKeyframes(_ frames: [String: [Keyframe]]) {
    state.document.sheets.keyframes.merge(frames) { _, new in new }
}
```

Update the two `dom =` sites (`Frame.swift:266`, `Frame.swift:676`) and the `rules =` sites (`Frame.swift:305,685,709`; `append` at `372,381,720,726`).

`replaceDOM` is rewritten in A2-A4 as each dependent field moves into its group. It is the only allowed DOM replacement path from A1 onward.

Keep temporary computed forwarders for document reads (`dom`, `rules`, `keyframes`, `url`, `title`, `isSecure`, `loaded`, `nodes`) so the rest of `Frame` compiles unchanged. Keep setters only where a semantic method does not exist.

Gate: build/tests green; DOM reload test (`FrameReloadTests`) still passes.

### Step A2 — Move the layout group

Add `layout` to `FrameState`.

Move `documentValue`, `documentDirty`, `frameWidth`, `frameHeight`, `scroll`, `interestTop`, `pageZoom`, `iframeTargets`, `scrollBlockTargets`, `scrollTargetsValid`, `scrollTargetsNeedRebuild`.

Replace the `frameWidth` observer with:

```swift
func setViewport(width: CGFloat, height: CGFloat) {
    let oldWidth = state.layout.viewport.width
    state.layout.viewport.width = width
    state.layout.viewport.height = height
    if oldWidth != width {
        state.layout.tree.value?.markDocumentWidthDirty()
    }
}
```

`maxScroll` and `interestBottom` stay computed on `Frame`, reading `state.layout` and `state.display`.

Update external width/height writes: `BrowserTab.resize` (`BrowserTab.swift:228-230`) and `EmbedLayoutPass.swift:382-388` call `setViewport`.

Gate: resize, incremental layout, and iframe layout tests pass; `www/ch16/exercise-16-2-protecting-layout-phases.html` screenshot matches.

### Step A3 — Move the display group

Add `display` to `FrameState`.

Move `displayList`, `paintRevision`, `paintEpoch`, `needsPaint`, `compositedUpdates`, `needsComposite`, `needsCompositeForPaint`, `paintedBottom`, `paintedWindow`.

Update `paint()`:

```diff
-var list: [DisplayOp] = []
-list.reserveCapacity(displayList.count)
+var list: [DisplayOp] = []
+list.reserveCapacity(state.display.paint.ops.count)
...
-displayList = list
-paintedBottom = contentBottom
-paintRevision += 1
-needsPaint = false
+state.display.paint.ops = list
+state.display.painted.bottom = contentBottom
+state.display.paint.revision += 1
+state.display.paint.isNeeded = false
```

Add `func clearPaintRequest()` for `BrowserTab.runAnimationFrame` (`BrowserTab.swift:197-199`) instead of mutating `frame.needsPaint`.

Gate: paint-cache and paint tests pass; `www/ch11/index.html` screenshot matches.

### Step A4 — Move the runtime group

Add `runtime` to `FrameState`.

Move `js`, `focus`, `hoveredElements`, `scrollFocusNode`, `scrollTween`, `activeAnimations`, `needsRender`, `needsFocusScroll`, and the debug flag.

Keep `JSRuntime!` in `FrameRuntimeState` to preserve existing load assumptions; do not widen optionality in this step.

Update `runAnimationFrame` to use `state.runtime.animation` and `state.runtime.schedule`.

Gate: animation tests and `www/ch13/exercise-13-6.html` screenshot match.

### Step A5 — Delete the forwarders and prove one stored state

Remove every temporary computed accessor from A1-A4. Update remaining `Frame` references to `state.<group>.<field>` and update tests:

- `LayoutTestPage` uses `frame.dom = ...`, `frame.rules = ...`; switch to `replaceDOM`/`setStyleRules`.
- `FrameReloadTests` uses `frame.dom = ...`; switch to `replaceDOM`.

Keep a small read-only coordinator API where it is genuinely public:

```swift
var nodes: DOMRef { DOMRef(id: state.document.dom.root, dom: state.document.dom) }
var document: LayoutTree? { state.layout.tree.value }
var url: WebURL! { state.document.meta.url }
var title: String { state.document.meta.title }
var scroll: CGFloat { state.layout.scroll.offset }
var pageZoom: CGFloat { state.layout.viewport.zoom }
```

No setters in that API.

Gate: no flat document/layout/display/runtime fields remain in `Frame`; only identity fields (`tab`, `parentFrame`, `frameElement`, `windowID`) and `state`. `swift test` green.

### Step B1 — Add `FrameID` and `FrameLinks`

Add `FrameID` and replace the four identity fields:

```diff
-weak var tab: BrowserTab?
-weak var parentFrame: Frame?
-var frameElement: NodeID?
-let windowID: Int
+let links: FrameLinks
```

Add registration and lookup to `BrowserTab`:

```swift
func reserveFrameID() -> FrameID {
    let id = FrameID(raw: nextFrameID)
    nextFrameID += 1
    return id
}

func frame(_ id: FrameID?) -> Frame? {
    guard let id else { return nil }
    return windowIDToFrame[id.raw]
}
```

Keep the old `windowIDToFrame` temporarily so the build stays green. `Frame.windowID` becomes computed `links.id.raw`; `parentFrame` becomes `links.tab?.frame(links.parent)`.

Gate: iframe history and focus tests pass.

### Step B2 — Make `BrowserTab` the single frame owner

Replace `windowIDToFrame`, `rootFrame: Frame!`, and `focusedFrame: Frame!` with `framesByID`, `rootFrameID`, and `focusedFrameID`. Keep computed `rootFrame`/`focusedFrame` so existing call sites read naturally.

Changes:

- `HistoryEntry.windowID` becomes `frame: FrameID`.
- `postMessage(targetWindowID:)` wraps `FrameID(raw: targetWindowID)`.
- `syncIframes`, `discardChildFrames`, `unload`, and `setPageZoom` filter by `links.parent == links.id` instead of `parentFrame === self`.
- `setFocusedFrame` stores an ID.
- `Frame.init` registers itself after all stored properties are initialized.

Rename the private history `FrameState` to `NavigationLocation` here (D9).

Gate: no `windowIDToFrame`, no `ObjectIdentifier(tab)` frame keys; tests green.

### Step B3 — Store frame IDs in the iframe side table

Change `EmbedTable.frames` to `[NodeID: FrameID]` and add `DOMLinks`:

```diff
-final class DOMTree {
-    private(set) var nodes: [DOMNode?]
-    private(set) var root: NodeID
-    var side: DOMSideTables
-    weak var layoutTree: LayoutTree?
+final class DOMTree {
+    private(set) var nodes: [DOMNode?]
+    private(set) var root: NodeID
+    var side: DOMSideTables
+    var links: DOMLinks
+}
```

`ElementRef.frame` resolves through the owner:

```swift
var frame: Frame? {
    dom.links.owner?.frame(dom.side.embeds.frames[id])
}

nonmutating set {
    dom.side.embeds.frames[id] = newValue?.links.id
}
```

`Frame` sets `dom.links.owner = self` after initialization. The weak link breaks the cycle: `Frame` owns `DOMTree`; `DOMTree` does not own `Frame`.

Gate: `www/ch15/index.html` and `example15-dynamic-iframe.html` render identically.

### Step B4 — Move presentation state into the tab

Add `TabPresentation` to `BrowserTab`. Rename `FrameDisplay`/`FrameRender` to `PresentedDisplay`/`PresentedRender`.

```diff
-private struct TabFrame {
-    var display: FrameDisplay = FrameDisplay()
-    var scroll: ScrollState = ...
-    var render: FrameRender = FrameRender()
-    var preferences: ColorPreferences = ...
-}
-
-private var frames: [ObjectIdentifier: TabFrame] = [:]
-private var activeFrameID: ObjectIdentifier?
-private var activeFrame: TabFrame = TabFrame()
+private var activePresentation: TabPresentation {
+    get { activeTab?.presentation ?? TabPresentation.empty }
+    set { activeTab?.presentation = newValue }
+}
```

Wrap the `TabPresentation` struct in a file with the same four-field rule. `TabPresentation.empty` carries the same defaults the old `TabFrame()` initializer had.

Update `commit`, `applyScroll`, `applyScrollAndUpdateInterest`, `selectTab`, `presentedFrame`, `canvasColor`, `activeSidebar`, and `scheduleRasterAndDraw` to read `activeTab.presentation` or the captured owner tab.

The raster completion becomes:

```swift
then: { [weak self, weak owner] output in
    guard let self, let owner else { return }
    owner.presentation.render.layers = output.layers ?? owner.presentation.render.layers
    ...
    if owner === self.activeTab {
        self.activePresentation.render.signature = signature
        self.dispatchPresent(frameID: frameID)
    }
}
```

No `frames[ownerID] = ...` writeback. The stale-frame branch disappears.

Gate: tab switching, background raster completion, scroll, and presentation tests pass; all four screenshots match.

### Step B5 — Use `FrameID` in focus targets

`FocusTarget` stores `frame: FrameID` and `element: NodeID`. Resolve through `tab.frame(id)` in `focusOder`, `tabOrderKey`, and `advanceTab`.

Audit stored strong `Frame` references:

```sh
grep -rn "var .*: Frame\b\|let .*: Frame\b\|\[.*: Frame\]" Sources/Engine
```

Allowed: `BrowserTab.framesByID`, local handles, `JSRuntime` (weak), `FrameAccessibilityNode` (computed transient). Everything else is a registry ID or a weak back-pointer.

Gate: focus navigation and iframe focus tests pass.

### Step C1 — Replace `CompositedLayer` with `RasterLayer`

Add the value layer types and delete the class. Update:

- `DisplayOp.compositedLayer` to the `indirect` value payload.
- `DisplayOp.execute` and `executeCompositedLayer`.
- `Browser.computeComposite`, `reuseRasterization`, `layerEffectStrategy`, `computePaintDrawList`, `layerPlacements`, `rasterEffectBitmap`, `updateEffectImage`.
- `TileStrip` to `layerIndex: Int`.
- `RasterComposition.layers` to `var` so install can write tiles back through a local copy.
- `RasterOutput.compositedLayers` to `layers: [RasterLayer]?`.
- `RenderedContent` and `LayerPlacement` consumers.
- `CompositedLayer.tileSize` and `rasterCapPerComposite` to `RasterLayer` statics.
- `CompositedLayer.keyCache` to `LayerContent.tileCache`.

Layer construction keeps the old convenience shape:

```swift
init(
    displayItem: DisplayOp,
    firstCommandIndex: Int = -1,
    id: LayerID = LayerID(effect: nil, ordinal: 0)
)
```

This is a real initializer, not a compatibility shim; it is the smallest way to build a layer from the first op.

Install writes tiles into a local array:

```swift
var layers: [RasterLayer] = plan.composition.layers
for (i, strip) in plan.batch.strips.enumerated() {
    guard let stripImage = images[i] else { continue }
    for key in strip.tiles {
        guard let tile = stripImage.cropping(to: ...) else { continue }
        layers[strip.layerIndex].tiles[key.index] = tile
        store.insert(tile, key: key)
    }
}
```

Add `Tests/ToyStackTests/RasterCompositorTests.swift` with synthetic ops:

- adjacent ops in the same effect scope merge into one layer;
- leaving and re-entering a scope starts a new layer;
- `firstCommandIndex` and `ancestorChain` match the stream;
- `computePaintDrawList` replaces drawing ops with composited-layer ops and keeps `beginEffect`/`endEffect` order.

These are behavior tests for the value layer pipeline, not source-shape checks.

Gate: `PaintCacheTests.compositedLayerIsRejected` updated and passing; new compositor tests pass; `www/ch11`, `www/ch15`, and `www/ch13` screenshots match.

### Step C2 — Make display and raster leaves `Sendable`

Conform the closed value leaves:

- `BrowserColor`, `ImageRendering`, `Rect`, `Point`, `CornerRadii`, `RadiusLength`, `ClipShape`.
- `EffectKind`, `EffectScope`, `EffectPlacement`, `EffectScopeID`, `EffectUpdate`, `PaintEffectStyle`, `PaintWindow`.
- `ScrollState`, `Viewport`, `ContentScale`, `ColorPreferences`, `RasterInvalidation`, `AccessibilityBounds`, `RasterSettings`.
- `TileIndex`, `TileKey`, `LayerID`, `EffectImageKey`, `LayerEffectStrategy`.
- `LayerEffect`, `LayerPlacement`, `LayerPlacementKey`, `RenderedContent`.
- `DisplayOp`, `RasterLayer`, `FrameDisplayState` and its children.
- `BrowserFont` and `FontMeasureCache` per D7.

Fix `BrowserFont` per D7. Use `cache.width(for: text) { ... }` inside `measure`.

Remove `@MainActor` from `PaintWindow`; it is a pure two-value struct.

`FrameDisplayState` now compiles as `Sendable`, which proves paint output is value-only.

Gate: build succeeds. Any type that needs a class reference in a snapshot blocks conformance and must be moved out, not marked `@unchecked`.

### Step C3 — Introduce `FrameSnapshot` and delete commit structs

Replace `FrameCommit`/`FrameDisplayOutput`:

```diff
-struct FrameCommit {
-    let scrollState: ScrollState
-    let display: FrameDisplayOutput
-    let preferences: ColorPreferences
-}
+struct FrameSnapshot: Sendable {
+    let scroll: ScrollState
+    let display: DisplaySnapshot
+    let preferences: ColorPreferences
+}
+
+struct DisplaySnapshot: Sendable {
+    let ops: [DisplayOp]
+    let updates: [NodeID: EffectUpdate]?
+    let revision: UInt
+}
```

`Frame` builds it:

```swift
func makeSnapshot() -> FrameSnapshot {
    let display = state.display
    let updates = (display.composite.isNeeded || display.composite.isNeededForPaint)
        ? nil
        : display.composite.updates
    return FrameSnapshot(
        scroll: ScrollState(
            scroll: state.layout.scroll.offset,
            interestTop: state.layout.scroll.interestTop,
            interestBottom: interestBottom,
            maxScroll: maxScroll
        ),
        display: DisplaySnapshot(
            ops: display.paint.ops,
            updates: updates,
            revision: display.paint.revision
        ),
        preferences: ColorPreferences(
            prefersDark: tab?.prefersDark ?? false,
            usesForcedColors: tab?.forcedColors ?? false
        )
    )
}
```

`commitFrame` clears composite state after taking the snapshot. `Browser.commit` takes `FrameSnapshot`.

Then remove `@unchecked Sendable` from:

- `RasterInput`, `RasterScene`, `RasterOutput`
- `RasterPlan`, `RasterComposition`
- `TileStrip`, `TileBatch`

`RasterScheduler`, `TileStore`, and `RasterWorkerPool` may keep `@unchecked Sendable`: they are synchronization/queue boundaries, not snapshot payloads. The gate is that no data crossing the worker boundary requires `@unchecked`.

Gate: build with no `@unchecked` on the listed payloads; raster output identical.

### Step C4 — Prove no live state crosses the boundary

Audit the raster closures. They may capture:

- `FrameSnapshot` / `RasterInput` values
- `MeasureTime`, `TraceContext`
- `weak BrowserTab` / `weak Browser` for the completion

They may not capture `Frame`, `TabPresentation`, `DOMTree`, or `LayoutTree`.

```sh
grep -rn "@unchecked Sendable" Sources/Engine/Raster
git grep -n "activeFrame\|frames\[" Sources/Engine
```

Expected: only the scheduler/worker/tile-store synchronization classes; no `activeFrame`, no frame map.

Gate: build/tests green.

### Step D1 — Move raster planning and compositing out of `Browser`

Create `Raster/RasterCompositor.swift` and `Raster/RasterDrawList.swift`. Move these `Browser` statics:

- `computeComposite` (`Browser.swift:600-655`)
- `reuseRasterization` (`656-674`)
- `layerEffectStrategy` (`676-744`)
- `updatesAreCA` (`745-752`)
- `computePaintDrawList` (`754-807`)
- `updatedScope` (`809-832`)
- `layerPlacements` (`834-872`)
- `rasterEffectBitmap` (`873-887`)
- `updateEffectImage` (`888-893`)

They become plain nonisolated functions/types in the raster module. `Browser.scheduleRasterAndDraw` keeps only sequencing: build request, schedule, dispatch present.

Gate: no `nonisolated static func` left in `Browser` that operates on raster values; behavior unchanged.

### Step D2 — Audit the main-actor surface

Required `@MainActor`:

- `Browser`, `BrowserTab`, `Frame`
- `DOMTree`, `LayoutTree`, `StyleFields`
- `JSRuntime` and Canvas/AppKit boundaries

Required nonisolated:

- all snapshot and raster value types
- `RasterCompositor`, `RasterDrawList`, `RasterEffectCache`
- `TileStripRasterizer` and the worker pool entry points

Add a comment to `FrameState.swift`:

```swift
/// Grouped frame state. `document` and `layout` still hold main-actor arenas;
/// `display` is a Sendable value and is the only part that crosses to raster.
```

Do not remove `@MainActor` from the arenas in this item. Document why in the plan/commit body.

Gate: build with no new `@MainActor` in `Raster/`; snapshots compile as `Sendable`.

## Verification

After each step:

```sh
swift build
swift test
```

After A5, B4, C3, and D2:

```sh
swift run ToyStackHeadless "file://$PWD/www/ch11/index.html" \
  --trace /tmp/after-frame-paint.trace --frame-limit 5 --screenshot /tmp/after-frame-paint.png
swift run ToyStackHeadless "file://$PWD/www/ch15/index.html" \
  --trace /tmp/after-frame-embed.trace --frame-limit 5 --screenshot /tmp/after-frame-embed.png
swift run ToyStackHeadless "file://$PWD/www/ch16/exercise-16-2-protecting-layout-phases.html" \
  --trace /tmp/after-frame-incremental.trace --frame-limit 5 --screenshot /tmp/after-frame-incremental.png
swift run ToyStackHeadless "file://$PWD/www/ch13/exercise-13-6.html" \
  --trace /tmp/after-frame-anim.trace --frame-limit 30 --screenshot /tmp/after-frame-anim.png
```

Compare each after-image with its before-image. If a screenshot differs, inspect the trace before changing code:

- paint output changed: compare `paint` and `displayList` counts.
- raster changed: compare tile hits/misses and `composite_raster_and_draw`.
- animation changed: inspect frames around the transform.

Final structural checks:

```sh
# Frame has one grouped state, not a flat bag.
grep -n "private var\|var .*:.*=" Sources/Engine/Core/Frame.swift | head

# No frame map or active-frame copy remains.
grep -rn "windowIDToFrame\|activeFrame\|activeFrameID" Sources/Engine

# No value layer class remains.
grep -rn "class CompositedLayer\|CompositedLayer(" Sources/Engine

# Only synchronization boundaries keep unchecked.
grep -rn "@unchecked Sendable" Sources/Engine/Raster

# iframe side table stores IDs, not frames.
grep -n "frames:" Sources/Engine/Parsing/DOMSideTables.swift
```

Manual smoke:

- Switch tabs while a raster job is running; the old tab must keep its own presentation and the active tab must not show the old frame.
- Load `www/ch15/index.html`; navigate an iframe; close it; confirm no stale frame stays in `framesByID`.
- Scroll a long page; confirm tiles and scrollbar still update.
- Run an animation page; confirm commit/snapshot updates do not freeze.

## Risks

| Risk | Mitigation |
|---|---|
| `DisplayOp` growth from an inline layer payload | Use `indirect case`; verify enum size or memory behavior in the first C1 build. |
| Raster layer value copies | Arrays and dictionaries are COW. Layers are rebuilt per composite already; install copies only shared buffers. |
| Tile hash cache migration | `LayerContent.tileCache` must be cleared when `items` change and when scale changes, matching `CompositedLayer.add` and `keyCacheScale`. |
| iframe lifetime changes | The tab registry is the only owner; side tables store IDs. Test load, unload, navigate, and tab close. |
| Animation/post-message frame lookup | `FrameID` keeps the same numeric value as `windowID`; only the type changes. |
| Forwarding accessors left behind | A5 is a hard gate; do not merge A with forwarders. |
| Main-actor claims overstated | D2 documents the exact boundary: snapshot/raster nonisolated, layout/paint still main. |
| `BrowserFont` lock in a hot path | The cache is per-font and text measurement already has a cache miss path. Keep the lock narrow; do not hold it during CoreText measurement. |

## Commit order

1. `refactor: group frame state by pass` — A1-A5.
2. `refactor: give frames stable identities` — B1-B3.
3. `refactor: let each tab own its presentation` — B4-B5.
4. `refactor: make display layers values` — C1.
5. `refactor: freeze the raster snapshot` — C2-C4.
6. `refactor: keep raster work off the main actor` — D1-D2.

Each commit leaves `swift build` and `swift test` green. The tree must never sit between A1 and A5 with both flat fields and grouped state as independent storage.
