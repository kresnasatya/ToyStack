# ToyStack: OOP Findings and Data-Shape Corrections

Two sources point at the same problem from different directions:

- **Casey Muratori** — *The Big OOPs* (2025) and *Semantic Compression* (2014): domain-model inheritance hierarchies and encapsulation around nouns fight the cross-cutting operations real programs need; abstractions should be earned from concrete use.
- **Apple, WWDC15 408** — *Protocol-Oriented Programming in Swift*: inheritance and implicit sharing are the wrong defaults; value types and protocol composition are better; but protocols are still type-centric.

The shared conclusion:

> **Protocols are for open seams. Sum types are for closed data. Flat arrays are for hot passes.**

ToyStack already uses value types in places (`Rect`, `Point`, `BrowserFont`, `LayoutField` bitmasks, paint caches). The six areas below are where the object-oriented shape still dominates.

## The README premise, corrected

The README currently gives this as reason #2:

> **2. Everything is object.**
>
> The web has Document Object Model (DOM). Swift has Object Oriented Programming. There's correlation between those terms.
>
> > How does the DOM relate to Swift’s OOP model in the context of building a browser engine?

Reasons #1 and #3 are unaffected. Reason #2 is the premise that produced most of the shapes in this document, and it is wrong in four ways.

### What went wrong

| README claim | What went wrong | What should be |
|---|---|---|
| "Everything is object." | The DOM is a tree of a fixed set of node kinds. "Object" in *Document Object Model* means a node in that model, not an instance of an open class hierarchy with inheritance and encapsulation. | Model the document as tagged values over a closed set of node kinds. Use classes only at language boundaries. |
| "Swift has Object Oriented Programming." | True but incomplete. Swift supports classes, but its design center is protocol-oriented and value-oriented. Structs and enums are first-class types with methods, computed properties, subscripts, and extensions. | Use structs and enums for data; use protocols for seams where implementations vary. |
| "There's correlation between those terms." | A word coincidence, not a design argument. The word "object" in DOM and in OOP does not mean the same thing. | Correlate the *shape*: a closed tree calls for a sum type; an open backend calls for a protocol. |
| "How does the DOM relate to Swift's OOP model?" | The question starts from a language feature and looks for a place to apply it. | Start from the data shape and choose the Swift feature that expresses it. |

The DOM is also language-neutral. It has bindings in JavaScript, Python, Java, and Swift. Nothing about the model requires the engine's internal representation to be a class hierarchy. ToyStack already gets this right in one place: `Element.tag` is a string, so `<div>` and `<span>` are data, not subclasses. The correction is to extend that same instinct to node kinds and layout kinds.

### What should be

Replace the README bullet with something like:

> **2. The DOM is a tree, not an object graph.**
>
> The web's Document Object Model is a fixed set of node kinds arranged as a tree. Building a browser engine is a chance to model that tree with Swift's value types and enums, and to use protocols only where implementations vary: the renderer, the font backend, the network loader.

A shorter version:

> **2. The DOM is data, not a paradigm.**
>
> A document is a tree of a few node kinds. Swift expresses that with value types and enums. Protocols are reserved for open seams.

### The code contrast

**What went wrong**

```swift
class DOMNode {}
class Element: DOMNode { var tag: String = "" }
class TextNode: DOMNode { var text: String = "" }

func text(of node: DOMNode) -> String {
    if let text = node as? TextNode { return text.text }
    if node is Element { return "" }
    return ""
}
```

**What should be**

```swift
enum DOMNode {
    case element(tag: String)
    case text(String)
}

func text(of node: DOMNode) -> String {
    switch node {
    case .text(let value): return value
    case .element: return ""
    }
}
```

This is the same correction as item 3, applied at the premise level. The set of node kinds is closed; element tag names are data. The class hierarchy is not carrying its weight.

### What this changes in the rest of the document

- **Item 1:** draw commands are a closed set, so a protocol is the wrong shape.
- **Item 3:** the DOM and layout trees are closed sets, so the class hierarchy and `as?` passes follow directly from the premise.
- **Item 6:** `Frame` becomes one object holding everything because the premise says the frame *is* an object. The correction says the frame is data plus a coordinator.
- **What stays:** `Renderer` remains a protocol because implementations genuinely vary. The premise correction is not "delete all protocols"; it is "stop using protocols for closed sets."

## The two arguments, with examples

### Casey Muratori: the hierarchy fights the operation

Muratori's target is not "objects exist." It is the claim that a program should be organized as a hierarchy of domain nouns, with data hidden inside the most-derived type. His test is simple: take an operation that must touch many kinds of data at once. The hierarchy makes that operation the hardest thing to write.

#### Example 1 — the cross-cutting operation

**What went wrong**

```swift
class Shape {
    func draw() {}
}

class Circle: Shape {
    var radius: CGFloat = 0
}

class Triangle: Shape {
    var points: [Point] = []
}

func recolor(_ shapes: [Shape], to color: Color) {
    for shape in shapes {
        // radius and points are inside the subclasses.
        // The base class does not expose them.
        // So either add get/set accessors to Shape...
        // ...or downcast every element:
        if let circle = shape as? Circle {
            circle.setColor(color)
        } else if let triangle = shape as? Triangle {
            triangle.setColor(color)
        }
    }
}
```

The operation is not about `Circle` or `Triangle`; it is about color across all shapes. The hierarchy put the color behind the most-derived type, so the cross-cutting operation needs accessors or downcasts. If you add the accessors to the base class, the base class becomes a fat union of every property any subclass might have. Then the hierarchy is no longer buying encapsulation.

> "Why did you bother with the hierarchy? You're not getting any actual encapsulation benefits from it because you just forced everything in the base class anyway."

**What should be**

Make the data addressable by the operation. A tagged value is the smallest fix:

```swift
enum Shape {
    case circle(center: Point, radius: CGFloat, color: Color)
    case triangle(points: [Point], color: Color)
}

func recolor(_ shapes: [Shape], to color: Color) -> [Shape] {
    shapes.map { shape in
        switch shape {
        case .circle(let center, let radius, _):
            return .circle(center: center, radius: radius, color: color)
        case .triangle(let points, _):
            return .triangle(points: points, color: color)
        }
    }
}
```

Muratori's stronger form is to invert ownership: the color system owns the color data, the shape system owns geometry, and an entity ID joins them. That is the ECS/"rotated" architecture he describes. The point is the same: the operation should not have to ask the noun for permission.

> "Most of the time what we need to do is create cross-cutting operations that work with a lot of the data that's inside these derived classes."

**In ToyStack:** item 1 (draw commands), item 3 (`LayoutObject` casts in paint and invalidation), item 4 (cross-cutting dirty propagation).

#### Example 2 — encapsulation makes integration harder

**What went wrong**

A class exposes only the operations its author predicted. A caller who needs a different operation cannot reach the data.

> "The lie is if something is object oriented it will be easier for someone else to integrate, because it's all encapsulated. The truth is the opposite. The more walled off something is the harder it is for someone to integrate because there's nothing they can do with it. The only things they can do are things you've already thought of and provided an interface for and anything you forgot, they're powerless. They have to wait for an update."

**What should be**

Expose data at the level the operation needs, or keep the data in a system that owns it. A display list of values, a flat array of layout nodes, and side tables keyed by ID are all versions of this. The caller can write a new pass without asking the type author for a new method.

**In ToyStack:** item 1 (`[any DisplayItem]` requires new casts for new passes), item 6 (`Frame` hides document, layout, and display state behind one class).

#### Example 3 — premature abstraction

**What went wrong**

OOP pedagogy asks for the class hierarchy before the code exists. The hierarchy is a prediction about which nouns and operations matter.

> "The bad code all seems to come from roughly the same source... not dealing with the actual thing that's happening."

**What should be**

Write the concrete operation first. Extract a type only after the second real instance.

> "Make your code usable before you try to make it reusable."

**In ToyStack:** item 4 (dependency edges declared per instance before the real reads), item 1 (protocols for fixed sets).

---

### Apple, WWDC15 408: classes are the wrong default

Dave Abrahams' talk is an internal critique of class-based OOP, not a defense of it. Crusty's three complaints are: automatic sharing, intrusive inheritance, and classes are a bad fit when type relationships matter.

#### Example 1 — `Ordered`: the forced downcast

**What went wrong** (simplified reconstruction)

```swift
class Ordered {
    func precedes(_ other: Ordered) -> Bool {
        fatalError("subclass must implement")
    }
}

final class Number: Ordered {
    var value: Double = 0

    override func precedes(_ other: Ordered) -> Bool {
        guard let other = other as? Number else {
            fatalError("not a number")
        }
        return value < other.value
    }
}
```

The class cannot say "other is the same type as self." The override must downcast, and the downcast can fail at runtime.

> "Any time you see a forced down-cast in your code, it's a good sign that some important type relationship has been lost."

**What should be**

```swift
protocol Ordered {
    func precedes(_ other: Self) -> Bool
}

struct Number: Ordered {
    var value: Double
    func precedes(_ other: Number) -> Bool {
        value < other.value
    }
}
```

`Self` expresses the relationship. The compiler checks it. No downcast, no trap.

> "We trade dynamic polymorphism for static polymorphism, but, in return for that extra type information we're giving the compiler, it's more optimizable."

**In ToyStack:** item 1 (`as? any DisplayCommand`), item 3 (`as? BlockLayout`), item 4 (`any InvalidatableField`).

#### Example 2 — implicit sharing

**What went wrong**

```swift
final class Box {
    var value: Int = 0
}

let a = Box()
let b = a
b.value = 1
// a.value is also 1
```

Two names, one object. The talk's chain is: defensive copies, then locks, then races or deadlocks.

**What should be**

```swift
struct Box {
    var value: Int = 0
}

var a = Box()
var b = a
b.value = 1
// a.value is still 0
```

> "Swift collections are all value types" — the talk uses this to explain why iterating and mutating a collection no longer alias.

**In ToyStack:** item 6 (`Frame` and `Element` shared mutable graph, `@MainActor`, `@unchecked Sendable`), item 5 (`StyleFields` as a shared class per node).

#### Example 3 — the protocol extension dispatch trap

**What went wrong** (simplified reconstruction)

```swift
protocol Renderer {
    func circleAt(_ center: Point, radius: CGFloat)
}

extension Renderer {
    func circleAt(_ center: Point, radius: CGFloat) {
        // default drawing
    }

    func rectangleAt(_ rect: Rect) {
        // default drawing
    }
}

struct TestRenderer: Renderer {
    func circleAt(_ center: Point, radius: CGFloat) {
        print("test circle")
    }

    func rectangleAt(_ rect: Rect) {
        print("test rectangle")
    }
}

let renderer: any Renderer = TestRenderer()
renderer.circleAt(.zero, radius: 1)   // TestRenderer's implementation: it is a requirement
renderer.rectangleAt(.zero)           // extension default: it is NOT a requirement
```

The second call ignores `TestRenderer.rectangleAt`. A non-requirement method in a protocol extension is statically dispatched and shadows the concrete implementation.

> "Which is kind of weird, right?... Does this mean that rectangleAt should have been a requirement? Maybe, in this case, it should."

**What should be**

If a method is a customization point, declare it in the protocol. If it is only a convenience, do not let a conformer shadow it. The same rule applies to `LayoutObject`'s extension-only members (`children`, `x`, `hitTest`): a node type that defines its own `x` would be ignored through `any LayoutObject`.

**In ToyStack:** item 1 (extension-only members), item 3 (protocol requirements vs extension helpers).

#### Example 4 — value types and retroactive conformance (the win)

**What went wrong**

Inheritance forces one superclass and one place to put shared storage. That is why `Ordered`'s subclass must downcast and why `Drawable` classes accumulate shared state.

**What should be**

The talk's diagramming example uses value types (`Circle`, `Polygon`, `Diagram`) and a `Drawable` protocol. It also makes `CGContext` conform to `Renderer` without modifying `CGContext`:

```swift
extension CGContext: Renderer { /* ... */ }
```

That is genuine openness: you can add a capability to a type you do not own. A class hierarchy cannot do that. It is also the strongest counter to Muratori's "they have to wait for an update" complaint.

> "The more we decouple things with protocols, the more testable everything gets."

The caveat: `Drawable` is an open seam (any type may be drawable). ToyStack's `DisplayItem` is a closed internal set. For closed sets, a sum type is the precise Swift expression; for open seams, the protocol is.

**In ToyStack:** keep `Renderer` as the open seam; use `DisplayOp` and `LayoutKind` for closed sets.

#### Sources for both arguments

- Casey Muratori, [*The Big OOPs: Anatomy of a Thirty-Five Year Mistake*](https://www.youtube.com/watch?v=wo84LFzx5nI), [notes](https://www.computerenhance.com/p/the-big-oops-anatomy-of-a-thirty).
- Casey Muratori, [*Semantic Compression*](https://caseymuratori.com/blog_0015) and [*Complexity and Granularity*](https://caseymuratori.com/blog_0016).
- Casey Muratori interview, [*Surprises In Computer History And Where Bad Code Comes From*](https://www.developing.dev/p/casey-muratori-surprises-in-computer).
- Dave Abrahams, [*Protocol-Oriented Programming in Swift*, WWDC15 408](https://developer.apple.com/videos/play/wwdc2015/408/).

---

## Six changes at a glance

| # | Area | Current shape | Target shape |
|---|------|---------------|--------------|
| 1 | Draw commands | protocols + class hierarchy | `enum DisplayOp` |
| 2 | Paint output | tree of effect objects, flattened later | flat buffer with begin/end |
| 3 | Layout and DOM | class hierarchy + `as?` in every pass | tagged nodes + stable IDs |
| 4 | Invalidation | per-instance dependency graph | static input table + versions |
| 5 | Style and animation | strings round-tripped | typed `ComputedStyle` + `AnimatedValue` |
| 6 | Frame state | one big mutable class | grouped value state + snapshots |

---

## 1. Closed internal sets are modeled as open protocols and class hierarchies

**The rule:** a protocol says *"anyone can add a case later."* An enum says *"these are all the cases."* Use a protocol only when the first sentence is true.

### Step 1 — Decide whether the set is closed

**What went wrong**

`DisplayItem` and `DisplayCommand` are protocols (`DisplayItem.swift:4`, `DisplayCommand.swift:5`), but the engine owns every possible draw command: rect, line, text, image, rrect, outline, clipped image, composited layer. No external module will add one. The set is closed, but the type says it is open.

The same pattern appears in other closed sets:

- Selectors are `[any CSSSelector]` (`CSSSelector.swift:2`, `Frame.swift:54`).
- Animations are an `Animation: AnyObject` protocol with a class hierarchy (`Animation.swift:4`, `NumericAnimation.swift:27`).
- Invalidation fields use `any InvalidatableField` (`FieldRef.swift:22`) even though `FieldRef` already carries owner + name.

**What should be**

List every case. If you can list them and nobody outside the module owns one, it is closed → use an enum.

### Step 2 — Model the cases as data, not classes

**What went wrong**

Each command is its own type conforming to `DisplayCommand`. Adding a command does not force the places that must handle it to update:

- `DisplayCommand.contentHash` is a manual chain of `as?` checks (`DisplayCommand.swift:10-40`); a new command silently gets an incomplete hash.
- `BrowserVisualEffect` is a base class with `clone()` whose default implementation is `fatalError` (`BrowserVisualEffect.swift:28-30`); a new effect that forgets to override it crashes at runtime.
- `needsCompositing` scans children with `compactMap { $0 as? BrowserVisualEffect }` (`BrowserVisualEffect.swift:14-18`).

**What should be**

```swift
enum DisplayOp {
    case rect(Rect, BrowserColor)
    case line(Point, Point, BrowserColor, CGFloat)
    case text(String, BrowserFont, BrowserColor, Point)
    case image(CGImage, Rect)
    case rrect(Rect, CornerRadii, BrowserColor)
}
```

The shared `rect` property becomes a `switch`. The hash becomes a `switch`. Adding a case makes every non-exhaustive switch a compile error.

### Step 3 — Dispatch with one switch, not `as?` per item

**What went wrong**

`Browser.swift:514-519` loops over `[any DisplayItem]` and asks every item *"are you a command? are you an effect?"* The same pattern repeats during composition (`Browser.swift:622-637`) and effect classification (`Browser.swift:712-792`). Each `as?` is a runtime type check; the array boxes each item and looks up its methods at runtime.

**What should be**

`[DisplayOp]` and one switch in each consumer:

```swift
for op in ops {
    switch op {
    case .rect(let rect, let color):
        renderer.fillRect(rect, color: color)
    case .line(let from, let to, let color, let width):
        renderer.strokeSegment(from: from, to: to, color: color, lineWidth: width)
    // ...
    }
}
```

One switch in the renderer, one in the hasher, one in the shifter. No casts and no boxing.

### Step 4 — Replace the effect class tree with an effect enum

**What went wrong**

`BrowserVisualEffect` is a base class (`BrowserVisualEffect.swift:3`) with `Blend`, `Clip`, `Transform`, `ScrollEffect`, and `BlurFilter` subclasses. The base class has `clone()` with a `fatalError` default. A new effect can compile without implementing `clone()` and crash later.

**What should be**

```swift
enum EffectKind {
    case blend(opacity: Double, mode: BrowserBlendMode?)
    case blur(radius: CGFloat)
    case clip(ClipShape)
    case transform(Point)
}
```

A `struct DisplayEffect` holds `kind`, `rect`, and `children`. Cloning is a `switch`, so it cannot be forgotten. Turning the tree into a flat buffer is item 2.

### Step 5 — Keep the protocols that are actually open

**What went wrong**

Treating every protocol as suspicious would remove the one seam that works.

**What should be**

`Renderer` (`Renderer.swift:3`) has genuinely multiple implementations: `CGRenderer`, `SwiftUIRenderer`, test renderers. Keep it a protocol. `DisplayItem`, `DisplayCommand`, and `BrowserVisualEffect` are internal representations of fixed sets; they are not seams.

### The test

For any protocol, ask:

1. Can I list every conforming case today?
2. Does anyone outside this module add a case?

If **yes** and **no**, it is a closed set → enum. Otherwise it is an open seam → protocol.

---

## 2. Paint builds a tree of existentials, then flattens it with copies

**The problem in one line:** paint builds a tree of effects with child arrays, then raster immediately flattens that tree back into a list. ToyStack pays for both representations.

### Step 1 — Choose one representation

**What went wrong**

The display list is `[any DisplayItem]`, where an item is either a command or a `BrowserVisualEffect` that owns `children: [any DisplayItem]` (`BrowserVisualEffect.swift:5`). The same content exists as a nested tree.

**What should be**

One flat array. Nesting is represented by markers:

```swift
enum DisplayOp {
    case rect(Rect, BrowserColor)
    case text(String, BrowserFont, BrowserColor, Point)
    case beginEffect(EffectKind)
    case endEffect
}
```

`beginEffect` / `endEffect` say "the ops between here belong to this effect." No effect object owns a child array.

### Step 2 — Paint appends; it does not slice and re-wrap

**What went wrong**

`paintTree` records `childStart`, paints the children, copies the produced range, removes it, and wraps it:

```swift
let childItems = Array(displayList[childStart...])
displayList.removeSubrange(childStart..<displayList.count)
let effect = ScrollEffect(children: childItems)
displayList.append(effect)
```

That is `PaintTree.swift:45-72`. The clip path does the same through `clippedChildren` (`PaintTree.swift:73-80`). `applyPaintEffects` repeats it with `Array(items[start...])` and `replaceSubrange` (`LayoutObject.swift:175-182`). Every effect costs a subtree copy.

**What should be**

Append the marker, paint the children, append the end marker:

```swift
if let effect = node.effect {
    list.append(.beginEffect(effect))
}
paintOwnContent(node, into: &list)
for child in node.children {
    paint(child, into: &list)
}
if node.effect != nil {
    list.append(.endEffect)
}
```

No copy, no `removeSubrange`, no re-wrapping.

### Step 3 — Raster scans once with a stack

**What went wrong**

Because effects are a tree, raster must first restore parent links (`addParentPointers`, `BrowserVisualEffect.swift:63-84`), then flatten the tree (`treeToList`, `Browser.swift:617-620`), then cast the flattened items back to commands (`compactMap`, `Browser.swift:622-637`). `maxRectBottom` recurses through children (`BrowserVisualEffect.swift:87-100`).

**What should be**

One pass over the flat array, with a stack:

```swift
var effects: [EffectKind] = []

for op in list {
    switch op {
    case .beginEffect(let kind):
        effects.append(kind)
        applyEffect(kind, renderer: renderer)
    case .endEffect:
        finishEffect(effects.removeLast(), renderer: renderer)
    case .rect(let rect, let color):
        renderer.fillRect(rect, color: color)
    case .text(_, let font, let color, let point):
        // draw text
    }
}
```

The top of `effects` is the current parent. No weak `parentEffect` pointers, no flatten pass, no tree recursion.

### Step 4 — Caches stop filtering existentials

**What went wrong**

`PaintCache` stores `[any DisplayCommand]` and converts items with `as?` (`PaintCache.swift:20-31`). `LinePaintCache` does the same and rejects anything that is not `DrawText` or `DrawOutline` (`LinePaintCache.swift:13-22`). A block containing an effect silently fails to cache.

**What should be**

The cache stores `[DisplayOp]` and decides with a `switch`:

```swift
for op in ops {
    switch op {
    case .rect, .text, .image:
        relative.append(op.shifted(by: -origin))
    case .beginEffect, .endEffect:
        // this block cannot be cached as-is
    }
}
```

Type-checking becomes a compile-time switch, not a runtime `as?`.

### What improves

- Paint is a linear append; no subtree copies.
- Raster is a linear scan with a stack; no flattening, no parent pointers.
- Effects are a property of the stream, not an object graph.
- Caches store values instead of boxed existentials.
- `Renderer` still does the real work: `saveState` / `restoreState` / `drawLayer` map directly to `beginEffect` / `endEffect`.

**The rule:** paint once into one buffer; let the consumer interpret scopes. Don't build a tree just to flatten it.

---

## 3. Layout and DOM are class hierarchies where every pass downcasts

**The problem in one line:** both trees have a fixed set of node kinds, but they are built from classes and a protocol, so every pass rediscovers the kind with `as?`.

### Step 1 — List the kinds

**What went wrong**

`LayoutObject` is a protocol (`LayoutObject.swift:5`) with `BlockLayout`, `LineLayout`, `TextLayout`, `EmbedLayout`, `DocumentLayout`, and embed subclasses. `DOMNode` is a protocol (`DOMNode.swift:5`) with `Element` and `TextNode`. The set is closed, but the types say it is open.

**What should be**

```swift
enum LayoutKind {
    case document
    case block(BlockData)
    case line(LineData)
    case text(TextData)
    case embed(EmbedData)
}

enum DOMKind {
    case element(ElementData)
    case text(TextData)
}
```

### Step 2 — Keep shared state in one place

**What went wrong**

Every layout subclass repeats the same stored properties:

- `let node`
- `var parent`
- `var fields: LayoutFieldStore`
- `var hasDirtyDescendants`

`parent` is `weak` in `LineLayout` and `TextLayout`, strong in `BlockLayout`, and a constant `nil` in `DocumentLayout` (`DocumentLayout.swift:7`). The shared shape is copied into every class.

**What should be**

One node type with the shared state once, and kind-specific state in the enum payload:

```swift
struct LayoutNode {
    var kind: LayoutKind
    var base: LayoutBase        // id, parentID, fields, dirty flag
    var children: [NodeID]
}

struct LayoutTree {
    var nodes: [LayoutNode]
}
```

`node` and `parent` become IDs. `any DOMNode` and `any LayoutObject` references become `NodeID`, so each node stops carrying two existential references.

### Step 3 — Replace casts with switches

**What went wrong**

Passes are full of type tests:

- `PaintTree.swift:8,18,44,73,82`
- `LayoutInvalidation.swift:11,23,64,71,82`
- `BlockLayout.swift:369,426,442,504,532,549,574`
- `EmbedLayout.swift:43,99`

Each is a runtime check per node per pass. Adding a node kind does not force these passes to handle it.

**What should be**

One exhaustive switch per pass:

```swift
switch tree.nodes[id].kind {
case .document:
    layoutDocument(id, &tree)
case .block(let block):
    layoutBlock(id, block, &tree)
case .line(let line):
    layoutLine(id, line, &tree)
case .text(let text):
    layoutText(id, text, &tree)
case .embed(let embed):
    layoutEmbed(id, embed, &tree)
}
```

Adding a case makes every non-exhaustive switch a compile error.

### Step 4 — Move cold element state to side tables

**What went wrong**

`Element` carries state for every feature on every node: `image`, `backgroundImage`, `backgroundImageSource`, `frame`, `frameSource`, `canvasContext`, `scrollOffsetY` (`DOMNode.swift:40-65`). Most elements use none of these.

**What should be**

Side tables keyed by node ID:

```swift
var images: [NodeID: CGImage]
var iframes: [NodeID: Frame]
var canvases: [NodeID: CanvasRenderingContext2D]
var scrollOffsets: [NodeID: CGFloat]
```

Only nodes that use a feature pay for it. This is the side-table part of data-oriented design, not a full ECS.

### Step 5 — Make identity explicit

**What went wrong**

Identity currently comes from class references:

- `childrenField` compares with `===` (`LayoutObject.swift:78-81`)
- `BlockLayout` compares `block.node === reference` (`BlockLayout.swift:550`)
- composited-update caches use `ObjectIdentifier`

**What should be**

`NodeID` is stored in `parent`, `children`, and `previous`; nodes live in `[LayoutNode]` and are indexed by that ID. Identity becomes data, not a pointer. Caches key by `NodeID`.

Caveat: if `JSRuntime` or `Element.frame` holds object references, those become stable handles/IDs too. That is the main migration cost.

### What improves

- No `as?` per node per pass.
- No duplicated stored properties across subclasses.
- Adding a node kind is a compile error until every pass handles it.
- Nodes in contiguous arrays improve locality.
- The `LayoutObject` extension dispatch trap disappears: there is no static-vs-dynamic split when everything is a concrete struct and a switch.

**The rule:** a closed tree is an array of tagged nodes, not a class hierarchy.

---

## 4. Invalidation discovers its graph at runtime

**The problem in one line:** dependency edges are declared per node instance as arrays of protocol existentials, then re-discovered and mutated at read time. The graph is data the engine keeps rebuilding instead of a rule it states once.

### Step 1 — Declare the edges once, not per instance

**What went wrong**

The inputs are already known. `BlockLayout.freezeGeometry` lists them (`BlockLayout.swift:57-90`), `TextLayout.init` lists them (`TextLayout.swift:36-60`), `EmbedLayout` lists them (`EmbedLayout.swift:27-46`). But each node builds its own `[any InvalidatableField]` arrays at initialization and again when re-attached (`BlockLayout.swift:207-243`, `TextLayout.swift:165-174`).

Every entry is a freshly constructed handle:

- `xField`, `widthField`, `yField` create a `LayoutFieldHandle` with a key path and equality closure (`LayoutObject.swift:47-95`).
- `node.style.field("padding-left")` creates a `StyleFieldRef`.
- `parent.xField` creates another handle.

The same rule — "block width depends on parent width, zoom, padding-left, padding-right, width" — runs once per node, with allocations, instead of once per node kind.

**What should be**

One declaration per relation, keyed by node kind and field:

```swift
func inputs(for id: NodeID, field: LayoutField, in tree: LayoutTree) -> [FieldKey]
```

`FieldKey` is a value: `(NodeID, FieldID)`, where `FieldID` is `.layout(LayoutField)` or `.style(StyleProperty)`. No handles, no closures, no per-instance arrays.

### Step 2 — Reads must not mutate the graph

**What went wrong**

`LayoutFieldHandle.read(notify:)` calls `addInvalidation` when the field is not frozen (`LayoutFieldHandle.swift:66-80`). `StyleFieldRef.read` does the same (`StyleFieldRef.swift:24-33`). On the style side, `fieldIsFrozen` always returns `false` (`StyleFields.swift:169-171`), so **every style read inserts into the dependents dictionary**. The `assertionFailure("Undeclared dependency")` exists because a missing edge can only be discovered at read time.

**What should be**

Reads are pure. Dependencies are declared before layout, and a missing input is a table mistake caught by a test or an exhaustive switch, not a runtime assertion. After that, `read(notify:)` disappears from the API; there is only `get()`.

### Step 3 — Stop storing dependents per node

**What went wrong**

Each layout node stores `dependents: [LayoutField: [FieldRef]]` (`LayoutFieldStore.swift:17`). Each style store stores `dependents: [String: [FieldRef]]` (`StyleFields.swift:6`). The values are weak owner references, so every add and take scans for dead owners:

```swift
current.removeAll(where: { $0.owner == nil })
```

`LayoutFieldHandle.set` copies the entire store (`var fields = owner.fields`), mutates it, and writes it back (`LayoutFieldHandle.swift:39-50`). When dependents exist, that copy can trigger a copy-on-write of the dependency dictionary. A single field write can copy a dictionary.

**What should be**

Either:

- **Keep push invalidation, but build one reverse index for the whole tree** from the declared inputs, keyed by `FieldKey`. Nodes no longer own dependency dictionaries.
- **Or switch to pull/version checks.** Each field has a version. A node's cached result stores the versions of its inputs. On the next pass, if any input version changed, recompute. No dependents storage at all.

For a toy engine, the pull/version check is usually simpler and fast enough. The field-level graph is only worth its complexity if partial reuse is the main goal.

### Step 4 — Stop constructing a handle per field access

**What went wrong**

Layout code reads fields constantly. Every read goes through a freshly constructed `LayoutFieldHandle` (owner, field, key path, equality closure). The handle is small, but it is built per access and calls back into the owner's store.

**What should be**

Read the store directly:

```swift
let width = tree.nodes[id].fields.width
```

or use a `FieldID` + generic `get`/`set` on the tree. No handle object, no key path, no closure in the hot path.

### What improves

- No `any InvalidatableField` dispatch in the invalidation path.
- No handle construction per read or write.
- No dictionary insertion on read.
- No store copy on set.
- Dependencies live in one function per node kind, not scattered across initializers.
- Missing edges become a testable table error instead of a runtime `assertionFailure`.

**The rule:** declare inputs as data, not as a graph you discover while reading.

---

## 5. Style and animation still round-trip through strings

**The problem in one line:** a color is parsed from CSS, stored as a string, copied into a draw command as a string, and parsed again when the command executes. An animation formats the value back into a string every frame, writes it into the style dictionary, and layout/paint parse it again.

### Step 1 — Store computed style as typed fields

**What went wrong**

`StyleFields.values` is `[String: String]` (`StyleFields.swift:4`), so every node stores its style in a string dictionary. A read like `node.style["color"]` is a hash lookup, and the result is still a string. The engine cannot tell a color from a length from a keyword at the type level.

**What should be**

A `ComputedStyle` produced by the cascade, with typed fields grouped by cohesion:

```swift
struct ComputedStyle {
    var layout: LayoutStyle   // display, position, overflow, zIndex
    var box: BoxStyle         // width, height, margin, padding, border
    var text: TextStyle       // color, font, whiteSpace, direction
    var visual: VisualStyle   // background, opacity, transform, filter
}
```

Keep a small `unknown: [String: String]` bag for CSS the engine does not model. The point is not to type all of CSS; it is to type the properties the engine reads in hot paths.

### Step 2 — Parse at the cascade boundary, not in hit-test or paint

**What went wrong**

`hitTest` parses the transform string on every call:

```swift
if let t = CSSValueParser.transform(node.style["transform"] ?? "") { ... }
```

That is `LayoutObject.swift:187`. `absoluteBounds` does the same for every ancestor (`LayoutObject.swift:219`), so a single call can parse a chain of transform strings.

Paint does it too. `TextLayout.paint` reads `style["color"]` as a string (`TextLayout.swift:122`), `DrawText` stores `color: String` (`DrawText.swift:8`), and `DrawText.execute` runs `BrowserColor(cssName: color)` per text run per frame (`DrawText.swift:38`). `DrawRect` does the same (`DrawRect.swift:6,15`).

**What should be**

The cascade parses once. `ComputedStyle.visual.transform` is already a `Transform?`; `ComputedStyle.text.color` is already a `BrowserColor`. Hit-testing reads the field. `DrawText` and `DrawRect` store `BrowserColor`, not `String`. The parser runs at the boundary, not in the frame loop.

### Step 3 — Animate typed values, not strings

**What went wrong**

`Animation.nextValue()` returns `String?` (`Animation.swift:5`). Every animation formats its value back into text:

- `NumericAnimation` returns `String(current)` (`NumericAnimation.swift:23-28`)
- `PixelAnimation` appends `"px"` (`NumericAnimation.swift:27-35`)
- `ColorAnimation` formats hex (`ColorAnimation.swift:25-33`)
- `TransformAnimation` builds `"translate(xpx, ypx)"` (`TransformAnimation.swift:22-30`)
- `KeyframeAnimation` diffs `[String: String]` bodies and parses them with `AnimatedValue(css:)`

Then `Frame.runAnimationFrame` writes the string back into `node.style[property]` (`Frame.swift:915`), which dirties style and forces layout/paint to parse it again.

**What should be**

An animation returns a typed value:

```swift
enum AnimatedValue {
    case number(Double)
    case length(CGFloat)
    case color(RGBColor)
    case transform(Transform)
}
```

`nextValue() -> AnimatedValue?`. The result is written directly into the typed style field. `StyleTransitions.diff` compares typed old/new values, not strings. No per-frame formatting or parsing.

### What improves

- No per-frame string allocation in animations.
- No per-draw `BrowserColor(cssName:)` parsing.
- No per-hit-test transform parsing.
- No dictionary lookup for hot properties.
- A typo in a property name becomes a compile-time error or a missing enum case, not a silent runtime miss.
- Unknown CSS still works through the string bag.

**The boundary rule:** CSS is open-ended, so strings must exist at the parser boundary. They should not survive into the frame loop.

---

## 6. The remaining shared mutable graph

**The problem in one line:** `Frame` is the frame's entire mutable state in one class. Document, styles, layout, display, animation, scroll, focus, and iframes all live there. Because everything shares it, everything stays on the main actor, and raster receives class references marked `@unchecked Sendable`.

### Step 1 — Split `Frame` by responsibility

**What went wrong**

`Frame.swift` is 60KB, and its first 90 lines already hold dozens of stored properties: `url`, `nodes`, `document`, `displayList`, `paintRevision`, `rules`, `keyframes`, `mediaMatches`, `sortedRules`, `ruleIndex`, `focus`, `hoveredElements`, `lazyImages`, `compositedUpdates`, `needsPaint`, `needsComposite`, and more (`Frame.swift:13-93`). It mixes document ownership, style state, layout state, display state, animation state, and browser policy.

**What should be**

Group by responsibility, the way `Browser.TabFrame` already does with four fields (`Browser.swift:30-40`):

```swift
struct FrameState {
    var document: DocumentState   // nodes, style sheets, keyframes
    var layout: LayoutState       // layout tree, dirty flags, scroll
    var display: DisplayState     // display list, layers, caches
    var runtime: RuntimeState     // url, loading, focus, hover, animations
}
```

`Frame` becomes a coordinator that owns `FrameState` and sequences the passes. The same treatment applies to `Browser` and `BrowserTab`, which mix tabs, scheduling, raster, accessibility, and drawing.

### Step 2 — One owner, explicit handles

**What went wrong**

Objects reach into each other:

- `Element` stores `frame` and `layoutObject` (`DOMNode.swift:58-59`)
- `Frame` stores `nodes`, `document`, `frameElement`, `tab`, `parentFrame` (`Frame.swift:17-25`)
- `BrowserTab` stores `rootFrame`, `focusedFrame`, `windowIDToFrame` (`BrowserTab.swift:34-36`)

Ownership is spread across the graph instead of being stated once. A mutation can originate from several places, which is why so much of the engine must be main-actor isolated.

**What should be**

The coordinator owns the trees. Cross-tree references become IDs and side tables:

```swift
elementID -> frameID
elementID -> layoutNodeID
```

`Element` stops knowing about frames and layout. `BrowserTab` asks the coordinator for a frame by ID instead of holding `Frame` references.

### Step 3 — Make the raster snapshot real

**What went wrong**

`RasterInput` is `@unchecked Sendable` (`RasterInput.swift:3`), and `RasterScene` holds `[any DisplayItem]` plus `[ObjectIdentifier: BrowserVisualEffect]` (`RasterScene.swift:1-5`). Those are class references. The compiler cannot verify that the worker reads immutable data, so safety is asserted, not proven.

**What should be**

After items 1 and 2, the display list is `[DisplayOp]` and layers are value structs. `RasterInput` becomes genuinely `Sendable`; `@unchecked` disappears. The worker receives a frozen snapshot, not live `Frame` or effect objects.

### Step 4 — Shrink the main actor

**What went wrong**

`Browser`, `BrowserTab`, `Frame`, and `LayoutObject` are all `@MainActor`. The whole pipeline — style, layout, paint, composite — is serialized on the main thread because the data it touches is shared mutable class state.

**What should be**

Keep the coordinator and all AppKit/JS callbacks on the main actor. Make layout and paint `nonisolated` functions over value state where their dependencies allow. Raster is already off-main.

Constraint: `BrowserFont` contains a mutable `FontMeasureCache` class, so off-main text measurement needs a per-thread cache or a lock. AppKit and JavaScriptCore still need stable handles, so keep a thin class shell at the boundary.

### What improves

- One owner per piece of state; no cross-object mutation.
- A pass can be tested with a plain struct, without a live browser.
- Snapshots are actually safe to send; `@unchecked Sendable` disappears.
- The main actor covers the UI boundary, not the entire engine.
- `Frame` and `BrowserTab` get smaller and easier to navigate.

**The rule:** the frame is data plus a coordinator, not one object that everything points at.

---

## What not to lose

- **`Renderer`** is the right protocol seam (`Renderer.swift:3`). Multiple implementations exist; keep it open.
- **`BrowserFont`** is a value type with a shared measure cache (`BrowserFont.swift:11`). Keep the value semantics; make the cache thread-safe if measurement moves off-main.
- **`Rect` and `Point`** are already values. Keep them.
- **`LayoutField` bitmasks** (`usedBits`, `dirtyBits`, `frozenBits`) are the right primitive. Keep the bits; remove the per-node dependency dictionaries around them.
- **Block and line paint caches** are the right instinct. After item 2, they store `[DisplayOp]` instead of `[any DisplayItem]`.
- **`RasterWorkerPool`** already moves work off-main. Value snapshots make that safe instead of asserted.

## Summary

1. **Closed sets → enums.** `DisplayOp`, `EffectKind`, `Selector`, `AnimationKind`, `FieldID`.
2. **Paint into one flat buffer.** `beginEffect` / `endEffect`, no tree to flatten.
3. **Closed trees → tagged nodes + IDs.** `LayoutKind` / `LayoutNode` / `NodeID`; switches instead of `as?`.
4. **Declare invalidation inputs once.** No per-read graph mutation, no handle per access.
5. **Type the hot values.** `ComputedStyle` and `AnimatedValue`; parse at the cascade, not in the frame loop.
6. **Frame as data + coordinator.** Grouped value state, explicit handles, real snapshots, thin main actor.

**Protocols for open seams. Sum types for closed data. Flat arrays for hot passes.**
