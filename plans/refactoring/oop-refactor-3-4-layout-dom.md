# Layout and DOM refactor: items 3 and 4

Implementation plan for **item 3 (layout and DOM)** and **item 4 (invalidation)** from [oop-findings.md](./oop-findings.md). Ordering rationale lives in [oop-refactor-order.md](./oop-refactor-order.md).

**Yes, this is next.** Items 1, 2, and 5 are committed. The fixed sequence is:

```
1 → 2 → 5 → 3 → 4 → 6
```

Items 3 and 4 share this plan because `NodeID` cannot be introduced in one file at a time:

- `FieldRef` / `FieldDependencyKey` (`Sources/Engine/Core/FieldRef.swift:5-33`, `FieldDependencyKey.swift:5-13`) key dependencies by `ObjectIdentifier`.
- `LayoutInvalidation` (`Sources/Engine/Core/LayoutInvalidation.swift:6-26`) finds layout owners through `layoutObject as? BlockLayout`.
- A layout arena changes both: fields and invalidation edges need stable `LayoutID` / `NodeID` values, not object addresses.

This file is the plan only. No engine code is edited here.

## Scope

**In scope**

- Introduce `NodeID` (DOM identity) and `LayoutID` (layout identity) as values.
- Replace `NodeKey` and every node-identity `ObjectIdentifier` cache with `NodeID`.
- Replace the `DOMNode` protocol with `Element` / `TextNode` classes by one tagged arena:
  `DOMTree` owns `[DOMNode]`; `DOMRef`, `ElementRef`, and `TextRef` are lightweight views.
- Move cold element state (`image`, `backgroundImage`, `frame`, `canvasContext`, `scrollOffsetY`) to side tables keyed by `NodeID`.
- Replace the `LayoutObject` protocol hierarchy (`DocumentLayout`, `BlockLayout`, `LineLayout`, `TextLayout`, `EmbedLayout`, and embed subclasses) with one tagged arena:
  `LayoutTree` owns `[LayoutNode]`; `LayoutRef` is a lightweight view.
- Replace `as?` checks in layout, paint, hit-test, invalidation, accessibility, and frame code with exhaustive `switch` over `DOMKind` / `LayoutKind`.
- Replace per-instance `[any InvalidatableField]` arrays and per-node `dependents` dictionaries with:
  - one static input table per node kind and field;
  - one reverse `DependencyIndex` for the whole tree;
  - `FieldKey = .layout(LayoutID, LayoutField)` or `.style(NodeID, StyleProperty)`.
- Make `read(notify:)` / `touch(_:)` disappear. Reads become pure.
- Keep behavior equivalent: block/inline layout, incremental child reuse, paint caches, scroll targets, iframe embedding, canvas, accessibility, focus, hover, and animation updates.

**Out of scope**

- `Frame` state grouping and `Sendable` snapshots (item 6). `LayoutTree` and `DOMTree` stay main-actor classes owned by `Frame`.
- Making `StyleFields` a value type. It stays one class per DOM node; this plan gives it an owner `NodeID` and removes its dependency dictionary in Phase D.
- `Renderer`, `TaskRunner`, and font/network backends. They remain the open seams.
- New CSS, layout, or JS features. This is a representation refactor.

## Baseline

Verified before writing this plan:

- `swift build` → `Build complete!`
- `swift test` → **189 tests in 26 suites passed**
- Current code shape:
  - `Sources/Engine/Parsing/DOMNode.swift:4-40` defines the `DOMNode` protocol and the two classes.
  - `Sources/Engine/Layouts/LayoutObject.swift:5-12` defines the `LayoutObject` protocol.
  - `Sources/Engine/Core/Frame.swift:23-30` owns `nodes: any DOMNode` and `document: DocumentLayout?`.
  - `Sources/Engine/Core/FieldRef.swift:5-33`, `LayoutFieldStore.swift:5-17`, and `LayoutFieldHandle.swift:5-105` hold the current graph.
  - 157 `as?` sites in `Sources/Engine`, 120 of them `Element` / `TextNode`; 251 references to the handle/invalidation API.

Capture visual baselines before the first code step:

```sh
swift run ToyStackHeadless "file://$PWD/www/ch11/index.html" \
  --trace /tmp/before-layout-paint.trace --frame-limit 5 --screenshot /tmp/before-layout-paint.png
swift run ToyStackHeadless "file://$PWD/www/ch15/index.html" \
  --trace /tmp/before-layout-embed.trace --frame-limit 5 --screenshot /tmp/before-layout-embed.png
swift run ToyStackHeadless "file://$PWD/www/ch16/exercise-16-2-protecting-layout-phases.html" \
  --trace /tmp/before-layout-incremental.trace --frame-limit 5 --screenshot /tmp/before-layout-incremental.png
```

`www/ch11/index.html` covers paint/effects. `www/ch15/index.html` covers iframe/image/canvas embeds. `www/ch16/exercise-16-2-protecting-layout-phases.html` covers incremental layout reuse.

## End state

### Identity

Two IDs, not one. A DOM node can have zero layout nodes (`head`, `script`), one primary layout node, or several layout nodes (anonymous block, line, each word). A layout node can cover several DOM nodes (`extraNodes` and run-in headings). One ID space cannot express both.

```swift
struct NodeID: Hashable, Sendable {
    let raw: UInt32
}

struct LayoutID: Hashable, Sendable {
    let raw: Int
}
```

`FieldKey` is the closed key type shared by layout and style fields:

```swift
enum FieldKey: Hashable {
    case layout(LayoutID, LayoutField)
    case style(NodeID, StyleProperty)
}
```

### DOM storage

The data is tagged. The classes become views over the arena.

```swift
enum DOMKind {
    case element(ElementData)
    case text(TextData)
}

struct DOMNode {
    var kind: DOMKind
    var base: DOMBase
}

struct DOMBase {
    var parent: NodeID?
    var children: [NodeID]
    var style: StyleFields
    var state: DOMState
}

struct DOMState {
    var flags: DOMFlags
    var animations: [AnimationKey: Animation]
}

struct DOMFlags {
    var isFocused: Bool
    var isFocusVisible: Bool
    var isHovered: Bool
    var satisfiedHas: Set<Int>
}

struct ElementData {
    var tag: String
    var attributes: [String: String]
    var isChecked: Bool
}

struct TextData {
    var text: String
}
```

Each `struct` stays at four or fewer stored properties. `DOMFlags` has exactly four; `DOMBase` has exactly four.

Cold state moves out of every element:

```swift
struct DOMSideTables {
    var images: ImageTable
    var embeds: EmbedTable
    var canvases: CanvasTable
    var scrollOffsets: [NodeID: CGFloat]
}

struct ImageTable {
    var images: [NodeID: CGImage]
    var backgrounds: [NodeID: CGImage]
    var backgroundSources: [NodeID: String]
}

struct EmbedTable {
    var frames: [NodeID: Frame]
    var frameSources: [NodeID: String]
}

struct CanvasTable {
    var contexts: [NodeID: CanvasRenderingContext2D]
}
```

The tree:

```swift
@MainActor
final class DOMTree {
    private(set) var nodes: [DOMNode?]
    private(set) var root: NodeID
    private(set) var side: DOMSideTables
    weak var layoutTree: LayoutTree?
}
```

`root` is always `NodeID(raw: 0)`. `layoutTree` is a weak back-reference so `DOMRef.layout` can find the current primary layout node without putting a layout pointer in every DOM node. `LayoutTree` owns `DOMTree` strongly, so there is no cycle.

Views:

```swift
@MainActor
struct DOMRef {
    let id: NodeID
    unowned let dom: DOMTree
}

@MainActor
struct ElementRef {
    let ref: DOMRef
}

@MainActor
struct TextRef {
    let ref: DOMRef
}
```

`DOMRef` has two stored properties; the kind-specific views have one. Views carry no data. They exist because 120 call sites read `el.tag`, `el.attributes`, and `text.text`; forcing every one of them through `DOMTree` methods makes the migration unreadable without making the model more data-oriented.

### Layout storage

```swift
enum LayoutKind {
    case document(DocumentData)
    case block(BlockData)
    case line(LineData)
    case text(TextData)
    case embed(EmbedData)
}

struct LayoutNode {
    var kind: LayoutKind
    var dom: NodeID
    var links: LayoutLinks
    var state: LayoutState
}

struct LayoutLinks {
    var parent: LayoutID?
    var previous: LayoutID?
    var children: [LayoutID]
    var versions: LinkVersions
}

struct LinkVersions {
    var children: UInt64
    var previous: UInt64
}

struct LayoutState {
    var fields: LayoutFieldStore
    var hasDirtyDescendants: Bool
}
```

`LayoutNode` has exactly four stored properties. `LayoutLinks` has four.

```swift
@MainActor
final class LayoutTree {
    private(set) var nodes: [LayoutNode?]
    let dom: DOMTree
    private(set) var primaryByNode: [NodeID: LayoutID]
    var dependencies: DependencyIndex
}
```

The root document is `LayoutID(raw: 0)`, created in `LayoutTree.init(dom:)` and never removed. Nodes are append-only; removing a subtree writes `nil`. IDs are never reused, so a stale `LayoutID` cannot silently point at a different node.

```swift
@MainActor
struct LayoutRef {
    let id: LayoutID
    unowned let tree: LayoutTree
}
```

`LayoutRef` replaces `any LayoutObject` at call sites. It is a two-property view, not a class hierarchy. `node`, `parent`, `children`, `x`, `width`, `zoom`, and the `*Field` accessors remain, so the layout algorithms keep their shape:

```swift
extension LayoutRef {
    var node: DOMRef {
        DOMRef(id: tree.node(id).dom, dom: tree.dom)
    }

    var parent: LayoutRef? {
        guard let parent = tree.node(id).links.parent else { return nil }
        return LayoutRef(id: parent, tree: tree)
    }

    var children: [LayoutRef] {
        tree.node(id).links.children.map { LayoutRef(id: $0, tree: tree) }
    }

    var x: CGFloat {
        get { tree.node(id).state.fields.geometry.origin.x }
        set { tree.setField(.x, newValue, for: id) }
    }

    var kind: LayoutKind {
        tree.node(id).kind
    }
}
```

### Layout payloads

The subclasses become data:

```swift
struct DocumentData {
    var pageZoom: CGFloat
}

struct BlockData {
    var content: BlockContent
    var scroll: BlockScroll
    var paint: BlockPaint
    var changes: BlockChanges
}

struct BlockContent {
    var extraNodes: [NodeID]
    var inlineItems: [InlineItem]
    var inlineObjects: [Int: LayoutID]
    var inlineLinePlan: [[Int]]?
}

struct BlockScroll {
    var offset: CGFloat
    var contentHeight: CGFloat
}

struct BlockPaint {
    var cache: PaintCache
    var style: BlockStyle?
    var styleRevision: UInt64
}

struct BlockChanges {
    var childChanges: [BlockChildChange]
    var declaredHeightChildren: [LayoutID]
}
```

```swift
struct LineData {
    var content: LineContent
    var paint: LinePaint
    var placement: LinePlacement
}

struct LineContent {
    var centered: Bool
    var hasEmbed: Bool
}

struct LinePaint {
    var cache: LinePaintCache
    var generation: UInt
    var paintedChildCount: Int
}

struct LinePlacement {
    var inlineYOffset: CGFloat
    var childOriginY: CGFloat?
    var declaredInlineChildCount: Int
}
```

```swift
struct TextData {
    var word: String
    var display: String?
    var fontOverride: BrowserFont?
    var metrics: TextMetrics
}

struct TextMetrics {
    var width: CGFloat
    var whiteSpace: WhiteSpaceMode
}
```

```swift
enum EmbedData {
    case image(ImageData)
    case input
    case button(ButtonData)
    case iframe
    case canvas
}

struct ImageData {
    var imageHeight: CGFloat
}

struct ButtonData {
    var cursorX: CGFloat
}
```

### Field storage

`LayoutFieldStore` becomes a value struct with grouped storage. The bit layout stays; only the owner changes.

```swift
struct LayoutFieldStore {
    var geometry: GeometryFields
    var inlineText: InlineTextFields
    var state: FieldState
}

struct GeometryFields {
    var origin: Point
    var size: CGSize
    var zoom: CGFloat
}

struct InlineTextFields {
    var font: BrowserFont
    var ascent: CGFloat
    var descent: CGFloat
    var inlineContent: UInt64
}

struct FieldState {
    var usedBits: UInt16
    var dirtyBits: UInt16
    var frozenBits: UInt16
}
```

`children` and `previous` are no longer values in the field store. They live in `LayoutLinks`; `LayoutField.children` and `.previous` remain only as dirty/version keys. `LayoutTree.value(of:)` reads the link version for those two keys.

### Invalidation

One reverse index for the whole tree, built from the static input table.

```swift
struct DependencyIndex {
    private var dependents: [FieldKey: [FieldKey]]
}
```

```swift
enum LayoutInputTable {
    static func inputs(
        for id: LayoutID,
        field: LayoutField,
        in tree: LayoutTree
    ) -> [FieldKey] {
        switch (tree.node(id).kind, field) {
        case (.document, .width):
            return [.layout(id, .zoom)]

        case (.block, .width):
            let dom: NodeID = tree.node(id).dom
            return [
                parentKey(id, .width, in: tree),
                .layout(id, .zoom),
                .style(dom, .paddingLeft),
                .style(dom, .paddingRight),
                .style(dom, .width),
            ]

        case (.line, .y):
            let dom: NodeID = tree.node(id).dom
            return [
                parentKey(id, .y, in: tree),
                .style(dom, .top),
                .style(dom, .marginTop),
            ]

        default:
            return []
        }
    }
}
```

The table is the only place that knows an edge. Initializers stop constructing handles. The reverse index is rebuilt once at the start of a layout pass and after a structural change; a field write walks it once.

## Decisions

### D1. Separate `NodeID` and `LayoutID`

**Option A — one `NodeID` for both.** Reject. A DOM node can own several layout nodes (anonymous block for an inline run, one line node, one text node per word). One layout node can own several DOM nodes (`extraNodes`, run-in `h6`). Collapsing them makes the arena index ambiguous.

**Option B — `NodeID` + `LayoutID` + `FieldKey`.** Recommend. The cost is one extra value type; the benefit is that every cache and every invalidation edge states which kind of owner it means.

### D2. Arena plus views, not one tagged class

**Option A — one `final class LayoutNode` with a `kind` enum.** Removes the hierarchy and casts, but keeps pointer identity, per-node allocation, and a DOM->layout class reference. The invalidation table would still key by object address.

**Option B — arena of tagged structs plus `DOMRef` / `LayoutRef` views.** Recommend. The data is contiguous, identity is a value, and caches key by `NodeID` / `LayoutID`. The views cost one small struct copy per node visit, not one per field access.

This is the same trade the display-list refactor made: one flat `[DisplayOp]` plus data, not a tree of objects. The views are the `DisplayOp`-style convenience layer, not a second representation.

### D3. Layout first, DOM second

**Option A — DOM arena first.** The parser, JS bridge, selectors, accessibility, and every layout read move at once. That is the largest coupled change in the repo.

**Option B — layout arena first over a `DOMTree` adapter.** Recommend. Phase A introduces `DOMTree` as an adapter over the existing classes and exposes `DOMRef` / `ElementRef` / `TextRef`. Layout then ports to `LayoutRef` and IDs without touching the parser or JS bridge. Phase C swaps the adapter internals; layout call sites do not change because they already use `DOMRef`.

The adapter is temporary. It must be deleted in C3, not left as a second DOM representation.

### D4. Cold element state goes to side tables

**Option A — keep all fields in `ElementData`.** Reject. Every element pays for `image`, `backgroundImage`, `backgroundSource`, `frame`, `frameSource`, `canvasContext`, and `scrollOffsetY`, even a `<span>`.

**Option B — side tables keyed by `NodeID`.** Recommend. Group by feature: images, embeds, canvases, scroll. Only nodes that use a feature have an entry.

### D5. Invalidation: one reverse index, not pull/version

The findings recommend pull/version for a toy engine. This codebase already has dirty bits and push propagation; changing to pull would rewrite `layoutNeeded` semantics, `hasDirtyDescendants`, and the incremental tests at the same time as the arena.

**Option A — static input table + one reverse index (recommended).**

- Keep `dirtyBits`, `usedBits`, `hasDirtyDescendants`.
- Build `DependencyIndex` from `LayoutInputTable` at the start of a layout pass.
- A field write increments its version, marks dependents dirty through the index, and marks ancestors dirty.
- Reads are direct; no read-time mutation.

Closest to current behavior; existing tests remain meaningful.

**Option B — pull/version checks.**

- Each field stores a version.
- `layoutNeeded` compares cached input versions.
- No reverse index.

Simpler storage, but every layout pass must check versions for every used field, and `hasDirtyDescendants` no longer explains why a node is visited. Choose this only if profiling shows the reverse index is the bottleneck.

### D6. `StyleFields` stays a class

Item 6 owns the shared mutable graph. This plan gives `StyleFields` an owner `NodeID` and removes its per-key `dependents` dictionary in Phase D. It does not turn it into a value type.

### D7. Tests compare IDs, not object addresses

`ObjectIdentifier(layoutObject)` and `===` disappear. Tests compare `LayoutID` and `NodeID`; the guarantees are the same (an unchanged node keeps its ID), and the tests stop depending on allocation identity.

## File map

### New files

| File | Holds |
|---|---|
| `Sources/Engine/Core/NodeID.swift` | `NodeID` |
| `Sources/Engine/Layouts/LayoutID.swift` | `LayoutID` |
| `Sources/Engine/Layouts/LayoutNode.swift` | `LayoutNode`, `LayoutLinks`, `LinkVersions`, `LayoutState` |
| `Sources/Engine/Layouts/LayoutKind.swift` | `LayoutKind` and payload enums |
| `Sources/Engine/Layouts/LayoutTree.swift` | arena, accessors, allocation, removal |
| `Sources/Engine/Layouts/LayoutRef.swift` | `LayoutRef` view and geometry accessors |
| `Sources/Engine/Layouts/BlockData.swift` | `BlockData` and its groups |
| `Sources/Engine/Layouts/LineData.swift` | `LineData` and its groups |
| `Sources/Engine/Layouts/TextData.swift` | `TextData`, `TextMetrics` |
| `Sources/Engine/Layouts/EmbedData.swift` | `EmbedData`, `ImageData`, `ButtonData` |
| `Sources/Engine/Layouts/DocumentData.swift` | `DocumentData` |
| `Sources/Engine/Layouts/DocumentLayoutPass.swift` | document pass over `LayoutTree` |
| `Sources/Engine/Layouts/BlockLayoutPass.swift` | block pass and child builder |
| `Sources/Engine/Layouts/LineLayoutPass.swift` | line pass |
| `Sources/Engine/Layouts/TextLayoutPass.swift` | text pass |
| `Sources/Engine/Layouts/EmbedLayoutPass.swift` | embed pass |
| `Sources/Engine/Layouts/LayoutPaintPass.swift` | hit-test, absolute bounds, paint scope, self rect |
| `Sources/Engine/Layouts/LayoutInputTable.swift` | static input edges (Phase D) |
| `Sources/Engine/Core/DependencyIndex.swift` | reverse index (Phase D) |
| `Sources/Engine/Core/FieldKey.swift` | `FieldKey` |
| `Sources/Engine/Parsing/DOMNode.swift` | rewritten tagged DOM data |
| `Sources/Engine/Parsing/DOMKind.swift` | `DOMKind` |
| `Sources/Engine/Parsing/DOMBase.swift` | `DOMBase`, `DOMState`, `DOMFlags` |
| `Sources/Engine/Parsing/ElementData.swift` | `ElementData` |
| `Sources/Engine/Parsing/TextData.swift` | `TextData` |
| `Sources/Engine/Parsing/DOMTree.swift` | DOM arena, mutation API |
| `Sources/Engine/Parsing/DOMRef.swift` | `DOMRef` view |
| `Sources/Engine/Parsing/ElementRef.swift` | `ElementRef` view |
| `Sources/Engine/Parsing/TextRef.swift` | `TextRef` view |
| `Sources/Engine/Parsing/DOMSideTables.swift` | `DOMSideTables`, `ImageTable`, `EmbedTable`, `CanvasTable` |

### Deleted files

| File | Replaced by |
|---|---|
| `Sources/Engine/Display/NodeKey.swift` | `NodeID` |
| `Sources/Engine/Core/FieldRef.swift` | `FieldKey` + `DependencyIndex` |
| `Sources/Engine/Core/FieldDependencyKey.swift` | `FieldKey` |
| `Sources/Engine/Layouts/LayoutObject.swift` | `LayoutRef` + `LayoutTree` |
| `Sources/Engine/Layouts/LayoutFieldHandle.swift` | direct field access |
| `Sources/Engine/Layouts/LayoutFieldStore.swift` | rewritten value store |
| `Sources/Engine/Layouts/LayoutFieldAccess.swift` | grouped field storage |
| `Sources/Engine/Layouts/DocumentLayout.swift` | `DocumentLayoutPass.swift` |
| `Sources/Engine/Layouts/BlockLayout.swift` | `BlockLayoutPass.swift` |
| `Sources/Engine/Layouts/LineLayout.swift` | `LineLayoutPass.swift` |
| `Sources/Engine/Layouts/TextLayout.swift` | `TextLayoutPass.swift` |
| `Sources/Engine/Layouts/EmbedLayout.swift` | `EmbedLayoutPass.swift` |
| `Sources/Engine/Layouts/ImageLayout.swift` | `EmbedData.image` |
| `Sources/Engine/Layouts/InputLayout.swift` | `EmbedData.input` |
| `Sources/Engine/Layouts/ButtonLayout.swift` | `EmbedData.button` |
| `Sources/Engine/Layouts/IframeLayout.swift` | `EmbedData.iframe` |
| `Sources/Engine/Layouts/CanvasLayout.swift` | `EmbedData.canvas` |
| `Sources/Engine/Layouts/InlineLayoutItem.swift` | `LayoutKind` switch |
| `Sources/Engine/Layouts/InlinePlacement.swift` | `LayoutTree` line builder |
| `Sources/Engine/Style/StyleFieldRef.swift` | `FieldKey.style` |
| `Sources/Engine/Parsing/DOMNode.swift` (old classes) | rewritten file |

### Modified files (high-level)

| Area | Files |
|---|---|
| Frame lifecycle | `Core/Frame.swift`, `Core/FrameParent.swift`, `Core/FrameDisplay.swift`, `Core/FrameDisplayOutput.swift`, `Core/BrowserTab.swift`, `Core/Browser.swift` |
| Paint | `Display/PaintTree.swift`, `Display/PaintSession.swift`, `Display/EffectScope.swift`, `Display/DisplayOp.swift`, `Display/PaintEffectStyle.swift`, `Display/FocusRing.swift`, `Display/DrawCursor.swift` |
| Raster hand-off | `Raster/RasterScene.swift`, `Raster/LayerEffect.swift`, `Display/DisplaySignature.swift` |
| Style | `Style/ApplyStyle.swift`, `Style/StyleCascade.swift`, `Style/StyleInvalidation.swift`, `Style/InlineStyle.swift`, `Style/TextDirectionResolver.swift`, all `Style/Selectors/*.swift` |
| Parsing | `Parsing/HTMLParser.swift`, `Parsing/HTMLSyntaxHighlighter.swift` |
| JS / canvas | `Platform/JSRuntime.swift`, `Platform/CanvasBridge.swift` |
| Accessibility | `Accessibility/AccessibilityNode.swift`, `Accessibility/FrameAccessibilityNode.swift`, `Accessibility/AccessibilityBounds.swift` |
| Other core | `Core/FocusNavigation.swift`, `Core/ImageLoading.swift`, `Core/TreeTraversal.swift`, `Core/BrokenImage.swift` |
| Tests | `BlockLayoutTests`, `EmbedLayoutTests`, `GeometryInvalidationTests`, `InlineTextLayoutTests`, `LayoutDependencyTests`, `LayoutIdempotenceTests`, `LayoutInvalidationTests`, `LayoutOracle`, `LayoutSkippingTests`, `LayoutTestPage`, `PaddingLayoutTests`, `PaintCacheTests`, `PaintCullingTests`, `AppendChildTests`, `InsertBeforeTests`, `ReplaceChildrenTests`, `DOMNodeTests`, `HTMLParserTests`, `HoverTests`, `ViewportResizeTests` |

## Steps

Each step below ends with `swift build` green and `swift test` green unless marked as a cutover gate. The cutover steps (B2, C2) are large but mechanical: the data model is already in place, and the old files are deleted in the following step.

### Step A0 — Pin the baseline

- Capture the three screenshots listed in **Baseline**.
- Record the current test count (`189`) and the current `git status`.
- Do not start A1 on a dirty tree.

**Gate:** screenshots exist and `swift test` passes.

### Step A1 — Add `NodeID`, `LayoutID`, and the DOM adapter

**Files**

- New: `Core/NodeID.swift`, `Layouts/LayoutID.swift`, `Parsing/DOMTree.swift`, `Parsing/DOMRef.swift`, `Parsing/ElementRef.swift`, `Parsing/TextRef.swift`.
- Modify: `Core/Frame.swift`, `Core/BrowserTab.swift`, `Parsing/HTMLParser.swift`, `Platform/JSRuntime.swift`.

**Change**

Add the value IDs first; no engine behavior changes.

```swift
// Sources/Engine/Core/NodeID.swift
struct NodeID: Hashable, Sendable {
    let raw: UInt32
}

// Sources/Engine/Layouts/LayoutID.swift
struct LayoutID: Hashable, Sendable {
    let raw: Int
}
```

`DOMTree` starts as an adapter over the existing classes. It owns the ID maps and the root. The storage struct keeps the class's stored-property count at four.

```swift
@MainActor
final class DOMTree {
    private struct Index {
        var nodes: [NodeID: any DOMNode] = [:]
        var ids: [ObjectIdentifier: NodeID] = [:]
    }

    private var index: Index
    private var next: UInt32
    private(set) var root: NodeID

    init(root: any DOMNode) { … }

    func id(of node: any DOMNode) -> NodeID
    func node(_ id: NodeID) -> (any DOMNode)?
    func register(_ node: any DOMNode) -> NodeID
    func adopt(_ root: any DOMNode)
}
```

`DOMTree(root:)` calls `adopt` recursively, so every node in a parsed or test-built tree gets an ID and a stamped style owner before layout reads it.

`register` also stamps the style owner, so a `StyleFieldRef` can form a `FieldKey` before the DOM arena exists. Add one stored property to `StyleFields`:

```diff
 nonisolated final class StyleFields: FieldOwner {
+    private(set) var owner: NodeID?
     private var storage: StyleStorage = StyleStorage()
```

```diff
     func register(_ node: any DOMNode) -> NodeID {
         let id: NodeID = allocate()
         index.nodes[id] = node
         index.ids[ObjectIdentifier(node)] = id
+        node.style.owner = id
         return id
     }
```

`Frame` keeps a `DOMTree` beside the old root. The existing `nodes` call sites keep their class type until C2, so A1 stays build-green:

```diff
-    var nodes: any DOMNode = Element(tag: "html", attributes: [:], parent: nil)
+    var dom: DOMTree = DOMTree(root: Element(tag: "html", attributes: [:], parent: nil))
+    var nodes: any DOMNode {
+        get { dom.node(dom.root)! }
+        set { dom = DOMTree(root: newValue) }
+    }
```

`HTMLParser` still returns `any DOMNode` in this step. `Frame` wraps it and adopts the subtree:

```diff
-            nodes = profiler.measure("load.parse", {
-                HTMLParser(body: body).parse()
-            })
+            let parsed: any DOMNode = profiler.measure("load.parse", {
+                HTMLParser(body: body).parse()
+            })
+            dom = DOMTree(root: parsed)
```

`JSRuntime` registers nodes it creates:

```diff
-            let elt: Element = Element(tag: tag, attributes: [:], parent: nil)
+            let elt: Element = Element(tag: tag, attributes: [:], parent: nil)
+            _ = frame.dom.register(elt)
```

**Views**

`DOMRef`, `ElementRef`, and `TextRef` forward to the adapter. They are the stable API that layout will use in A2 and that the DOM arena will keep in C2.

```swift
@MainActor
struct DOMRef {
    let id: NodeID
    unowned let dom: DOMTree
}

extension DOMRef {
    var style: StyleFields { dom.node(id)!.style }
    var parent: DOMRef? { … }
    var children: [DOMRef] { … }
    var element: ElementRef? { … }
    var text: TextRef? { … }
}
```

`ElementRef` exposes `tag`, `attributes`, `isChecked`, and the side-table accessors. In A1 it forwards to the class; in C2 it forwards to `ElementData`.

**Tests**

No test changes. The adapter is unused by existing engine code; `Frame.nodes` still returns `any DOMNode`, and every old call site keeps that type until C2. `DOMRef` is only used by layout in A2. To keep the build green, add a temporary `raw` bridge for the few identity comparisons that still need the class:

```swift
extension DOMRef {
    var raw: any DOMNode { dom.node(id)! }
}
```

**Verification**

```sh
swift build && swift test
```

### Step A2 — Route layout's DOM reads through `DOMRef`

**Files**

- Modify: `Layouts/LayoutObject.swift`, `BlockLayout.swift`, `BlockStyle.swift`, `LineLayout.swift`, `TextLayout.swift`, `EmbedLayout.swift`, `DocumentLayout.swift`, `ImageLayout.swift`, `InputLayout.swift`, `ButtonLayout.swift`, `IframeLayout.swift`, `CanvasLayout.swift`, `InlineTextRun.swift`, `InlineItem.swift`, `InlinePlacement.swift`, `LayoutFieldAccess.swift`, `LayoutMetrics.swift`.
- Modify: `Display/PaintTree.swift`, `Display/DisplayOp.swift`, `Display/PaintEffectStyle.swift`, `Display/DrawCursor.swift`, `Display/FocusRing.swift`.
- Modify: `Core/Frame.swift`, `Core/LayoutInvalidation.swift`, `Core/FocusNavigation.swift`, `Core/TreeTraversal.swift`, `Accessibility/AccessibilityNode.swift`, `Accessibility/FrameAccessibilityNode.swift`.
- Modify: `Platform/BrowserFont.swift`, `Style/InlinePlacement.swift`, `Style/TextDirectionResolver.swift`.

**Change**

`LayoutObject.node` becomes `DOMRef`. This is the step that deletes the `as? Element` / `as? TextNode` checks from layout and paint, before the arena exists. The class hierarchy stays for now, so the diff is mechanical and testable.

```diff
 @MainActor
 protocol LayoutObject: AnyObject, FieldOwner {
-    var node: any DOMNode { get }
+    var node: DOMRef { get }
     var parent: (any LayoutObject)? { get }
     var fields: LayoutFieldStore { get }
     var hasDirtyDescendants: Bool { get set }
```

Call sites:

```diff
-        if let el = node as? Element, el.tag == "li" {
+        if let el = node.element, el.tag == "li" {
```

```diff
-        if node is TextNode { return "inline" }
+        if node.text != nil { return "inline" }
```

```diff
-        if let text = leaf as? TextNode {
+        if let text = leaf.text {
             addTextNode(text, into: &items)
-        } else if let el = leaf as? Element {
+        } else if let el = leaf.element {
```

`ElementRef` owns the element-only reads:

```swift
extension ElementRef {
    var tag: String { … }
    var attributes: [String: String] { get set }
    var isChecked: Bool { get set }
    var image: CGImage? { get set }
    var backgroundImage: CGImage? { get set }
    var backgroundImageSource: String? { get set }
    var frame: Frame? { get set }
    var frameSource: String? { get set }
    var canvasContext: CanvasRenderingContext2D? { get set }
    var scrollOffsetY: CGFloat { get set }
}
```

`TextRef` owns text reads and appends:

```swift
extension TextRef {
    var text: String { … }

    @MainActor
    func append(_ suffix: String) { … }
}
```

The old constructors assign `node.layoutObject = self`. Keep that working through a temporary forwarding property:

```swift
extension DOMRef {
    var layoutObject: (any LayoutObject)? {
        get { raw.layoutObject }
        set { raw.layoutObject = newValue }
    }
}
```

`raw` and `layoutObject` are deleted in C3, when `LayoutTree.primaryByNode` is the only mapping.

`InlineItem` and `InlineTextRun` change their payload types:

```diff
-    case embed(Element)
+    case embed(ElementRef)

 struct InlineTextRun {
-    let node: any DOMNode
+    let node: DOMRef
     let font: BrowserFont
     let whiteSpace: WhiteSpaceMode
     let isAbbr: Bool
 }
```

`Frame`, `LayoutInvalidation`, accessibility, and focus still compare layout nodes to class nodes. Use the temporary `DOMRef.raw` bridge only at those seams:

```diff
-        let objs: [any LayoutObject] = treeToList(doc).filter({ $0.node === elt || $0.node.parent === elt })
+        let objs: [any LayoutObject] = treeToList(doc).filter({
+            $0.node.raw === elt || $0.node.parent?.raw === elt
+        })
```

```diff
-            doc = DocumentLayout(node: nodes)
+            doc = DocumentLayout(node: DOMRef(id: dom.root, dom: dom))
```

`StyleInvalidation` still takes classes. Do not add new `as?` checks; `.raw` is the only bridge allowed in A2. It disappears in C3.

**Verification**

```sh
swift build && swift test
```

Every `layout.*` and `paint.*` profiler counter must match A0. If `layout.children.rebuilt` changes, the `DOMRef` conversion changed an identity comparison (`===` became value equality or vice versa); fix it before continuing.

### Step A3 — Replace node-address identity with `NodeID`

**Files**

- Delete: `Display/NodeKey.swift`.
- Modify: `Core/Frame.swift`, `Core/FrameDisplay.swift`, `Core/FrameDisplayOutput.swift`, `Core/Browser.swift`, `Display/EffectScope.swift`, `Display/PaintSession.swift`, `Raster/RasterScene.swift`, `Raster/LayerEffect.swift`.

**Change**

`NodeKey` is exactly the old identity; its call sites become `NodeID`.

```diff
-public struct NodeKey: Hashable {
-    let raw: ObjectIdentifier
-
-    init(_ node: any DOMNode) {
-        self.raw = ObjectIdentifier(node)
-    }
-}
+typealias NodeKey = NodeID
```

After the call sites compile, remove the alias and delete it. The important fixes:

```diff
-    private var compositedUpdates: [NodeKey: EffectUpdate] = [:]
+    private var compositedUpdates: [NodeID: EffectUpdate] = [:]
```

```diff
-                            compositedUpdates[NodeKey(node)] = EffectUpdate(
+                            compositedUpdates[dom.id(of: node)] = EffectUpdate(
```

`StyleCascade`, `JSRuntime`, and `Browser.liveRegionTexts` keep their `ObjectIdentifier` maps in this step. They still hold class nodes; they switch to `NodeID` in C2, when every node has an arena ID. `Frame` hover sets do the same.

**Why this step is separate**

If the layout arena is built while `NodeKey` is still `ObjectIdentifier`, every composition cache and effect scope has to be rewritten twice. Doing identity first keeps the arena port about storage and dispatch only. It also means A2 has already put a `DOMRef` on every layout node, so `obj.node.id` is available wherever paint creates an effect scope.

**Verification**

```sh
swift build && swift test
```

Screenshot check: paint output must be byte-identical to A0.

### Step B1 — Add the layout arena types

**Files**

- New: `Layouts/LayoutNode.swift`, `LayoutKind.swift`, `LayoutTree.swift`, `LayoutRef.swift`, `BlockData.swift`, `LineData.swift`, `TextData.swift`, `EmbedData.swift`, `DocumentData.swift`.
- Rewrite: `Layouts/LayoutFieldStore.swift`.

**Change**

Add the model from **End state**. It is not wired into the engine yet. The point is to make the target shapes compile and to write the arena unit tests before the cutover.

`LayoutTree` allocates by appending:

```swift
@MainActor
final class LayoutTree {
    private(set) var nodes: [LayoutNode?] = []
    let dom: DOMTree
    private(set) var primaryByNode: [NodeID: LayoutID] = [:]
    var dependencies: DependencyIndex = DependencyIndex()

    init(dom: DOMTree) {
        self.dom = dom
        dom.layoutTree = self
        self.nodes.reserveCapacity(1024)
        let document: LayoutID = append(
            kind: .document(DocumentData(pageZoom: 1)),
            dom: dom.root,
            parent: nil,
            previous: nil
        )
        assert(document.raw == 0)
    }

    func append(
        kind: LayoutKind,
        dom: NodeID,
        parent: LayoutID?,
        previous: LayoutID?
    ) -> LayoutID { … }

    func removeSubtree(_ id: LayoutID) { … }

    func node(_ id: LayoutID) -> LayoutNode { … }

    func children(of id: LayoutID) -> [LayoutID] { … }

    func setChildren(_ children: [LayoutID], of id: LayoutID) { … }

    func isDirty(_ field: LayoutField, at id: LayoutID) -> Bool { … }

    func markField(_ field: LayoutField, at id: LayoutID) { … }

    func setField(_ field: LayoutField, _ value: CGFloat, for id: LayoutID) { … }
}
```

B1 also adds `FieldKey` and a `DependencyIndex` that starts with `add` / `remove` / `replace` / `mark` so `LayoutTree` compiles. D1 adds `rebuild(from:)` from the static input table; until then the temporary handle API pushes edges into the index.

B1 adds the weak back-reference that A1 could not declare yet as a stored property on `DOMTree`:

```swift
weak var layoutTree: LayoutTree?
```

`DOMRef` gains the layout lookup that A1 could not compile yet:

```swift
extension DOMRef {
    var layout: LayoutRef? {
        guard let layout = dom.layoutTree?.primaryLayout(for: id) else { return nil }
        return LayoutRef(id: layout, tree: dom.layoutTree!)
    }
}
```

`LayoutRef` keeps the old property names:

```swift
extension LayoutRef {
    var children: [LayoutRef] { … }
    var x: CGFloat { get set }
    var y: CGFloat { get set }
    var width: CGFloat { get set }
    var height: CGFloat { get set }
    var zoom: CGFloat { get set }
    var font: BrowserFont { get set }
    var selfRect: Rect { … }
}
```

`LayoutFieldStore` moves from a class to a value:

```diff
-@MainActor
-final class LayoutFieldStore {
-    var x: CGFloat = 0
-    var y: CGFloat = 0
-    var width: CGFloat = 0
-    var height: CGFloat = 0
-    var zoom: CGFloat = 1
-    var children: [any LayoutObject] = []
-    var previous: (any LayoutObject)? = nil
-    var font: BrowserFont = inlineDefaultFont
-    var ascent: CGFloat = 0
-    var descent: CGFloat = 0
-    var inlineContent: UInt64 = 0
-    private var usedBits: UInt16 = 0
-    private var dirtyBits: UInt16 = LayoutField.allMask
-    private var frozenBits: UInt16 = 0
-    private var dependents: [LayoutField: [FieldDependencyKey: FieldRef]] = [:]
+@MainActor
+struct LayoutFieldStore {
+    var geometry: GeometryFields
+    var inlineText: InlineTextFields
+    var state: FieldState
+}
```

**Tests**

Add a small `LayoutTreeTests`:

- `append` gives unique, monotonic `LayoutID`s.
- `removeSubtree` leaves a hole; the ID is not reused.
- `setChildren` updates parent links and increments `links.versions.children`.

**Verification**

```sh
swift build && swift test
```

### Step B2 — Cut layout over to the arena

**Files**

- Modify: `Core/Frame.swift`, `Core/LayoutInvalidation.swift`, `Core/FrameParent.swift`, `Core/BrowserTab.swift`, `Display/PaintTree.swift`, `Accessibility/AccessibilityNode.swift`, `Accessibility/FrameAccessibilityNode.swift`, `Core/FocusNavigation.swift`, `Core/TreeTraversal.swift`, `Core/ImageLoading.swift`.
- Rewrite: all `Layouts/*Layout.swift` files as pass files.
- Move: `LayoutObject` helpers into `LayoutRef.swift` / `LayoutTree.swift`.
- Delete: `InlinePlacement.swift`, `InlineLayoutItem.swift`.

**Change**

One cutover commit. The new model is already tested; this step changes the engine to use it and updates tests in the same commit. Do not park between B2 and B3.

`Frame`:

```diff
-    private var documentValue: DocumentLayout?
+    private var documentValue: LayoutTree?
@@
-    var document: DocumentLayout? {
+    var document: LayoutTree? {
```

```diff
-            let doc: DocumentLayout
-            if let existing = document, existing.node === nodes, browser?.forceFullLayout != true {
+            let doc: LayoutTree
+            if let existing = document, existing.dom === dom, browser?.forceFullLayout != true {
                 doc = existing
             } else {
-                doc = DocumentLayout(node: nodes)
+                doc = LayoutTree(dom: dom)
                 scrollTargetsValid = false
             }
-            doc.layout(
+            doc.layoutDocument(
                 availableWidth: frameWidth,
                 zoom: 1.0,
                 pageZoom: pageZoom
             )
```

Viewport and zoom invalidation stop reaching into fields:

```diff
     var frameWidth: CGFloat {
         didSet {
             if oldValue != frameWidth {
-                document?.widthField.mark()
+                document?.markDocumentGeometryDirty()
             }
         }
     }
```

```diff
     func setNeedsViewportResize() {
-        document?.widthField.mark()
-        document?.zoomField.mark()
+        document?.markDocumentGeometryDirty()
         if !mediaMatches.isEmpty, !flippedMediaQueries(currentMedia()).isEmpty {
             invalidateStyle(fromViewport: true)
         } else {
             setNeedsLayout()
         }
     }
```

`DocumentLayout` becomes the document pass:

```swift
extension LayoutTree {
    func layoutDocument(
        availableWidth: CGFloat,
        zoom: CGFloat,
        pageZoom: CGFloat
    ) {
        let root: LayoutRef = LayoutRef(id: LayoutID(raw: 0), tree: self)
        guard root.layoutNeeded() else { return }

        root.zoom = zoom
        if case .document(var data) = root.kind {
            data.pageZoom = pageZoom
            setDocumentData(data, at: root.id)
        }

        let child: LayoutRef
        if let existing = root.children.first, existing.kind.isBlock {
            child = existing
        } else {
            child = makeBlock(
                dom: root.node.id,
                parent: root.id,
                previous: nil
            )
        }
        root.setChildren([child.id])

        let rootZoom: CGFloat = root.zoom
        root.width = availableWidth - 2 * HSTEP * rootZoom
        root.x = HSTEP * rootZoom
        root.y = VSTEP * rootZoom

        child.layout()
        root.height = child.boxHeight()
    }
}
```

`LayoutRef.layout()` dispatches once:

```swift
extension LayoutRef {
    func layout() {
        switch kind {
        case .document:
            // The document pass is entered from Frame.layoutDocument,
            // because it owns the viewport width and page zoom.
            break
        case .block(let data):
            tree.layoutBlock(data, id: id)
        case .line(let data):
            tree.layoutLine(data, id: id)
        case .text(let data):
            tree.layoutText(data, id: id)
        case .embed(let data):
            tree.layoutEmbed(data, id: id)
        }
    }
}
```

Block child construction returns IDs, not objects:

```diff
-    private func rebuildBlockChildren() -> [any LayoutObject] {
+    private func rebuildBlockChildren() -> [LayoutID] {
         profiler.count("layout.children.rebuilt")
         childChanges.removeAll()
         var state: BlockChildBuild = BlockChildBuild()
         consumeBlockChildren(node.children, state: &state)
         finishBlockChildren(&state)
         return state.built
     }
```

```diff
-private struct BlockChildBuild {
-    var built: [any LayoutObject] = []
-    var previous: (any LayoutObject)?
-    var inlineRun: [any DOMNode] = []
-    var pendingRunIn: Element?
-}
+private struct BlockChildBuild {
+    var built: [LayoutID] = []
+    var previous: LayoutID?
+    var inlineRun: [NodeID] = []
+    var pendingRunIn: NodeID?
+}
```

```diff
-                    let next: BlockLayout = BlockLayout(node: child, parent: self, previous: state.previous)
+                    let next: LayoutID = tree.makeBlock(
+                        dom: child.id,
+                        parent: id,
+                        previous: state.previous
+                    )
```

The field-handle bridge during B2. `LayoutFieldHandle` cannot keep `unowned let owner: any LayoutObject` because layout owners are now structs. It becomes a value handle over `LayoutRef`; `FieldRef` becomes a key plus a mark closure, so a style owner never stores a class pointer:

```diff
-struct LayoutFieldHandle<Access: LayoutFieldAccess>: InvalidatableField {
-    unowned let owner: any LayoutObject
-    unowned let fields: LayoutFieldStore
-    let field: LayoutField
+struct LayoutFieldHandle<Access: LayoutFieldAccess>: InvalidatableField {
+    let owner: LayoutRef
+    let field: LayoutField
+
+    var key: FieldKey { .layout(owner.id, field) }
+    var ref: FieldRef {
+        FieldRef(key: key) { [tree = owner.tree, id = owner.id] in
+            tree.markField(field, at: id)
+        }
+    }
```

```diff
-struct FieldRef: InvalidatableField {
-    weak var owner: (any FieldOwner)?
-    let name: FieldName
+struct FieldRef: InvalidatableField {
+    let key: FieldKey
+    let markBody: () -> Void
+
+    var fieldName: String { key.description }
+    var ref: FieldRef { self }
+    func mark() { markBody() }
```

`LayoutFieldAccess` changes its static signatures from a store to the tree:

```diff
 protocol LayoutFieldAccess {
     associatedtype Value
-    static func read(_ store: LayoutFieldStore, _ field: LayoutField) -> Value
-    static func write(_ store: LayoutFieldStore, _ field: LayoutField, _ value: Value)
+    static func read(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField) -> Value
+    static func write(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField, _ value: Value)
     static func equals(_ lhs: Value, _ rhs: Value) -> Bool
 }
```

`StyleFields` keeps its per-key dependents dictionary during B2, but its keys are `FieldKey` instead of `FieldDependencyKey`:

```diff
-    func field(_ key: StyleProperty) -> StyleFieldRef {
-        return StyleFieldRef(owner: self, key: key)
-    }
+    func field(_ key: StyleProperty) -> StyleFieldRef {
+        return StyleFieldRef(owner: self, key: key, node: owner!)
+    }
```

`StyleFieldRef` continues to store those refs. D2 deletes the dictionary and moves the edges into `DependencyIndex`.

`InlinePlacement` becomes an arena builder owned by `LayoutTree`:

```swift
struct LineBuilder {
    let tree: LayoutTree
    let parent: LayoutID
    private(set) var lines: [LayoutID] = []
    private(set) var current: LayoutID?
    private(set) var children: [LayoutID] = []
    var cursorX: CGFloat = 0

    mutating func start() {
        current = tree.makeLine(
            dom: tree.node(parent).dom,
            parent: parent,
            previous: lines.last
        )
    }

    mutating func endLine() {
        guard let current else { return }
        tree.setChildren(children, of: current)
        lines.append(current)
        start()
    }
}
```

`PaintTree` becomes one switch over `LayoutKind`:

```diff
-    if let line = obj as? LineLayout, !window.intersects(line.selfRect()) {
+    switch obj.kind {
+    case .line:
+        guard window.intersects(obj.selfRect()) else { … }
+    case .text:
+        guard window.intersects(obj.selfRect()) else { … }
+    default:
+        break
+    }
```

```diff
-        if let block = obj as? BlockLayout {
+        if case .block = obj.kind {
             let origin: Point = Point(x: block.x, y: block.y)
```

The three block paint paths (scroll, hidden/clip, normal) become one `switch` with `case .block(let data)`. The `as? IframeLayout` branch becomes `case .embed(.iframe)`.

`LayoutInvalidation` stops casting:

```diff
-    static func childrenAppend(_ parent: any DOMNode, _ child: any DOMNode) {
-        guard let block = parent.layoutObject as? BlockLayout else {
+    static func childrenAppend(_ parent: DOMRef, _ child: DOMRef) {
+        guard let block = parent.layout?.kind.blockData else {
             childrenChanged(parent)
             return
         }
-        block.noteAppendedChildren([child])
+        block.noteAppendedChildren([child.id])
     }
```

`Frame` stores layout IDs, not layout objects:

```diff
-    private struct IframeTarget {
-        let rect: Rect
-        let iframe: IframeLayout
-    }
+    private struct IframeTarget {
+        let rect: Rect
+        let layout: LayoutID
+        let dom: NodeID
+    }
```

`Frame.scrollTo`, `scrollToFragment`, `rebuildScrollTargets`, `refreshScrollTargetRects`, `scrollableAncestor`, `click`, and `hover` all use `LayoutRef` / `NodeID`. They must not keep a `LayoutRef` across a layout pass because the tree can remove the ID; resolve it from the current `document` each time.

**Tests**

- `LayoutTestPage` stores `dom` and `document`, returns `ElementRef`.
- `firstLayout<T>` becomes `firstLayout(kind:)` or:
  - `firstBlock(in:)`
  - `firstText(in:)`
  - `firstLine(in:)`
  - `firstEmbed(in:)`
- Identity assertions use `LayoutID` and `NodeID`.
- `LayoutOracle` signatures walk `LayoutTree` by kind and `LayoutID`.

**Verification**

```sh
swift build && swift test
```

Screenshot and profiler gates:

- `www/ch16/exercise-16-2-protecting-layout-phases.html`: `layout.children.rebuilt` must not increase on a clean second pass.
- `www/ch16/exercise-16-3-append-child-move.html`: appended/moved child must keep surviving sibling IDs.
- `www/ch15/index.html`: iframe/canvas paint commands unchanged.

### Step B3 — Delete the old layout classes

**Files**

- Delete the old `*Layout.swift` class files and `LayoutObject.swift`, `LayoutFieldHandle.swift`, `LayoutFieldAccess.swift`, `InlinePlacement.swift`, `InlineLayoutItem.swift`.
- Keep the pass files and data files.

**Change**

No behavior change. The compiler is the check: if anything still references `BlockLayout`, `LineLayout`, `TextLayout`, `EmbedLayout`, `DocumentLayout`, `ImageLayout`, `InputLayout`, `ButtonLayout`, `IframeLayout`, or `CanvasLayout`, the type is still part of the engine.

Search gates:

```sh
grep -rn 'any LayoutObject\|as? BlockLayout\|as? LineLayout\|as? TextLayout\|as? EmbedLayout\|LayoutFieldHandle\|setDependencies\|read(notify' Sources/Engine
```

The only remaining hit should be `read(notify:)` in the temporary field bridge, which Phase D deletes.

**Verification**

```sh
swift build && swift test
```

### Step C1 — Add the DOM payload types

**Files**

- New: `Parsing/DOMKind.swift`, `DOMBase.swift`, `ElementData.swift`, `TextData.swift`, `DOMSideTables.swift`.

**Change**

Add the payload structs from **End state**. Do not add the final `DOMNode` struct or rewrite `DOMTree` yet: the old `DOMNode` protocol still owns that name, and the A1 `DOMTree` is still the adapter. C1 is the compile-and-test step for the data shapes only.

```swift
enum DOMKind {
    case element(ElementData)
    case text(TextData)
}

struct DOMBase {
    var parent: NodeID?
    var children: [NodeID]
    var style: StyleFields
    var state: DOMState
}

struct ElementData {
    var tag: String
    var attributes: [String: String]
    var isChecked: Bool
}

struct TextData {
    var text: String
}
```

`DOMSideTables` and its three feature tables are added here too. They are plain values; no engine path reads them until C2.

**Tests**

Add `DOMDataTests`:

- `ElementData` / `TextData` are value types; mutating a copy does not change the original.
- `DOMFlags` and `DOMBase` satisfy the four-property rule.
- `DOMSideTables` starts empty and stores an image/iframe/canvas/scroll entry by `NodeID`.
- `DOMKind` switches are exhaustive in the test helpers.

**Verification**

```sh
swift build && swift test
```

### Step C2 — Cut the DOM over to the arena

**Files**

- Modify: `Parsing/DOMNode.swift`, `Parsing/DOMTree.swift`, `Parsing/DOMRef.swift`, `Parsing/ElementRef.swift`, `Parsing/TextRef.swift`, `Parsing/HTMLParser.swift`.
- Modify: `Core/Frame.swift`, `Core/FrameParent.swift`, `Core/BrowserTab.swift`, `Core/Browser.swift`, `Platform/JSRuntime.swift`, `Platform/CanvasBridge.swift`, `Style/ApplyStyle.swift`, `Style/StyleCascade.swift`, `Style/StyleInvalidation.swift`, `Style/InlineStyle.swift`, `Style/TextDirectionResolver.swift`, all `Style/Selectors/*.swift`, `Accessibility/AccessibilityNode.swift`, `Accessibility/FrameAccessibilityNode.swift`, `Core/FocusNavigation.swift`, `Core/ImageLoading.swift`, `Core/TreeTraversal.swift`, `Core/BrokenImage.swift`, `Parsing/HTMLSyntaxHighlighter.swift`, `Display/PaintTree.swift`, `Display/DisplayOp.swift`, `Display/FocusRing.swift`.
- Delete: old `Element` / `TextNode` classes at the end of the step.

**Change**

One cutover commit. The payloads from C1 are in place; this step adds the final `DOMNode` struct, rewrites `DOMTree` from the adapter to `[DOMNode?]`, and changes every consumer plus the parser entry point.

`DOMNode` and the arena:

```swift
struct DOMNode {
    var kind: DOMKind
    var base: DOMBase
}
```

`DOMTree` gains the mutation API the parser and JS need:

```swift
extension DOMTree {
    func createElement(tag: String, attributes: [String: String]) -> NodeID
    func createText(_ text: String) -> NodeID
    func append(_ child: NodeID, to parent: NodeID)
    func insert(_ child: NodeID, before reference: NodeID, in parent: NodeID)
    func remove(_ child: NodeID, from parent: NodeID)
    func reparent(_ child: NodeID, to parent: NodeID)
    func setAttributes(_ attributes: [String: String], of id: NodeID)
    func setText(_ text: String, of id: NodeID)
    func appendText(_ suffix: String, to id: NodeID)
}
```

The parser builds directly:

```diff
-final class HTMLParser {
-    private let body: String
-    private var unfinished: [Element] = []
+final class HTMLParser {
+    private let body: String
+    private var dom: DOMTree
+    private var unfinished: [NodeID] = []
@@
-    func parse() -> any DOMNode {
+    func parse() -> DOMTree {
```

```diff
-        let node: Element = Element(tag: tagName, attributes: attributes, parent: parent)
-        parent.children.append(node)
+        let node: NodeID = dom.createElement(tag: tagName, attributes: attributes)
+        dom.append(node, to: parent)
```

`Frame`:

```diff
-            let parsed: any DOMNode = profiler.measure("load.parse", {
-                HTMLParser(body: body).parse()
-            })
-            dom = DOMTree(root: parsed)
+            dom = profiler.measure("load.parse", {
+                HTMLParser(body: body).parse()
+            })
```

```diff
-    var nodes: any DOMNode {
-        get { dom.node(dom.root)! }
-        set { dom = DOMTree(root: newValue) }
-    }
+    var nodes: DOMRef { DOMRef(id: dom.root, dom: dom) }
```

```diff
-    weak var frameElement: Element?
+    weak var frameElement: NodeID?
```

`FrameParent`:

```diff
 struct FrameParent {
     weak var frame: Frame?
-    weak var element: Element?
+    let element: NodeID?
 }
```

`Frame` DOM mutations use the arena:

```diff
-        f.children.append(text)
+        dom.append(text, to: f.id)
```

```diff
-            f.attributes["value", default: ""] += char
+            f.setAttribute("value", (f.attributes["value"] ?? "") + char)
```

```diff
-        html.children = [body]
+        dom.setChildren([body], of: html.id)
```

`JSRuntime` handles are IDs throughout:

```diff
-            guard let self, let elt = self.handleToNode[handle] as? Element else { return "" }
+            guard let self, let node = self.handleToNode[handle],
+                let elt = self.frame.dom.element(node)
+            else { return "" }
```

`_createElement`:

```diff
-            let elt: Element = Element(tag: tag, attributes: [:], parent: nil)
-            _ = frame.dom.register(elt)
-            return self.getHandle(elt)
+            let id: NodeID = frame.dom.createElement(tag: tag, attributes: [:])
+            return self.getHandle(id)
```

`_appendChild` / `_removeChild` / `_insertBefore` use `dom.append`, `dom.remove`, `dom.insert` and then `frame.setNeedsRender()`. Do not mutate `children` arrays directly through a `DOMRef`.

Selectors stop taking nodes:

```diff
 protocol CSSSelector {
-    func matches(_ node: any DOMNode) -> Bool
+    func matches(_ id: NodeID, in dom: DOMTree) -> Bool
 }
```

`ApplyStyle` recurses by `NodeID`:

```diff
-private func applyStyle(node: any DOMNode, cascade: StyleCascade, force: Bool) {
+private func applyStyle(id: NodeID, dom: DOMTree, cascade: StyleCascade, force: Bool) {
```

`AccessibilityNode`:

```diff
-class AccessibilityNode {
-    let node: DOMNode
+class AccessibilityNode {
+    let node: DOMRef
```

`computeBounds` uses `node.layout?.kind` and `LayoutRef.children`. No `as?`.

`StyleCascade.direct` / `oldStyles`, `JSRuntime.nodeToHandle` / `handleToNode`, `Frame.hoveredElements`, and `Browser.liveRegionTexts` switch from `ObjectIdentifier` to `NodeID`. This is the step that finishes the identity conversion A3 deferred.

`Frame.focus`, `hoveredElements`, `scrollFocusNode`, `iframeTargets`, and `scrollBlockTargets` store `NodeID` / `LayoutID`, not class references. `BrowserTab.focus` returns `ElementRef?`.

`CanvasBridge` uses side tables:

```diff
-                guard let ctx = (nodeForHandle(handle) as? Element)?.canvasContext else { return "" }
+                guard let id = nodeForHandle(handle),
+                    let ctx = tree.side.canvases.contexts[id]
+                else { return "" }
```

**Tests**

- `LayoutTestPage` and all fixtures build with `DOMTree`:
  ```swift
  let dom: DOMTree = DOMTree()
  let html: NodeID = dom.createElement(tag: "html", attributes: [:])
  let body: NodeID = dom.createElement(tag: "body", attributes: [:])
  dom.append(body, to: html)
  ```
- `firstElement(tag:)` returns `ElementRef?`.
- `DOMNodeTests` becomes `DOMTreeTests`; `Element` / `TextNode` construction assertions become `ElementData` / `TextData` assertions.
- `HTMLParserTests` compares `dom.tag`, `dom.text`, and `dom.children`.
- `AppendChildTests`, `InsertBeforeTests`, `ReplaceChildrenTests` assert `NodeID` order and parent links.

**Verification**

```sh
swift build && swift test
```

Screenshot gates:

- `www/ch15/index.html`: iframe, image, canvas, and scrollbar output identical.
- `www/ch11/exercise-11-3.html`: scroll effect scopes identical.
- `www/ch16/exercise-16-4-style-descendants.html`: style invalidation behavior unchanged.

### Step C3 — Delete the DOM classes and the adapter maps

**Files**

- Delete the remaining `Element` / `TextNode` class definitions from `Parsing/DOMNode.swift`; keep the tagged data.
- Remove `DOMTree.Index` class maps and `register`, `raw`, and any `any DOMNode` bridge.
- Remove `DOMRef.raw`.

**Change**

`DOMTree` now stores `[DOMNode?]` directly:

```swift
@MainActor
final class DOMTree {
    private(set) var nodes: [DOMNode?]
    private(set) var root: NodeID
    private(set) var side: DOMSideTables
    weak var layoutTree: LayoutTree?
}
```

Search gates:

```sh
grep -rn 'any DOMNode\|as? Element\|as? TextNode\|DOMNode\.raw\|ObjectIdentifier(node' Sources/Engine
```

The only remaining `ObjectIdentifier` uses in `Sources/Engine` should be for `BrowserTab`, `CGImage`, `CTFont`, and other non-node identities.

**Verification**

```sh
swift build && swift test
```

### Step D1 — Add the static input table and reverse index

**Files**

- New: `Core/FieldKey.swift`, `Core/DependencyIndex.swift`, `Layouts/LayoutInputTable.swift`.
- Modify: `LayoutTree.swift`, `DOMTree.swift`.

**Change**

`LayoutInputTable` states every edge once, per node kind and field. This is the table that replaces the `setDependencies` calls in `freezeGeometry`, `TextLayout.init`, `EmbedLayout.init`, and `DocumentLayout.init`.

Representative entries:

```swift
enum LayoutInputTable {
    static func inputs(
        for id: LayoutID,
        field: LayoutField,
        in tree: LayoutTree
    ) -> [FieldKey] {
        let node: LayoutNode = tree.node(id)
        let dom: NodeID = node.dom

        switch (node.kind, field) {
        case (.document, .width):
            return [.layout(id, .zoom)]

        case (.document, .x), (.document, .y):
            return [.layout(id, .zoom)]

        case (.block, .width):
            return [
                .layout(requiredParent(id, in: tree), .width),
                .layout(id, .zoom),
                .style(dom, .paddingLeft),
                .style(dom, .paddingRight),
                .style(dom, .width),
            ]

        case (.block, .y):
            var inputs: [FieldKey] = [
                .layout(requiredParent(id, in: tree), .y),
                .layout(id, .zoom),
                .style(dom, .paddingTop),
                .style(dom, .top),
                .style(dom, .marginTop),
            ]
            if let previous = node.links.previous {
                let previousDom: NodeID = tree.node(previous).dom
                inputs += [
                    .layout(previous, .y),
                    .layout(previous, .height),
                    .style(previousDom, .marginBottom),
                    .style(previousDom, .paddingBottom),
                ]
            }
            return inputs

        case (.line, .width):
            return [.layout(requiredParent(id, in: tree), .width)]

        case (.text, .font):
            return [.layout(id, .zoom)] + fontKeys(dom, in: tree)

        case (.embed, .zoom):
            return [
                .layout(requiredParent(id, in: tree), .zoom),
                .style(dom, .zoom),
            ]

        default:
            return []
        }
    }
}
```

`DependencyIndex` builds and marks:

```swift
@MainActor
struct DependencyIndex {
    private var dependents: [FieldKey: [FieldKey]] = [:]

    mutating func rebuild(from tree: LayoutTree) {
        dependents.removeAll(keepingCapacity: true)
        for id in tree.liveIDs {
            for field in LayoutField.allCases {
                guard tree.isUsed(field, at: id) else { continue }
                for input in LayoutInputTable.inputs(for: id, field: field, in: tree) {
                    dependents[input, default: []].append(.layout(id, field))
                }
            }
        }
    }

    func mark(_ key: FieldKey, in tree: LayoutTree) {
        for dependent in dependents[key] ?? [] {
            guard case .layout(let id, let field) = dependent else { continue }
            tree.markDirty(field, at: id)
        }
    }
}
```

`LayoutInputTable.inputs` takes three parameters, not four. `LayoutInputTable` is a stateless enum; no catch-all context.

**Tests**

- For every layout field used in the current tests, `inputs(for:field:)` equals the old `frozen dependencies` set.
- Adding a new `LayoutField` case is a compile error in the table.
- Removing a child removes its edges from `DependencyIndex`.

**Verification**

```sh
swift build && swift test
```

### Step D2 — Make reads pure and delete the handles

**Files**

- Delete: `Core/FieldRef.swift`, `Core/FieldDependencyKey.swift`, `Layouts/LayoutFieldHandle.swift`, `Layouts/LayoutFieldAccess.swift`, `Style/StyleFieldRef.swift`.
- Modify: every layout pass, `StyleFields.swift`, `StyleTransitions.swift`, `Frame.swift`, `LayoutDependencyDump.swift`.

**Change**

The old handle API disappears:

```diff
-        let parentZoom: CGFloat = parent?.zoomField.read(notify: zoomField) ?? 1.0
-        node.style.field(.zoom).touch(zoomField)
+        let parentZoom: CGFloat = parent?.zoom ?? 1.0
+        let ownZoom: CGFloat = node.style.computed.box.zoom ?? 1.0
```

```diff
-        widthField.setDependencies([
-            parent.widthField,
-            zoomField,
-            node.style.field(.paddingLeft),
-            node.style.field(.paddingRight),
-            node.style.field(.width),
-        ])
+        // Declared in LayoutInputTable.inputs(for:field:in:).
```

```diff
-        let width: CGFloat = parent!.widthField.read(notify: widthField)
+        let width: CGFloat = parent!.width
```

`LayoutFieldStore` writes go through the tree:

```swift
extension LayoutTree {
    func setField(_ field: LayoutField, _ value: CGFloat, for id: LayoutID) {
        guard value(of: field, at: id) != value else { return }
        nodes[id.raw]!.state.fields.set(value, for: field)
        nodes[id.raw]!.state.fields.state.dirtyBits &= ~field.mask
        dependencies.mark(.layout(id, field), in: self)
        markAncestorsDirty(from: id)
    }
}
```

Style writes notify the same index. `StyleFields.mutate` returns the changed set (today it computes and discards it):

```swift
extension DOMTree {
    func applyStyle(id: NodeID, _ body: (inout ComputedStyle) -> Void) {
        let style: StyleFields = node(id)!.base.style
        let changed: Set<StyleProperty> = style.mutate(body)
        guard !changed.isEmpty else { return }
        for property in changed where property.affectsLayout {
            layoutTree?.dependencies.mark(.style(id, property), in: layoutTree!)
        }
    }
}
```

`StyleFields.field(_:)`, `StyleFieldRef`, `LayoutFieldHandle`, `read(notify:)`, `touch(_:)`, `setDependencies`, `addInvalidation`, `removeInvalidation`, `containsInvalidation`, `frozenDependencies`, and `FieldOwner` are deleted. `LayoutDependencyDump` prints `LayoutInputTable.inputs` for the same debug view.

**Tests**

- `LayoutDependencyTests` reads the table instead of `layoutFields`/`FieldRef`.
- `StyleFieldsTests` replaces `dependentCount` assertions with `DependencyIndex` assertions.
- `LayoutInvalidationTests` still asserts the same outcomes; only the mechanism changes.

**Verification**

```sh
swift build && swift test
```

Profile gate: `layout.skipped` and `layout.visited` counts on `www/ch16/exercise-16-2-protecting-layout-phases.html` must match B2. If `layout.visited` grows, the reverse index is missing an edge; fix the table, not the pass.

### Step D3 — Remove the last per-node dependency state

**Files**

- Modify: `StyleFields.swift`, `LayoutTree.swift`, `DOMTree.swift`, `Frame.swift`, `StyleTransitions.swift`, `Animation/*.swift`.
- Delete: `LayoutDependencyDump.swift` if its debug output is replaced by `LayoutInputTable` dump.

**Change**

- `StyleFields.dependents` dictionary is deleted. `StyleFields` keeps only computed style, unknown values, dirty keys, and the owner `NodeID`.
- `LayoutFieldStore` no longer stores `frozenBits`; all edges are static.
- `LayoutTree` rebuilds `DependencyIndex` before a layout pass and after `setChildren` / `removeSubtree`.
- `Frame.setNeedsLayout` marks the document root dirty; the index propagates field writes, not frame-level invalidation.

```diff
-private struct StyleInvalidationState {
-    var dirtyKeys: Set<StyleProperty> = []
-    var dependents: [StyleProperty: [FieldDependencyKey: FieldRef]] = [:]
-    var needsRestyle: Bool = true
-    var descendantsDirty: Bool = false
-}
+private struct StyleInvalidationState {
+    var dirtyKeys: Set<StyleProperty> = []
+    var needsRestyle: Bool = true
+    var descendantsDirty: Bool = false
+}
```

**Verification**

```sh
swift build && swift test
```

### Step D4 — Clean up and prove no second path remains

**Files**

- Delete unused invalidation files and any temporary bridge.
- Update `README.md` only if it still describes the class trees (the premise correction is already committed).

**Change**

Search gates:

```sh
grep -rn 'FieldRef\|InvalidatableField\|FieldOwner\|LayoutFieldHandle\|StyleFieldRef\|read(notify\|setDependencies\|as? BlockLayout\|as? LineLayout\|as? TextLayout\|as? EmbedLayout\|as? Element\|as? TextNode' Sources/Engine Tests
```

Expected hits: none in `Sources/Engine`. Tests may keep intentionally descriptive names, not types.

**Verification**

```sh
swift build
swift test
```

## Verification

Run after every step, and the full set after B2, C2, and D2:

```sh
swift build
swift test
swift run ToyStackHeadless "file://$PWD/www/ch11/index.html" \
  --trace /tmp/after-layout-paint.trace --frame-limit 5 --screenshot /tmp/after-layout-paint.png
swift run ToyStackHeadless "file://$PWD/www/ch15/index.html" \
  --trace /tmp/after-layout-embed.trace --frame-limit 5 --screenshot /tmp/after-layout-embed.png
swift run ToyStackHeadless "file://$PWD/www/ch16/exercise-16-2-protecting-layout-phases.html" \
  --trace /tmp/after-layout-incremental.trace --frame-limit 5 --screenshot /tmp/after-layout-incremental.png
```

Compare:

```sh
cmp /tmp/before-layout-paint.png /tmp/after-layout-paint.png
cmp /tmp/before-layout-embed.png /tmp/after-layout-embed.png
cmp /tmp/before-layout-incremental.png /tmp/after-layout-incremental.png
```

Trace counters that must not regress:

| Counter | Meaning | Gate |
|---|---|---|
| `layout.visited` | blocks that ran | equal or lower on clean pass |
| `layout.skipped` | blocks skipped | equal on clean pass |
| `layout.children.rebuilt` | child arrays rebuilt | unchanged for text/edit/append tests |
| `layout.children.appended` | incremental append | unchanged |
| `layout.children.inserted` | incremental insert | unchanged |
| `paint.cache.hit.blocks` | block paint reuse | unchanged |
| `paint.cache.hit.lines` | line paint reuse | unchanged |
| `layout.animation.fallback` | missing animation edge | zero |

For animation/transition pages, use the existing video check as in the style plan:

```sh
swift run ToyStackHeadless "file://$PWD/www/ch13/exercise-13-6.html" \
  --trace /tmp/after-layout-anim.trace --frame-limit 30 --screenshot /tmp/after-layout-anim.png
```

## Risks

1. **Layout ID reuse.** If `LayoutID` is reused after `removeSubtree`, a stale cache can hit the wrong node. Keep IDs monotonic and never reuse them. This is cheaper than a generation field and safe for a toy engine.
2. **Primary layout mapping.** `primaryByNode` must be updated when a block is removed or rebuilt. If it goes stale, `DOMRef.layout` returns a dead ID. `LayoutTree.removeSubtree` clears map entries for the subtree; `makeBlock` overwrites the primary for its first DOM node.
3. **Incremental child reuse.** `layout.children.rebuilt` tests are the canary. The block child builder must keep the same `LayoutID` for survivors and only allocate IDs for new nodes.
4. **Cache ownership.** `PaintCache` and `LinePaintCache` move from class properties to `BlockData` / `LineData`. Mutating them through `LayoutRef` must write back into `LayoutTree`; do not copy a `BlockData` and forget to store it.
5. **DOM mutation from JS.** `appendChild`, `insertBefore`, `removeChild`, `replaceChildren`, and `textContent` must maintain `parent` / `children` on both sides. The old classes did this with direct arrays; the arena needs one `DOMTree` method per operation and no direct array mutation outside it.
6. **Frame targets across layout passes.** `iframeTargets` and `scrollBlockTargets` currently hold layout objects. With an arena, hold `LayoutID` and resolve through `document`; never keep a `LayoutRef` after `removeSubtree`.
7. **Accessibility nodes outlive layout.** `AccessibilityNode` holds a `DOMRef`; `DOMRef.layout` resolves through the current `LayoutTree`. If the frame rebuilds the tree, the accessibility node sees the new layout, which is what the current code does with `layoutObject` replacement.
8. **Style owner references.** `StyleFields` is a class per node. Give it `let owner: NodeID` and a weak `DOMTree`; do not let it hold a `DOMRef` strongly or the tree becomes a cycle.
9. **Test identity.** `ObjectIdentifier` assertions become `NodeID` / `LayoutID` assertions. Do not replace them with `==` on whole structs; that would pass after a rebuild and hide a broken reuse path.

## Commit order

| Commit | Subject | Contents |
|---|---|---|
| 1 | `refactor: give nodes stable IDs` | A1: `NodeID`, `LayoutID`, `DOMTree` adapter, `DOMRef` views |
| 2 | `refactor: read layout through node values` | A2: `LayoutObject.node` -> `DOMRef`, layout casts removed |
| 3 | `refactor: identify paint scopes by node` | A3: `NodeKey` -> `NodeID`, composition caches |
| 4 | `refactor: store layout nodes in one arena` | B1 + B2: data model and cutover |
| 5 | `refactor: delete the layout class tree` | B3: old files deleted |
| 6 | `refactor: store document nodes in one arena` | C1 + C2: DOM data model and cutover |
| 7 | `refactor: delete the DOM class tree` | C3: old classes and adapter maps deleted |
| 8 | `refactor: declare layout inputs once` | D1: `LayoutInputTable` and `DependencyIndex` |
| 9 | `refactor: read layout fields directly` | D2 + D3: handles and per-node dependents removed |

Commit 4 is the risky one. Do not start commit 6 until the three screenshots and the incremental-layout counters are green after commit 5.
