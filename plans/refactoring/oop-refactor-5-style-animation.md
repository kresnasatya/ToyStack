# Style and animation refactor: item 5

Implementation plan for **item 5 (style and animation)** from [oop-findings.md](./oop-findings.md). Ordering rationale lives in [oop-refactor-order.md](./oop-refactor-order.md).

**Yes, this is next.** Items 1 and 2 are committed (`54786fb` through `3eb2b1e`). The fixed sequence is:

```
1 → 2 → 5 → 3 → 4 → 6
```

Item 5 must land before item 3 so `LayoutObject`, `BlockLayout`, `TextLayout`, and `hitTest` are rewritten once against the final typed style API. It must land before item 4 so invalidation keys are `StyleProperty`, not strings.

This file is the plan only. No engine code is edited here.

## Scope

**In scope**

- Replace `StyleFields.values: [String: String]` as the engine's read model with `ComputedStyle`, grouped into four value structs.
- Add `StyleProperty` as the closed key set for style reads and dependencies.
- Parse CSS once at the cascade boundary (`ApplyStyle` -> `StyleFields.apply`), not in `hitTest`, `paint`, or `runAnimationFrame`.
- Inherit from the parent's `ComputedStyle`, not by re-seeding a string dictionary with parent strings.
- Make `AnimatedValue` the return type of `Animation.nextValue()`.
- Make transitions and keyframes write typed values directly into `ComputedStyle`.
- Replace the synthetic animation dictionary key `"animation/<name>"` with an `AnimationKey` enum.
- Update `BlockStyle`, `BrowserFont`, `BackgroundSize`, `ObjectFit`, `PaintEffectStyle`, `PaintTree`, `DisplayOp` factories, `Frame`, and every style read to the typed API.
- Remove `rgbToHex` and all per-frame value formatting.

**Out of scope**

- `NodeID`, tagged layout nodes, and `LayoutKind` (item 3).
- Invalidation table, versions, and removal of `FieldRef` handles (item 4). This plan only types the keys.
- `Frame` state grouping and `Sendable` snapshots (item 6).
- New CSS features. `display: flex`, `position: sticky`, `object-fit: scale-down` keep their current behavior through `.other`/explicit cases.
- Animation behavior changes. Text `color` transitions stay unsupported; keyframe `transform` stays unsupported, as today.
- The `Renderer` protocol. It remains the open seam.

## Baseline

Verified before writing this plan:

- `git status` clean on `main`.
- `swift build` -> `Build complete!`
- `swift test` -> **189 tests in 26 suites passed**.

Capture visual baselines before the first code step:

```sh
swift run ToyStackHeadless "file://$PWD/www/ch13/exercise-13-2.html" \
  --trace /tmp/before-style.trace --frame-limit 5 --screenshot /tmp/before-style.png
swift run ToyStackHeadless "file://$PWD/www/ch13/exercise-13-6.html" \
  --trace /tmp/before-anim.trace --frame-limit 30 --screenshot /tmp/before-anim.png
```

`www/ch13/exercise-13-2.html` covers transitions. `www/ch13/exercise-13-6.html` covers keyframes. Keep the screenshot comparison as the stop signal for B1 and B2.

## End state

```swift
enum StyleProperty: CaseIterable, Hashable {
    case display, position, overflow, zIndex
    case width, height, maxWidth, aspectRatio
    case marginTop, marginRight, marginBottom, marginLeft
    case paddingTop, paddingRight, paddingBottom, paddingLeft
    case left, top, zoom
    case borderWidth, borderStyle, borderColor, borderRadius
    case outlineWidth, outlineStyle, outlineColor
    case color, fontFamily, fontSize, fontStyle, fontWeight, whiteSpace, direction
    case backgroundColor, backgroundImage, backgroundSize, imageRendering, objectFit
    case opacity, mixBlendMode, transform, filter
}
```

```swift
struct ComputedStyle: Equatable {
    var layout: LayoutStyle
    var box: BoxStyle
    var text: TextStyle
    var visual: VisualStyle
}

struct LayoutStyle: Equatable {
    enum Display: Equatable { case inline, block, none, other(String) }
    enum Position: Equatable { case staticFlow, relative, absolute, fixed, sticky, other(String) }
    enum Overflow: Equatable { case visible, hidden, clip, scroll, auto, other(String) }

    struct Positioning: Equatable {
        var kind: Position
        var left: CGFloat?
        var top: CGFloat?
    }

    var display: Display
    var position: Positioning
    var overflow: Overflow
    var zIndex: Int
}
```

```swift
struct BoxStyle: Equatable {
    struct Size: Equatable {
        var width: CGFloat?
        var height: CGFloat?
        var maxWidth: Length?
        var aspectRatio: AspectRatio?
    }

    struct Spacing: Equatable {
        var margin: EdgeInsets
        var padding: EdgeInsets
    }

    struct Decoration: Equatable {
        struct Border: Equatable {
            enum LineStyle: Equatable { case none, hidden, solid, dashed, dotted, other(String) }
            var width: CGFloat
            var color: BrowserColor
            var style: LineStyle
            var radii: CornerRadii
        }

        struct Outline: Equatable {
            var width: CGFloat
            var color: BrowserColor?
            var style: Border.LineStyle
        }

        var border: Border
        var outline: Outline
    }

    var size: Size
    var spacing: Spacing
    var decoration: Decoration
    var zoom: CGFloat?
}
```

```swift
struct TextStyle: Equatable {
    struct Font: Equatable {
        enum Style: Equatable { case normal, italic, oblique }
        enum Weight: Equatable { case normal, bold, number(Int) }

        var family: String
        var size: CGFloat
        var style: Style
        var weight: Weight
    }

    var color: BrowserColor
    var font: Font
    var whiteSpace: WhiteSpaceMode
    var direction: TextDirection
}
```

```swift
struct VisualStyle: Equatable {
    struct Background: Equatable {
        var color: BrowserColor?
        var image: String?
        var size: BackgroundSizeSpec
    }

    struct Image: Equatable {
        var rendering: ImageRendering
        var fit: ObjectFitKind
    }

    struct Effects: Equatable {
        var opacity: Double
        var blendMode: BrowserBlendMode?
        var blurRadius: CGFloat
        var translation: CGPoint?
    }

    var background: Background
    var image: Image
    var effects: Effects
}
```

```swift
enum AnimatedValue: Equatable {
    case number(Double)
    case length(CGFloat)
    case color(BrowserColor)
    case transform(CGPoint)
}

protocol Animation: AnyObject {
    func nextValue() -> AnimatedValue?
    var animatedProperty: StyleProperty { get }
}

enum AnimationKey: Hashable {
    case property(StyleProperty)
    case keyframes(String)
}
```

```swift
enum Length: Equatable {
    case px(CGFloat)
    case percent(CGFloat)

    init?(css: String?)
    func resolved(available: CGFloat, zoom: CGFloat) -> CGFloat
}

enum BackgroundSizeSpec: Equatable {
    case auto
    case cover
    case contain
    case lengths(Length?, Length?)

    init?(css: String?)
}

enum ObjectFitKind: Equatable {
    case fill, contain, cover, none, scaleDown

    init(css: String?)
}
```

`StyleFields` keeps three stored properties:

```swift
nonisolated final class StyleFields: FieldOwner {
    private var storage: StyleStorage
    private(set) var revision: UInt64
    private var invalidation: StyleInvalidationState

    var computed: ComputedStyle { storage.computed }
    var unknown: [String: String] { storage.unknown }
}
```

`StyleStorage` and `StyleInvalidationState` are small support structs in `StyleFields.swift`, each with at most four stored properties. The `raw` mirror inside `StyleStorage` is temporary and is deleted in A4.

## Decisions

### D1. Four groups, nested value structs, unknown bag outside `ComputedStyle`

`ComputedStyle` has exactly four stored properties: `layout`, `box`, `text`, `visual`. That satisfies the four-property rule without a catch-all struct. Nested structs (`BoxStyle.Decoration.Border`, `TextStyle.Font`, `VisualStyle.Effects`) live in the file of their owning group and are named by nesting, not by separate top-level types.

The findings' `unknown: [String: String]` stays in `StyleFields`, not `ComputedStyle`. Otherwise `ComputedStyle` has five stored properties.

**Alternative:** a flat `ComputedStyle` with 30 properties. Rejected: it breaks the architecture rule and makes every initializer a 30-argument call.

### D2. `StyleProperty` is a `CaseIterable` enum

Every property the engine reads has one enum case. Unmodeled CSS (custom properties, `animation`, `transition`, `-forced-colors`) stays in the `unknown` bag. `animation` and `transition` are read once per style application by `Frame`, not per frame, so they stay strings at that boundary.

No `.custom(String)` case. A typed read cannot name an unmodeled property, and animation only ever targets modeled properties. This keeps `CaseIterable` synthesis and makes `StyleProperty.allCases` usable for full-style diffs.

**Alternative:** a `struct StyleProperty { let rawValue: String }`. Rejected: still a string key at runtime, so item 4 gains nothing.

### D3. Parse once, with the parent style

`ComputedStyleParser.parse(css, parent:)` starts from `ComputedStyle.inheriting(from: parent)` and applies the declaration dictionary. The parser is the only source of inherited values for typed reads.

A2 keeps the old string seed in `ApplyStyle` (`ApplyStyle.swift:60-66`) for one reason only: the raw mirror must keep the same contents as before so the un-migrated string reads and tests still see inherited values. A4 deletes the seed and `inheritedPropertyDefaults` after every read is typed.

The parser consumes the keys it models and returns the rest as `unknown`. `StyleFields.apply` stores both.

### D4. `BrowserColor` and `CGPoint`, not `RGBColor` and a new `Transform` type

The findings sketch uses `.color(RGBColor)` and `.transform(Transform)`. The repo has no `Transform` type; `CSSValueParser.transform` returns `CGPoint` and only models `translate`. Use `CGPoint` and name the case `.transform` to match the protocol. Introduce a new `Transform` type in a later item if scale/rotate become real.

`ColorAnimation` interpolates `BrowserColor` channels (0-1). Keep its current behavior of dropping alpha: return alpha 1, as `rgbToHex` effectively did.

### D5. `Animation` stays a class; the dictionary becomes `AnimationKey`

Animations have per-frame mutable state (`currentFrame`) and are stored in a dictionary. A class is the boring fit. The closed key set is the data:

```swift
enum AnimationKey: Hashable {
    case property(StyleProperty)
    case keyframes(String)
}
```

`DOMNode.animations` becomes `[AnimationKey: Animation]`. `Frame.addAnimation` uses `.property(animation.animatedProperty)`. Keyframes use `.keyframes(playback.name)`. This removes `"animation/\(playback.name)"` and `node.animations["transform"]`.

### D6. `BackgroundSize` and `ObjectFit` become geometry over typed specs

`BackgroundSizeSpec` and `ObjectFitKind` parse CSS at the cascade. `BackgroundSize.rect(spec:)` and `ObjectFit(box:intrinsicWidth:intrinsicHeight:fit:)` keep only geometry. No paint-time string parsing.

### D7. Preserve the two property sets exactly

Move `Frame.paintOnlyProperties` and `Frame.paintStyleProperties` (`Frame.swift:876-903`) to `StyleProperty` without changing membership:

```swift
extension StyleProperty {
    static let paintOnly: Set<StyleProperty> = [...]
    static let paintStyle: Set<StyleProperty> = [...]
    static let inherited: [StyleProperty] = [
        .color, .fontFamily, .fontSize, .fontStyle, .fontWeight, .whiteSpace, .direction
    ]

    var affectsLayout: Bool { !Self.paintOnly.contains(self) }
}
```

`border-width` and `border-style` stay layout-affecting but paint-visible, exactly as today.

### D8. One temporary bridge, removed in A4

A2 adds `StyleStorage.raw` so existing string reads and tests keep working while consumers migrate. B1 updates it from typed animation values by formatting once per animation write. A3 stops reading it. A4 deletes it, the string subscript, `isEmpty`, and the raw snapshot. No string bridge survives the item.

## File map

### New files

| File | Why |
|---|---|
| `Style/StyleProperty.swift` | closed property keys, property sets, `cssName` |
| `Style/ComputedStyle.swift` | four-group value, `initial`, `inheriting`, `matches`, `changed`, `set`/`value` |
| `Style/LayoutStyle.swift` | layout group plus nested display/position/overflow enums |
| `Style/BoxStyle.swift` | box group plus size/spacing/decoration/border/outline |
| `Style/TextStyle.swift` | text group plus font |
| `Style/VisualStyle.swift` | visual group plus background/image/effects |
| `Style/ComputedStyleParser.swift` | one CSS dictionary -> `(ComputedStyle, unknown)` |
| `Style/Length.swift` | `px`/`percent` value used by `max-width` and `background-size` |
| `Style/BackgroundSizeSpec.swift` | parsed `background-size` |
| `Style/ObjectFitKind.swift` | parsed `object-fit` |
| `Animation/AnimationKey.swift` | `.property` / `.keyframes` dictionary key |

### Modified files

| File | Why |
|---|---|
| `Style/StyleFields.swift` | typed storage, parser call, typed dirty keys and dependents, typed `set` |
| `Style/StyleFieldRef.swift` | key becomes `StyleProperty`; `read` becomes `touch` |
| `Core/FieldRef.swift` | `FieldName.style(StyleProperty)` |
| `Style/StyleCascade.swift` | old snapshots are `ComputedStyle`; typed `inheritedChanged` |
| `Style/ApplyStyle.swift` | pass the parent computed style to `apply`; delete the string seed in A4 |
| `Style/CSSValueParser.swift` | `cornerRadii` reads a dictionary; remove `StyleFields` overload |
| `Style/ForcedColor.swift` | `usesForcedColors` reads the unknown bag accessor |
| `Core/Frame.swift` | typed style diff, typed animation loop, `AnimationKey`, typed fallback |
| `Core/LayoutInvalidation.swift` | `animatedPropertyChanged(property: StyleProperty)` |
| `Parsing/DOMNode.swift` | `animations: [AnimationKey: Animation]` |
| `Layouts/BlockStyle.swift` | typed `BlockStyle` fields |
| `Layouts/BlockLayout.swift` | typed padding/margin/background/border/scroll reads |
| `Layouts/BrowserFont.swift` | typed font fields (file is `Platform/BrowserFont.swift`) |
| `Layouts/TextLayout.swift` | typed text color |
| `Layouts/LineLayout.swift` | typed direction |
| `Layouts/DocumentLayout.swift` | typed padding dependency keys |
| `Layouts/EmbedLayout.swift` | typed zoom dependency keys |
| `Layouts/ButtonLayout.swift` | typed font, background, outline |
| `Layouts/InputLayout.swift` | typed input background/border/text |
| `Layouts/IframeLayout.swift` | typed background and radii |
| `Layouts/ImageLayout.swift` | typed `aspect-ratio`, `max-width`, `object-fit`, `image-rendering` |
| `Layouts/BackgroundSize.swift` | `rect(spec:)` |
| `Layouts/ObjectFit.swift` | `fit:` instead of `css:` |
| `Layouts/LayoutObject.swift` | typed `hitTest` / `absoluteBounds` transform and zoom |
| `Layouts/LengthPx.swift` | delete; `Length.resolved` replaces it |
| `Display/DisplayOp.swift` | typed outline/border factories |
| `Display/PaintEffectStyle.swift` | read `VisualStyle.Effects` |
| `Display/PaintTree.swift` | typed overflow/position/z-index/radii |
| `Animation/Animation.swift` | typed `nextValue` and `animatedProperty` |
| `Animation/AnimatedValue.swift` | typed cases and `StyleProperty` parser |
| `Animation/NumericAnimation.swift` | `nextValue -> AnimatedValue?` |
| `Animation/ColorAnimation.swift` | typed `BrowserColor` |
| `Animation/TransformAnimation.swift` | `CGPoint` in, `.transform` out |
| `Animation/StyleTransitions.swift` | typed old/new values, typed result |
| `Animation/KeyframeAnimation.swift` | typed factory |
| `Tests/ToyStackTests/StyleFieldsTests.swift` | typed field API |
| `Tests/ToyStackTests/DOMNodeTests.swift` | `isEmpty` removal |
| `Tests/ToyStackTests/HoverTests.swift` | typed color assertions |
| `Tests/ToyStackTests/StyleInvalidationTests.swift` | typed writes and assertions |
| `Tests/ToyStackTests/LayoutInvalidationTests.swift` | `StyleProperty.affectsLayout`, typed animation init |
| `README.md` | describe `ComputedStyle` and `AnimatedValue` |
| `profiling.md` | only if a metric name changes; no planned change |

---

## Step A1 — Add the typed style vocabulary

**Commit subject:** `refactor: give computed style a typed shape`

Add the new files from the map. Nothing consumes them yet, so the build stays green and all 189 tests pass.

Key rules for this step:

- `ComputedStyle`, `LayoutStyle`, `BoxStyle`, `TextStyle`, and `VisualStyle` each declare at most four stored properties.
- Nested support types live in the owning group's file and are addressed as `BoxStyle.Decoration.Border`, not as loose names.
- Add explicit `Equatable` to `EdgeInsets` (`BlockStyle.swift:71`) and `AspectRatio` (`AspectRatio.swift:4`).
- `TextDirection` and `WhiteSpaceMode` are already `Equatable`; use them.
- `BrowserColor` is already `Hashable`; use it.

### `StyleProperty` mapping

`init?(cssName:)` maps CSS longhands to cases. The four radius longhands all map to `.borderRadius` because the engine reads them as one `CornerRadii` value:

```swift
case "border-radius", "border-top-left-radius", "border-top-right-radius",
     "border-bottom-right-radius", "border-bottom-left-radius":
    self = .borderRadius
```

`cssName` is the inverse only for dependency messages:

```swift
var cssName: String {
    switch self {
    case .display: return "display"
    case .backgroundColor: return "background-color"
    case .paddingTop: return "padding-top"
    // ...
    case .borderRadius: return "border-radius"
    }
}
```

### `ComputedStyle` diff

`StyleFields.apply` needs per-property change detection, not whole-style equality:

```swift
extension ComputedStyle {
    func matches(_ other: ComputedStyle, for property: StyleProperty) -> Bool {
        switch property {
        case .display: return layout.display == other.layout.display
        case .position: return layout.position.kind == other.layout.position.kind
        case .overflow: return layout.overflow == other.layout.overflow
        case .zIndex: return layout.zIndex == other.layout.zIndex
        case .width: return box.size.width == other.box.size.width
        case .height: return box.size.height == other.box.size.height
        case .maxWidth: return box.size.maxWidth == other.box.size.maxWidth
        case .aspectRatio: return box.size.aspectRatio == other.box.size.aspectRatio
        case .paddingTop: return box.spacing.padding.top == other.box.spacing.padding.top
        // ... one case per StyleProperty
        case .transform: return visual.effects.translation == other.visual.effects.translation
        }
    }

    func changed(from old: ComputedStyle) -> Set<StyleProperty> {
        Set(StyleProperty.allCases.filter { !old.matches(self, for: $0) })
    }
}
```

Do not compare whole groups. `BoxStyle` mixes layout inputs (`width`) and paint inputs (`border.color`); whole-group equality would over-invalidate one pass for the other.

### `ComputedStyle` animatable bridge

Only the properties transitions and keyframes support need values:

```swift
extension ComputedStyle {
    func value(for property: StyleProperty) -> AnimatedValue? {
        switch property {
        case .opacity: return .number(visual.effects.opacity)
        case .width: return box.size.width.map(AnimatedValue.length)
        case .height: return box.size.height.map(AnimatedValue.length)
        case .backgroundColor:
            return visual.background.color.map(AnimatedValue.color)
        case .transform:
            return visual.effects.translation.map(AnimatedValue.transform)
        default:
            return nil
        }
    }

    @discardableResult
    mutating func set(_ value: AnimatedValue, for property: StyleProperty) -> Bool {
        let before: ComputedStyle = self
        switch (property, value) {
        case (.opacity, .number(let v)): visual.effects.opacity = v
        case (.width, .length(let v)): box.size.width = v
        case (.height, .length(let v)): box.size.height = v
        case (.backgroundColor, .color(let c)): visual.background.color = c
        case (.transform, .transform(let p)): visual.effects.translation = p
        default: return false
        }
        return !matches(before, for: property)
    }
}
```

This preserves the current animatable set exactly. It is also the hook item 4's field table will use.

### Parser sketch

```swift
enum ComputedStyleParser {
    static func parse(
        _ css: [String: String],
        parent: ComputedStyle?
    ) -> (style: ComputedStyle, unknown: [String: String]) {
        var unknown: [String: String] = css
        func take(_ key: String) -> String? {
            return unknown.removeValue(forKey: key)
        }

        var style: ComputedStyle = ComputedStyle.inheriting(from: parent)
        style.layout.display = LayoutStyle.Display(css: take("display"))
        style.layout.position = LayoutStyle.Positioning(
            kind: LayoutStyle.Position(css: take("position")),
            left: px(take("left")),
            top: px(take("top"))
        )
        style.layout.overflow = LayoutStyle.Overflow(css: take("overflow"))
        style.layout.zIndex = Int(take("z-index") ?? "0") ?? 0
        // box, text, visual...
        return (style, unknown)
    }

    private static func px(_ raw: String?) -> CGFloat? {
        guard let raw, raw.hasSuffix("px"), let value = Double(raw.dropLast(2)) else { return nil }
        return CGFloat(value)
    }
}
```

`background-color`: return `nil` for absent or `"transparent"`, otherwise `BrowserColor.parse`. `border-color` defaults to black. `outline-color` stays optional so `DisplayOp.fromStyle` can fall back to text color. `font-size` defaults to 16; percentages are already normalized by `ApplyStyle`.

`The four radius keys + shorthand` stay in `CSSValueParser` and are consumed in one call:

```swift
let radii: CornerRadii = CSSValueParser.cornerRadii(css) ?? .zero
style.box.decoration.border.radii = radii
for key in ["border-radius", "border-top-left-radius", /* ... */] {
    unknown.removeValue(forKey: key)
}
```

Change `CSSValueParser.cornerRadii` from `(StyleFields)` to `([String: String])`; it reads five keys from the dictionary. Delete the old overload after A3.

**Stop signal:** `swift test` still 189 passing. The new types are unused, so any failure means a syntax or conforming-type mistake, not behavior.

---

## Step A2 — Compute typed style at the cascade boundary

**Commit subject:** `refactor: compute style as typed values`

This is the bridge step. `StyleFields` stores `ComputedStyle` and still keeps the raw dictionary for existing string reads. Every write path goes through `apply`.

### `StyleFields.swift`

```diff
 nonisolated final class StyleFields: FieldOwner {
-    private(set) var values: [String: String] = [:]
+    private var storage: StyleStorage = StyleStorage()
     private(set) var revision: UInt64 = 0
-    private var dirtyKeys: Set<String> = []
-    private var dependents: [String: [FieldDependencyKey: FieldRef]] = [:]
-    private var needsRestyle: Bool = true
-    private var descendantsDirty: Bool = false
+    private var invalidation: StyleInvalidationState = StyleInvalidationState()
+
+    var computed: ComputedStyle { return storage.computed }
+    var unknown: [String: String] { return storage.unknown }
+
+    @MainActor
+    func unknownValue(_ key: String) -> String? {
+        return storage.unknown[key]
+    }
```

Add the two support structs in the same file, under a `// MARK: -` section:

```swift
private struct StyleStorage {
    var computed: ComputedStyle = .initial
    var unknown: [String: String] = [:]
    var raw: [String: String] = [:] // temporary; deleted in A4
}

private struct StyleInvalidationState {
    var dirtyKeys: Set<String> = []
    var dependents: [String: [FieldDependencyKey: FieldRef]] = [:]
    var needsRestyle: Bool = true
    var descendantsDirty: Bool = false
}
```

The invalidation keys stay `String` in A2. A3 changes them to `StyleProperty` together with `FieldName` and `StyleFieldRef`; changing them now would force the un-migrated `read(_:notify:)` call sites to move in the same commit.

Replace the body of `apply` (`StyleFields.swift:56-86`):

```diff
-    func apply(_ newValues: [String: String]) {
-        var written: Int = 0
-        var changed: Int = 0
-        for key in Array(values.keys) where newValues[key] == nil { ... }
-        for (key, value) in newValues { ... }
-        needsRestyle = false
-        if changed > 0 { revision += 1 }
-        profiler.count("style.fields.set", by: written)
-        profiler.count("style.fields.changed", by: changed)
-    }
+    func apply(_ newValues: [String: String], parent: ComputedStyle? = nil) {
+        let old: ComputedStyle = storage.computed
+        let oldUnknown: [String: String] = storage.unknown
+        let oldRaw: [String: String] = storage.raw
+        let parsed: (style: ComputedStyle, unknown: [String: String]) =
+            ComputedStyleParser.parse(newValues, parent: parent)
+        let changed: Set<StyleProperty> = parsed.style.changed(from: old)
+
+        storage.computed = parsed.style
+        storage.unknown = parsed.unknown
+        storage.raw = newValues
+
+        invalidation.dirtyKeys.removeAll()
+        invalidation.needsRestyle = false
+        if !changed.isEmpty || parsed.unknown != oldUnknown || newValues != oldRaw {
+            revision += 1
+        }
+        for property in changed {
+            notifyDependents(property.cssName)
+        }
+        profiler.count("style.fields.set", by: storage.raw.count)
+        profiler.count("style.fields.changed", by: changed.count)
+    }
```

Add the direct typed mutation path. It is what programmatic writes (visited-link color) and tests use; it does not go through `AnimatedValue`:

```swift
@MainActor
func mutate(_ body: (inout ComputedStyle) -> Void) {
    let old: ComputedStyle = storage.computed
    body(&storage.computed)
    let changed: Set<StyleProperty> = storage.computed.changed(from: old)
    guard !changed.isEmpty else { return }
    invalidation.dirtyKeys.subtract(Set(changed.map(\.cssName)))
    revision += 1
    for property in changed {
        notifyDependents(property.cssName)
    }
}
```

In A3 the two `cssName` calls become `invalidation.dirtyKeys.subtract(changed)` and `notifyDependents(property)`.

`markAll` becomes:
```diff
-        for key in values.keys { dirtyKeys.insert(key) }
+        invalidation.dirtyKeys = Set(StyleProperty.allCases.map(\.cssName))
```

The existing string `subscript` and `read` keep working off `storage.raw` and `storage.unknown` until A4:

```swift
subscript(_ key: String) -> String? {
    get { return storage.raw[key] ?? storage.unknown[key] }
    set {
        let old: ComputedStyle = storage.computed
        let oldRaw: String? = storage.raw[key]
        storage.raw[key] = newValue
        let parsed: (style: ComputedStyle, unknown: [String: String]) =
            ComputedStyleParser.parse(storage.raw, parent: nil)
        let changed: Set<StyleProperty> = parsed.style.changed(from: old)
        storage.computed = parsed.style
        storage.unknown = parsed.unknown
        invalidation.dirtyKeys.remove(key)
        if !changed.isEmpty || oldRaw != newValue {
            revision += 1
        }
        for property in changed {
            notifyDependents(property.cssName)
        }
    }
}
```

The setter re-parses the raw dictionary so the typed mirror cannot go stale before B1/A3. This is a temporary boundary parse, not a read path; B1 removes the animation writes and A3 removes the test writes.

`isEmpty` and `snapshot` keep their raw behavior in A2:

```diff
     var isEmpty: Bool {
-        return values.isEmpty
+        return storage.raw.isEmpty
     }

     func snapshot() -> [String: String] {
-        return values
+        return storage.raw
     }
```

### `ApplyStyle.swift`

Keep the string inheritance seed through A3. It exists only to keep the raw mirror byte-for-byte compatible for the un-migrated tests and the raw transition path. The typed parser gets inheritance from `parent:`, so there is no typed dependency on the seed.

The only change in A2 is the call:

```diff
-        node.style.apply(newStyle)
+        node.style.apply(newStyle, parent: node.parent?.style.computed)
```

Delete the seed, `inheritedPropertyDefaults`, and the parent string lookup in A4. At that point the font-size percentage also resolves against `node.parent?.style.computed.text.font.size`, because the raw parent lookup is gone.

### `StyleCascade.swift`

Old snapshots become computed values, plus a temporary raw snapshot for the old transition path:

```diff
-    private var oldStyles: [ObjectIdentifier: [String: String]] = [:]
+    private var oldStyles: [ObjectIdentifier: ComputedStyle] = [:]
+    private var oldRawStyles: [ObjectIdentifier: [String: String]] = [:]
@@
     func record(_ node: any DOMNode) {
         appliedNodes.append(node)
-        oldStyles[ObjectIdentifier(node)] = node.style.snapshot()
+        oldStyles[ObjectIdentifier(node)] = node.style.computed
+        oldRawStyles[ObjectIdentifier(node)] = node.style.snapshot()
     }
 
-    func oldStyle(for node: any DOMNode) -> [String: String] {
-        return oldStyles[ObjectIdentifier(node)] ?? [:]
+    func oldStyle(for node: any DOMNode) -> ComputedStyle? {
+        return oldStyles[ObjectIdentifier(node)]
     }
+
+    func oldRawStyle(for node: any DOMNode) -> [String: String] {
+        return oldRawStyles[ObjectIdentifier(node)] ?? [:]
+    }
```

`inheritedChanged`:

```diff
-        guard let old: [String: String] = oldStyles[ObjectIdentifier(node)] else {
-            return true
-        }
-        for property in inheritedPropertyDefaults.keys {
-            if old[property] != node.style[property] { return true }
-        }
-        return false
+        guard let old: ComputedStyle = oldStyles[ObjectIdentifier(node)] else {
+            return true
+        }
+        return StyleProperty.inherited.contains {
+            !old.matches(node.style.computed, for: $0)
+        }
```

Delete `oldRawStyles` and `oldRawStyle` in B1 after `StyleTransitions` is typed.

### `Frame.swift` typed diff

`Frame`'s style diff uses typed values now, so inherited changes still trigger paint:

```diff
-                let old: [String : String] = cascade.oldStyle(for: node)
-                if Self.paintStyleChanged(old: old, new: node.style.snapshot()) {
+                guard let old: ComputedStyle = cascade.oldStyle(for: node) else { continue }
+                if Self.paintStyleChanged(old: old, new: node.style.computed) {
                     paintedChanged = true
                 }
@@
-                if old["display"] != node.style["display"]
-                    || old["overflow"] != node.style["overflow"]
+                if old.layout.display != node.style.computed.layout.display
+                    || old.layout.overflow != node.style.computed.layout.overflow
                 {
                     markStructureChanged()
                 }
```

`paintStyleChanged` and `affectsLayout` move to `StyleProperty`:

```diff
-    private static func paintStyleChanged(
-        old: [String: String],
-        new: [String: String]
-    ) -> Bool {
-        for (key, value) in new where old[key] != value {
-            if paintStyleProperties.contains(key) { return true }
-        }
-        for key in old.keys where new[key] == nil {
-            if paintStyleProperties.contains(key) { return true }
-        }
-        return false
-    }
+    private static func paintStyleChanged(
+        old: ComputedStyle,
+        new: ComputedStyle
+    ) -> Bool {
+        return StyleProperty.paintStyle.contains {
+            !old.matches(new, for: $0)
+        }
+    }
```

Until B1, the transition call keeps the raw API. `Frame` passes the raw old snapshot:

```diff
-                let newAnimations: [String : any Animation] = StyleTransitions.diff(
-                    node: node,
-                    oldStyle: old,
-                    newStyle: node.style.snapshot()
-                )
+                let newAnimations: [String : any Animation] = StyleTransitions.diff(
+                    node: node,
+                    oldStyle: cascade.oldRawStyle(for: node),
+                    newStyle: node.style.snapshot()
+                )
```

This is why `StyleCascade` keeps `oldRawStyles` in A2. B1 deletes it.

Keep `paintOnlyProperties`, `paintStyleProperties`, and `Frame.affectsLayout` through B1: `LayoutInvalidationTests` still calls `Frame.affectsLayout` until A3. Delete them in A3 together with the test update.

**Stop signal:** 189 tests pass, and the two screenshots from the baseline are pixel-identical. The cascade now parses typed style, so any difference is a parser bug.

---

## Step B1 — Make animations return typed values

**Commit subject:** `refactor: animate values, not style strings`

**This commit includes the `KeyframeAnimation` conformance and keyframe call-site changes shown under B2.** `Animation` is a protocol; changing `nextValue` without updating every conformer is not build-green. B2 is kept as a separate section for readability, but its keyframe edits land here. The only later B2 commit is dead-helper and docs cleanup.

### `AnimatedValue.swift`

```diff
-enum AnimatedValue {
+enum AnimatedValue: Equatable {
     case number(Double)
-    case length(Double)
-    case color(RGBColor)
+    case length(CGFloat)
+    case color(BrowserColor)
+    case transform(CGPoint)
@@
-    init?(css: String, property: String) {
+    init?(css: String, property: StyleProperty) {
         switch property {
-        case "opacity":
+        case .opacity:
             guard let v = Double(css) else { return nil }
             self = .number(v)
-        case "width", "height":
+        case .width, .height:
             guard css.hasSuffix("px"), let v = Double(css.dropLast(2)) else { return nil }
-            self = .length(v)
-        case "background-color":
-            guard let c = cssColorToRGB(css) else { return nil }
+            self = .length(CGFloat(v))
+        case .backgroundColor:
+            guard let c = BrowserColor.parse(css) else { return nil }
             self = .color(c)
         default:
             return nil
         }
     }
 }
```

Keep `transform` out of `init?(css:)`. Keyframes do not support it today; transitions get it from `ComputedStyle.value(for:)`.

### `Animation.swift`

```diff
 protocol Animation: AnyObject {
-    func nextValue() -> String?
-    var animatedProperty: String { get }
+    func nextValue() -> AnimatedValue?
+    var animatedProperty: StyleProperty { get }
 }
```

### Leaf animations

`NumericAnimation`:

```diff
-    func nextValue() -> String? {
+    func nextValue() -> AnimatedValue? {
         currentFrame += 1
         if currentFrame > timing.totalFrames { return nil }
         let t: Double = Double(currentFrame) / Double(timing.totalFrames)
         let eased: Double = timing.easing.apply(t)
         let current: Double = oldValue + (newValue - oldValue) * eased
-        return String(current)
+        return .number(current)
     }
```

`PixelAnimation`:

```diff
-    override func nextValue() -> String? {
+    override func nextValue() -> AnimatedValue? {
         guard let value = super.nextValue() else { return nil }
-        return value + "px"
+        guard case .number(let number) = value else { return nil }
+        return .length(CGFloat(number))
     }
```

`ColorAnimation`:

```diff
-    func nextValue() -> String? {
+    func nextValue() -> AnimatedValue? {
         currentFrame += 1
         if currentFrame > timing.totalFrames { return nil }
         let t: Double = Double(currentFrame) / Double(timing.totalFrames)
         let eased: Double = timing.easing.apply(t)
-        let r: Double = oldColor.r + (newColor.r - oldColor.r) * eased
-        let g: Double = oldColor.g + (newColor.g - oldColor.g) * eased
-        let b: Double = oldColor.b + (newColor.b - oldColor.b) * eased
-        return rgbToHex(r, g, b)
+        return .color(BrowserColor(
+            red: oldColor.red + (newColor.red - oldColor.red) * eased,
+            green: oldColor.green + (newColor.green - oldColor.green) * eased,
+            blue: oldColor.blue + (newColor.blue - oldColor.blue) * eased,
+            alpha: 1
+        ))
     }
```

`TransformAnimation`:

```diff
-    func nextValue() -> String? {
+    func nextValue() -> AnimatedValue? {
         currentFrame += 1
         if currentFrame > timing.totalFrames { return nil }
         let t: Double = Double(currentFrame) / Double(timing.totalFrames)
         let eased: Double = timing.easing.apply(t)
-        let x: Double = Double(oldPoint.x) + Double(newPoint.x - oldPoint.x) * eased
-        let y: Double = Double(oldPoint.y) + Double(newPoint.y - oldPoint.y) * eased
-        return "translate(\(x)px, \(y)px)"
+        let x: CGFloat = oldPoint.x + (newPoint.x - oldPoint.x) * CGFloat(eased)
+        let y: CGFloat = oldPoint.y + (newPoint.y - oldPoint.y) * CGFloat(eased)
+        return .transform(CGPoint(x: x, y: y))
     }
```

### `StyleFields.set`

Add the typed write path. During B1 it also updates the raw mirror; A4 deletes the mirror and formatter.

```swift
@MainActor
func set(_ value: AnimatedValue, for property: StyleProperty) {
    guard storage.computed.set(value, for: property) else { return }
    storage.raw[property.cssName] = property.cssString(value) // temporary
    invalidation.dirtyKeys.remove(property.cssName)
    revision += 1
    notifyDependents(property.cssName)
}
```

`invalidation` still uses string keys until A3. A3 changes these two calls to `property` after `StyleInvalidationState` becomes typed.

`StyleProperty.cssString(_:)` is the old formatting code moved here:

```swift
func cssString(_ value: AnimatedValue) -> String {
    switch value {
    case .number(let v): return String(v)
    case .length(let v): return "\(v)px"
    case .color(let c): return rgbToHex(c.red * 255, c.green * 255, c.blue * 255)
    case .transform(let p): return "translate(\(p.x)px, \(p.y)px)"
    }
}
```

### `StyleTransitions.swift`

```diff
-    static func diff(node: DOMNode, oldStyle: [String: String], newStyle: [String: String]) -> [String: Animation]
-    {
-        var animations: [String: Animation] = [:]
-        let transitions: [String : FrameTiming] = FrameTiming.parse(newStyle["transition"] ?? "")
+    static func diff(
+        node: DOMNode,
+        oldStyle: ComputedStyle,
+        newStyle: ComputedStyle
+    ) -> [StyleProperty: Animation] {
+        var animations: [StyleProperty: Animation] = [:]
+        let transitions: [String: FrameTiming] =
+            FrameTiming.parse(node.style.unknownValue("transition") ?? "")
         for (property, timing) in transitions {
-            guard let oldValue = oldStyle[property],
-                let newValue = newStyle[property],
+            guard let key = StyleProperty(cssName: property),
+                let oldValue = oldStyle.value(for: key),
+                let newValue = newStyle.value(for: key),
                 oldValue != newValue,
-                let animation = makeAnimation(property: property, oldValue: oldValue, newValue: newValue, timing: timing)
+                let animation = makeAnimation(
+                    property: key,
+                    oldValue: oldValue,
+                    newValue: newValue,
+                    timing: timing
+                )
             else { continue }
-            animations[property] = animation
-            node.style[property] = oldValue
+            animations[key] = animation
+            node.style.set(oldValue, for: key)
         }
         return animations
     }
@@
-    private static func makeAnimation(
-        property: String,
-        oldValue: String,
-        newValue: String,
-        timing: FrameTiming
-    ) -> Animation? {
-        if property == "transform", let oldPoint = CSSValueParser.transform(oldValue),
-            let newPoint = CSSValueParser.transform(newValue)
-        {
-            return TransformAnimation(...)
-        }
-        guard let old = AnimatedValue(css: oldValue, property: property),
-            let new = AnimatedValue(css: newValue, property: property)
-        else { return nil }
+    private static func makeAnimation(
+        property: StyleProperty,
+        oldValue: AnimatedValue,
+        newValue: AnimatedValue,
+        timing: FrameTiming
+    ) -> Animation? {
+        let old = oldValue
+        let new = newValue
         switch (old, new) {
         case (.number(let o), .number(let n)):
             return NumericAnimation(
                 animatedProperty: property,
                 oldValue: o,
                 newValue: n,
                 timing: timing
             )
         case (.length(let o), .length(let n)):
             return PixelAnimation(
                 animatedProperty: property,
-                oldValue: o,
-                newValue: n,
+                oldValue: Double(o),
+                newValue: Double(n),
                 timing: timing
             )
         case (.color(let o), .color(let n)):
             return ColorAnimation(
                 animatedProperty: property,
                 oldColor: o,
                 newColor: n,
                 timing: timing
             )
+        case (.transform(let o), .transform(let n)):
+            return TransformAnimation(
+                animatedProperty: property,
+                oldPoint: o,
+                newPoint: n,
+                timing: timing
+            )
         default:
             return nil
         }
     }
```

`PixelAnimation` still stores `Double`; the conversion is at the typed boundary. Alternatively change `NumericAnimation` to `CGFloat`, but that touches more call sites for no behavior gain.

### `AnimationKey` and `DOMNode`

```diff
 protocol DOMNode: AnyObject {
-    var animations: [String: Animation] { get set }
+    var animations: [AnimationKey: Animation] { get set }
 }
```

```diff
 class Element: DOMNode {
-    var animations: [String: Animation] = [:]
+    var animations: [AnimationKey: Animation] = [:]
 }
 class TextNode: DOMNode {
-    var animations: [String: Animation] = [:]
+    var animations: [AnimationKey: Animation] = [:]
 }
```

### `Frame.runAnimationFrame`

```diff
         for node in animated {
             for (key, animation) in node.animations {
-                let property: String = animation.animatedProperty
+                let property: StyleProperty = animation.animatedProperty
                 if let value = animation.nextValue() {
                     needsAnotherFrame = true
-                    if property == "transform" || property == "opacity"
-                    {
-                        node.style[property] = value
+                    node.style.set(value, for: property)
+                    if property == .transform || property == .opacity {
                         if (node.layoutObject as? BlockLayout) != nil,
                             let style: PaintEffectStyle = paintEffectStyle(node: node)
                         {
                             compositedUpdates[NodeKey(node)] = EffectUpdate(
                                 style: style,
-                                isAnimatedTransform: node.animations["transform"] != nil
+                                isAnimatedTransform: node.animations[.property(.transform)] != nil
                             )
                         }
-                    } else if Self.affectsLayout(property) {
-                        node.style[property] = value
+                    } else if property.affectsLayout {
                         if document?.layoutNeeded() == true {
                             needsLayoutUpdate = true
                         } else {
@@
                     } else {
-                        node.style[property] = value
                         needsCompositeForPaint = true
                         needsPaint = true
                     }
```

The fallback call becomes:

```diff
-                            LayoutInvalidation.animatedPropertyChanged(node, property: property)
+                            LayoutInvalidation.animatedPropertyChanged(node, property: property)
```

with the signature changed:

```diff
-    static func animatedPropertyChanged(_ node: any DOMNode, property: String) {
-        let affectsSiblings: Bool = property == "display"
-            || property == "position"
-            || property == "margin-bottom"
+    static func animatedPropertyChanged(_ node: any DOMNode, property: StyleProperty) {
+        let affectsSiblings: Bool = property == .display
+            || property == .position
+            || property == .marginBottom
         markLayoutInput(node, affectsSiblings: affectsSiblings)
     }
```

`Frame.addAnimation`:

```diff
     func addAnimation(_ animation: any Animation, to node: any DOMNode) {
-        let key: String = animation.animatedProperty
+        let key: AnimationKey = .property(animation.animatedProperty)
         if node.animations.updateValue(animation, forKey: key) == nil {
             activeAnimations += 1
         }
     }
```

`PaintTree` animated-transform check:

```diff
-            animatedTransform: obj.node.animations["transform"] != nil
+            animatedTransform: obj.node.animations[.property(.transform)] != nil
```

`PaintEffectStyle` animated check:

```diff
-    let animated: Bool = node.animations.values.contains(where: { $0.animatedProperty == "transform" || $0.animatedProperty == "opacity" })
+    let animated: Bool = node.animations[.property(.transform)] != nil
+        || node.animations[.property(.opacity)] != nil
```

### Visited-link color

`Frame` writes the visited color directly (`Frame.swift:820`). Move it to `mutate` in B1, before the string subscript starts lagging typed reads:

```diff
-                        el.style["color"] = (tab?.forcedColors ?? false) ? ForcedColor.visitedText : "purple"
+                        let color: BrowserColor = BrowserColor(
+                            cssName: (tab?.forcedColors ?? false) ? ForcedColor.visitedText : "purple"
+                        )
+                        el.style.mutate { $0.text.color = color }
```

This is a rare boundary parse, not a per-frame one.

### `StyleTransitions` call site in `Frame`

```diff
-                let newAnimations: [String : any Animation] = StyleTransitions.diff(
-                    node: node,
-                    oldStyle: old,
-                    newStyle: node.style.snapshot()
-                )
+                let newAnimations: [StyleProperty: any Animation] = StyleTransitions.diff(
+                    node: node,
+                    oldStyle: old,
+                    newStyle: node.style.computed
+                )
                 for (property, animation) in newAnimations {
-                    node.animations[property] = animation
+                    node.animations[.property(property)] = animation
                 }
```

Delete `StyleCascade.oldRawStyles` and `oldRawStyle` here; nothing reads them after this step.

`LayoutInvalidationTests` must change its animation constructors now; the assertions can stay on the raw mirror until A3:

```diff
         fixture.frame.addAnimation(NumericAnimation(
-            animatedProperty: "opacity",
+            animatedProperty: .opacity,
```

```diff
         fixture.frame.addAnimation(TransformAnimation(
-            animatedProperty: "transform",
+            animatedProperty: .transform,
```

**Stop signal:** 189 tests pass, and the animation screenshot is pixel-identical. If the transition screenshot changes, check `StyleTransitions.diff` first: it is the only place that writes the old value back.

---

## Step A3 — Read typed fields everywhere

**Commit subject:** `refactor: read style fields directly`

This step cuts every consumer off the string API. It is mechanical, but it is the step that removes the per-read parsing.

### Typed field keys

`FieldName`:

```diff
 enum FieldName: Hashable {
     case layout(LayoutField)
-    case style(String)
+    case style(StyleProperty)
@@
         case .style(let key):
-            return "style.\(key)"
+            return "style.\(key.cssName)"
```

`StyleFieldRef`:

```diff
 struct StyleFieldRef: InvalidatableField {
     weak var owner: StyleFields?
-    let key: String
+    let key: StyleProperty
 
-    var fieldName: String { "style.\(key)" }
+    var fieldName: String { "style.\(key.cssName)" }
@@
-    func read(notify: any InvalidatableField) -> String? {
-        if notify.frozenDependencies { ... } else { addInvalidation(notify) }
-        return owner?.values[key]
+    func touch(_ notify: any InvalidatableField) {
+        if notify.frozenDependencies { ... } else { addInvalidation(notify) }
     }
```

`StyleFields.field`, `markField`, `addDependency`, `removeDependency`, `dependencyNames`, `dependentCount`, `containsDependency`, `fieldIsDirty` all take `StyleProperty` instead of `String`.

`StyleInvalidationState` moves to typed keys at the same time:

```diff
 private struct StyleInvalidationState {
-    var dirtyKeys: Set<String> = []
-    var dependents: [String: [FieldDependencyKey: FieldRef]] = [:]
+    var dirtyKeys: Set<StyleProperty> = []
+    var dependents: [StyleProperty: [FieldDependencyKey: FieldRef]] = [:]
     var needsRestyle: Bool = true
     var descendantsDirty: Bool = false
 }
```

`StyleFields.markAll` becomes `invalidation.dirtyKeys = Set(StyleProperty.allCases)`. `StyleFields.apply` and `StyleFields.set` call `notifyDependents(property)` and `dirtyKeys.remove(property)` directly. `StyleFields.dependentCount(for:)` takes `StyleProperty`; update `StyleFieldsTests` accordingly.

While the bridge `subscript` still exists, its setter maps the string key before touching typed state:

```swift
if let property = StyleProperty(cssName: key) {
    invalidation.dirtyKeys.remove(property)
    notifyDependents(property)
}
```

A4 deletes the subscript, so this compatibility line does not survive.

### Read pattern

Use the typed value plus `touch` where the old code passed `notify`:

```swift
node.style.field(.paddingLeft).touch(notify)
let value: CGFloat = node.style.computed.box.spacing.padding.left
```

The `touch` disappears in item 4. Until then it keeps the runtime dependency edge that `read(notify:)` created.

### `BlockStyle.swift`

```diff
 struct BlockStyle {
-    let display: String
-    let position: String
+    let display: LayoutStyle.Display
+    let position: LayoutStyle.Position
     let box: BlockBoxStyle
     let flags: BlockStyleFlags
 
     init(node: any DOMNode) {
-        let style: StyleFields = node.style
-        self.display = style["display"] ?? "inline"
-        self.position = style["position"] ?? "static"
+        let style: ComputedStyle = node.style.computed
+        self.display = style.layout.display
+        self.position = style.layout.position.kind
         self.box = BlockBoxStyle(
-            width: BlockStyle.px(style["width"]),
-            height: BlockStyle.px(style["height"]),
-            padding: EdgeInsets(
-                top: max(0, BlockStyle.px(style["padding-top"]) ?? 0),
-                right: max(0, BlockStyle.px(style["padding-right"]) ?? 0),
-                bottom: max(0, BlockStyle.px(style["padding-bottom"]) ?? 0),
-                left: max(0, BlockStyle.px(style["padding-left"]) ?? 0),
-            ),
-            margin: EdgeInsets(
-                top: BlockStyle.px(style["margin-top"]) ?? 0,
-                right: BlockStyle.px(style["margin-right"]) ?? 0,
-                bottom: BlockStyle.px(style["margin-bottom"]) ?? 0,
-                left: BlockStyle.px(style["margin-left"]) ?? 0,
-            )
+            width: style.box.size.width,
+            height: style.box.size.height,
+            padding: EdgeInsets(
+                top: max(0, style.box.spacing.padding.top),
+                right: max(0, style.box.spacing.padding.right),
+                bottom: max(0, style.box.spacing.padding.bottom),
+                left: max(0, style.box.spacing.padding.left)
+            ),
+            margin: style.box.spacing.margin
         )
         self.flags = BlockStyleFlags(
-            left: BlockStyle.px(style["left"]),
-            top: BlockStyle.px(style["top"]),
-            overflowScroll: style["overflow"] == "scroll",
-            directionRTL: style["direction"] == "rtl"
+            left: style.layout.position.left,
+            top: style.layout.position.top,
+            overflowScroll: style.layout.overflow == .scroll,
+            directionRTL: style.text.direction == .rtl
         )
     }
```

Delete `BlockStyle.px`.

### `BlockLayout.swift`

Mechanical replacements:

```diff
-        zoomField.setDependencies([parent.zoomField, node.style.field("zoom")])
+        zoomField.setDependencies([parent.zoomField, node.style.field(.zoom)])
```

```diff
-            $0.style["display"] == "block"
+            $0.style.computed.layout.display == .block
```

```diff
-        for child in node.children where child.style["display"] != "block" {
+        for child in node.children where child.style.computed.layout.display != .block {
```

```diff
-                _ = node.style.read("direction", notify: childrenField)
+                node.style.field(.direction).touch(childrenField)
```

```diff
-                let position: String = child.node.style.read("position", notify: heightField) ?? "static"
+                child.node.style.field(.position).touch(heightField)
+                let position: LayoutStyle.Position = child.node.style.computed.layout.position.kind
```

```diff
-        if let hStr = node.style.read("height", notify: heightField),
-            hStr.hasSuffix("px"),
-            let h = Double(hStr.dropLast(2))
-        {
+        if let h: CGFloat = node.style.computed.box.size.height {
             contentHeight = sumHeight
             let styleHeightZoom: CGFloat = zoomField.read(notify: heightField)
-            heightField.set(CGFloat(h) * styleHeightZoom)
+            heightField.set(h * styleHeightZoom)
```

```diff
-    private func padding(_ side: String, notify: any InvalidatableField) -> CGFloat {
+    private func padding(_ side: StyleProperty, notify: any InvalidatableField) -> CGFloat {
         guard extraNodes.isEmpty else { return 0 }
-        guard let raw: String = node.style.read("padding-\(side)", notify: notify),
-            raw.hasSuffix("px"),
-            let value: Double = Double(raw.dropLast(2))
-        else { return 0 }
-        return scaled(CGFloat(max(0, value)))
+        node.style.field(side).touch(notify)
+        let insets: EdgeInsets = node.style.computed.box.spacing.padding
+        let value: CGFloat
+        switch side {
+        case .paddingTop: value = insets.top
+        case .paddingRight: value = insets.right
+        case .paddingBottom: value = insets.bottom
+        case .paddingLeft: value = insets.left
+        default: value = 0
+        }
+        return scaled(max(0, value))
     }
```

Update call sites: `padding("bottom", ...)` -> `padding(.paddingBottom, ...)`, `padding("top", ...)` -> `padding(.paddingTop, ...)`.

`paintedPadding` uses `node.style.computed.box.spacing.padding` with the same switch, no `touch`.

`borderPaintRect`:

```diff
-        guard let width: CGFloat = CSSValueParser.outlineWidth(node.style["border-width"] ?? "medium"),
-            width > 0
-        else { return rect }
+        let width: CGFloat = node.style.computed.box.decoration.border.width
+        guard width > 0 else { return rect }
```

`paint`:

```diff
-        let bgcolor: String = node.style["background-color"] ?? "transparent"
-        if bgcolor != "transparent" || node.style["overflow"] == "scroll" {
-            let radii: CornerRadii = CSSValueParser.cornerRadii(node.style) ?? .zero
+        let computed: ComputedStyle = node.style.computed
+        let background: BrowserColor? = computed.visual.background.color
+        if background != nil || computed.layout.overflow == .scroll {
+            let radii: CornerRadii = computed.box.decoration.border.radii
+            let color: BrowserColor = background ?? BrowserColor(
+                red: 0, green: 0, blue: 0, alpha: 0
+            )
             if !radii.isZero {
-                items.append(.rrect(rect: selfRect(), radii: radii, color: BrowserColor(cssName: bgcolor)))
+                items.append(.rrect(rect: selfRect(), radii: radii, color: color))
             } else {
-                items.append(.rect(rect: selfRect(), color: BrowserColor(cssName: bgcolor)))
+                items.append(.rect(rect: selfRect(), color: color))
             }
         }
 
-        if let el = node as? Element, let image = el.backgroundImage,
-            let value = node.style["background-image"], value != "none" {
+        if let el = node as? Element, let image = el.backgroundImage,
+            computed.visual.background.image != nil {
             let box: Rect = selfRect()
-            let dest: Rect = BackgroundSize(box: box, image: image, zoom: zoom).rect(css: node.style["background-size"])
-            items.append(.clippedImage(image: image, rendering: ImageRendering(css: node.style["image-rendering"]), rect: dest, clip: box))
+            let dest: Rect = BackgroundSize(box: box, image: image, zoom: zoom)
+                .rect(spec: computed.visual.background.size)
+            items.append(.clippedImage(
+                image: image,
+                rendering: computed.visual.image.rendering,
+                rect: dest,
+                clip: box
+            ))
         }
```

`paintScrollbar`:

```diff
-        guard node.style["overflow"] == "scroll", contentHeight > height else { return [] }
+        guard node.style.computed.layout.overflow == .scroll,
+            contentHeight > height
+        else { return [] }
```

`BlockLayout` inline font construction (`BlockLayout.swift:998-1005`) follows `BrowserFont`:

```diff
     let owner: any DOMNode = node.inheritedStyleOwner
-    let weight: String = owner.style.read("font-weight", notify: inlineContentField) ?? "normal"
-    var styleStr: String = owner.style.read("font-style", notify: inlineContentField) ?? "normal"
-    if styleStr == "normal" { styleStr = "roman" }
-    let sizePx: Double = Double(owner.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
+    owner.style.field(.fontWeight).touch(inlineContentField)
+    owner.style.field(.fontStyle).touch(inlineContentField)
+    owner.style.field(.fontSize).touch(inlineContentField)
+    owner.style.field(.fontFamily).touch(inlineContentField)
+    let fontSpec: TextStyle.Font = owner.style.computed.text.font
     let font: BrowserFont = getFont(
-        size: Int(sizePx * zoom),
-        weight: weight,
-        style: styleStr,
-        family: owner.style.read("font-family", notify: inlineContentField) ?? "serif"
+        size: Int(fontSpec.size * zoom),
+        weight: fontSpec.weight.cssValue,
+        style: fontSpec.style.browserFontStyle,
+        family: fontSpec.family
     )
```

`marginPx` and the remaining `font` reads follow the same pattern. `marginPx` currently has no call sites; delete it rather than porting it.

### `BrowserFont.swift`

```diff
 func fontForElement(_ node: any DOMNode, zoom: CGFloat, notify: any InvalidatableField) -> BrowserFont {
     let owner: any DOMNode = node.inheritedStyleOwner
-    let weight: String = owner.style.read("font-weight", notify: notify) ?? "normal"
-    var style: String = owner.style.read("font-style", notify: notify) ?? "normal"
-    if style == "normal" { style = "roman" }
-    let sizePx: Double = Double(owner.style.read("font-size", notify: notify)?.dropLast(2) ?? "16") ?? 16.0
-    let sizeInt: Int = Int(sizePx * zoom)
+    owner.style.field(.fontWeight).touch(notify)
+    owner.style.field(.fontStyle).touch(notify)
+    owner.style.field(.fontSize).touch(notify)
+    owner.style.field(.fontFamily).touch(notify)
+    let font: TextStyle.Font = owner.style.computed.text.font
+    let sizeInt: Int = Int(font.size * zoom)
     return getFont(
         size: sizeInt,
-        weight: weight,
-        style: style,
-        family: owner.style.read("font-family", notify: notify) ?? "serif"
+        weight: font.weight.cssValue,
+        style: font.style.browserFontStyle,
+        family: font.family
     )
 }
```

`fontInputs`:

```diff
     return [
-        owner.style.field("font-weight"),
-        owner.style.field("font-style"),
-        owner.style.field("font-size"),
-        owner.style.field("font-family"),
+        owner.style.field(.fontWeight),
+        owner.style.field(.fontStyle),
+        owner.style.field(.fontSize),
+        owner.style.field(.fontFamily),
     ]
```

### `TextLayout.swift`

```diff
     func paint(into items: inout [DisplayOp]) {
-        let color: String = node.inheritedStyleOwner.style["color"] ?? "black"
+        let color: BrowserColor = node.inheritedStyleOwner.style.computed.text.color
         // ...
-                color: BrowserColor(cssName: color),
+                color: color,
```

### `LineLayout.swift`

```diff
-            || TextDirection(cssValue: node.style["direction"]) == .rtl
+            || node.style.computed.text.direction == .rtl
```

```diff
-            if TextDirection(cssValue: node.style["direction"]) == .rtl {
+            if node.style.computed.text.direction == .rtl {
```

### `InputLayout.swift` / `ButtonLayout.swift` / `IframeLayout.swift`

`InputLayout.paint`:

```diff
-        let bgcolor: String = element.style["background-color"] ?? "transparent"
-        if bgcolor != "transparent" {
-            let radii: CornerRadii = CSSValueParser.cornerRadii(element.style) ?? .zero
+        let computed: ComputedStyle = element.style.computed
+        if let bgcolor: BrowserColor = computed.visual.background.color {
+            let radii: CornerRadii = computed.box.decoration.border.radii
             if !radii.isZero {
-                items.append(.rrect(rect: selfRect(), radii: radii, color: BrowserColor(cssName: bgcolor)))
+                items.append(.rrect(rect: selfRect(), radii: radii, color: bgcolor))
             } else {
-                items.append(.rect(rect: selfRect(), color: BrowserColor(cssName: bgcolor)))
+                items.append(.rect(rect: selfRect(), color: bgcolor))
             }
         }
@@
-        let color: String = element.style["color"] ?? "black"
-        items.append(.text(text: text, font: font, color: BrowserColor(cssName: color), rect: ...))
+        items.append(.text(
+            text: text,
+            font: font,
+            color: computed.text.color,
+            rect: ...
+        ))
```

`ButtonLayout.paint`:

```diff
-        let bgcolor: String = element.style["background-color"] ?? "transparent"
-        let displayColor: String = bgcolor == "transparent" ? (usesForcedColors(node) ? ForcedColor.buttonFace : "white") : bgcolor
-        items.append(.rect(rect: selfRect(), color: BrowserColor(cssName: displayColor)))
+        let computed: ComputedStyle = element.style.computed
+        let displayColor: BrowserColor = computed.visual.background.color
+            ?? BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonFace : "white")
+        items.append(.rect(rect: selfRect(), color: displayColor))
```

`ButtonLayout.addWord`: replace the font reads with `fontForElement`-style typed reads, or call `fontForElement(node, zoom: zoom, notify: fontField)` directly. Prefer the existing helper; it removes the duplicate parsing.

`IframeLayout.paint`:

```diff
-        let bgColor: String = node.style["background-color"] ?? "transparent"
-        guard bgColor != "transparent" else { return }
-        let radii: CornerRadii = CSSValueParser.cornerRadii(node.style) ?? .zero
-        items.append(.rrect(rect: selfRect(), radii: radii, color: BrowserColor(cssName: bgColor)))
+        let computed: ComputedStyle = node.style.computed
+        guard let bgColor: BrowserColor = computed.visual.background.color else { return }
+        let radii: CornerRadii = computed.box.decoration.border.radii
+        items.append(.rrect(rect: selfRect(), radii: radii, color: bgColor))
```

### `ImageLayout.swift`

```diff
-        let ratio: AspectRatio? = AspectRatio(css: el.style.read("aspect-ratio", notify: notify)) ?? AspectRatio(intrinsicWidth: intrinsicW, intrinsicHeight: intrinsicH)
+        el.style.field(.aspectRatio).touch(notify)
+        let ratio: AspectRatio? = el.style.computed.box.size.aspectRatio
+            ?? AspectRatio(intrinsicWidth: intrinsicW, intrinsicHeight: intrinsicH)
```

```diff
-        guard let limit = lengthPx(el.style.read("max-width", notify: notify), available: available, zoom: zoom) else {
+        el.style.field(.maxWidth).touch(notify)
+        guard let maxWidth: Length = el.style.computed.box.size.maxWidth,
+            let limit: CGFloat = maxWidth.resolved(available: available, zoom: zoom)
+        else {
             return intrinsic
         }
```

```diff
-        let content: Rect = ObjectFit(
-            box: box,
-            intrinsicWidth: scaled(CGFloat(image.width)),
-            intrinsicHeight: scaled(CGFloat(image.height)),
-            css: node.style["object-fit"]
-        ).contentRect
-        items.append(.clippedImage(image: image, rendering: ImageRendering(css: node.style["image-rendering"]), rect: content, clip: box))
+        let computed: ComputedStyle = node.style.computed
+        let content: Rect = ObjectFit(
+            box: box,
+            intrinsicWidth: scaled(CGFloat(image.width)),
+            intrinsicHeight: scaled(CGFloat(image.height)),
+            fit: computed.visual.image.fit
+        ).contentRect
+        items.append(.clippedImage(
+            image: image,
+            rendering: computed.visual.image.rendering,
+            rect: content,
+            clip: box
+        ))
```

`widthField.setDependencies` / `heightField.setDependencies` use `.aspectRatio`, `.maxWidth`.

Delete `LengthPx.swift`; `Length.resolved` replaces it.

### `BackgroundSize.swift` / `ObjectFit.swift`

```diff
-    func rect(css: String?) -> Rect {
-        let tokens: [String] = (css ?? "auto")
-            .split(whereSeparator: { $0 == " " }).map(String.init)
-        let first: String = tokens.first?.lowercased() ?? "auto"
-        let second: String? = tokens.count > 1 ? tokens[1].lowercased() : nil
-        let size: (width: CGFloat, height: CGFloat) = resolve(first: first, second: second)
+    func rect(spec: BackgroundSizeSpec) -> Rect {
+        let size: (width: CGFloat, height: CGFloat) = resolve(spec: spec)
```

Move the token parsing into `BackgroundSizeSpec.init(css:)`. Keep `resolve` behavior identical: `cover`, `contain`, two lengths, one length + intrinsic ratio, otherwise intrinsic.

```diff
-    let css: String?
+    let fit: ObjectFitKind
@@
-        switch (css ?? "fill").lowercased() {
-        case "contain":
+        switch fit {
+        case .contain:
             return (intrinsicWidth * contain, intrinsicHeight * contain)
-        case "cover":
+        case .cover:
             let cover: CGFloat = max(boxWidth / intrinsicWidth, boxHeight / intrinsicHeight)
             return (intrinsicWidth * cover, intrinsicHeight * cover)
-        case "none":
+        case .none:
             return (intrinsicWidth, intrinsicHeight)
-        case "scale-down":
+        case .scaleDown:
             let scale: CGFloat = min(1, contain)
             return (intrinsicWidth * scale, intrinsicHeight * scale)
-        default:
+        case .fill:
             return (boxWidth, boxHeight)
         }
```

### `LayoutObject.swift`

```diff
-        if let t = CSSValueParser.transform(node.style["transform"] ?? "") {
+        if let t: CGPoint = node.style.computed.visual.effects.translation {
             x -= t.x
             y -= t.y
         }
@@
-            if let t = CSSValueParser.transform(current.style["transform"] ?? "") {
+            if let t: CGPoint = current.style.computed.visual.effects.translation {
```

`resolvedZoom`:

```diff
-        guard let zoomStr = node.style.read("zoom", notify: zoomField) else {
+        node.style.field(.zoom).touch(zoomField)
+        guard let factor: CGFloat = node.style.computed.box.zoom else {
             return parentZoom
         }
-        let trimmed: String = zoomStr.trimmingCharacters(in: .whitespaces)
-        let factor: CGFloat
-        if trimmed.hasSuffix("%"), let pct = Double(trimmed.dropLast()) {
-            factor = CGFloat(pct / 100.0)
-        } else if let val = Double(trimmed) {
-            factor = CGFloat(val)
-        } else {
-            return parentZoom
-        }
         return parentZoom * factor
```

### `DisplayOp.swift`

```diff
     static func fromStyle(_ node: any DOMNode, rect: Rect) -> DisplayOp? {
-        let style: String = node.style["outline-style"] ?? "none"
-        guard style != "none", style != "hidden" else { return nil }
-        guard let thickness: CGFloat = CSSValueParser.outlineWidth(node.style["outline-width"] ?? "medium"),
-            thickness > 0
-        else { return nil }
-        let color: String = node.style["outline-color"] ?? node.style["color"] ?? "black"
-        return .outline(rect: rect, color: BrowserColor(cssName: color), width: thickness)
+        let computed: ComputedStyle = node.style.computed
+        let outline: BoxStyle.Decoration.Outline = computed.box.decoration.outline
+        guard outline.style != .none, outline.style != .hidden,
+            outline.width > 0
+        else { return nil }
+        return .outline(
+            rect: rect,
+            color: outline.color ?? computed.text.color,
+            width: outline.width
+        )
     }
 
     static func fromBorderStyle(_ node: any DOMNode, rect: Rect) -> DisplayOp? {
-        let style: String = node.style["border-style"] ?? "none"
-        guard style != "none", style != "hidden" else { return nil }
-        guard let thickness: CGFloat = CSSValueParser.outlineWidth(node.style["border-width"] ?? "medium"),
-            thickness > 0
-        else { return nil }
-        let color: String = node.style["border-color"] ?? "black"
-        return .outline(rect: rect, color: BrowserColor(cssName: color), width: thickness)
+        let border: BoxStyle.Decoration.Border = node.style.computed.box.decoration.border
+        guard border.style != .none, border.style != .hidden,
+            border.width > 0
+        else { return nil }
+        return .outline(rect: rect, color: border.color, width: border.width)
     }
```

### `PaintEffectStyle.swift`

```diff
 func paintEffectStyle(node: DOMNode) -> PaintEffectStyle? {
-    if node.animations.isEmpty,
-        node.style["opacity"] == nil,
-        node.style["mix-blend-mode"] == nil,
-        node.style["transform"] == nil,
-        node.style["filter"] == nil {
-        return nil
-    }
-    let opacity: Double = Double(node.style["opacity"] ?? "1.0") ?? 1.0
-    let blendMode: BrowserBlendMode? = browserBlendMode(node.style["mix-blend-mode"])
-    let translation: CGPoint? = CSSValueParser.transform(node.style["transform"] ?? "")
-    let blurRadius: CGFloat = CSSValueParser.blur(node.style["filter"] ?? "")
-    let animated: Bool = node.animations[.property(.transform)] != nil
-        || node.animations[.property(.opacity)] != nil
-
-    guard blurRadius > 0 || opacity < 1
-        || (blendMode != nil && blendMode != .normal)
-        || translation != nil || animated
+    let effects: VisualStyle.Effects = node.style.computed.visual.effects
+    let animated: Bool = node.animations[.property(.transform)] != nil
+        || node.animations[.property(.opacity)] != nil
+
+    guard effects.blurRadius > 0 || effects.opacity < 1
+        || (effects.blendMode != nil && effects.blendMode != .normal)
+        || effects.translation != nil || animated
     else { return nil }
 
     return PaintEffectStyle(
-        opacity: opacity,
-        blendMode: blendMode,
-        translation: translation,
-        blurRadius: blurRadius
+        opacity: effects.opacity,
+        blendMode: effects.blendMode,
+        translation: effects.translation,
+        blurRadius: effects.blurRadius
     )
 }
```

### `PaintTree.swift`

```diff
-    } else if let block = obj as? BlockLayout, block.node.style["overflow"] == "scroll" {
+    } else if let block = obj as? BlockLayout,
+        block.node.style.computed.layout.overflow == .scroll
+    {
@@
-        let radii: CornerRadii = CSSValueParser.cornerRadii(block.node.style) ?? .zero
+        let radii: CornerRadii = block.node.style.computed.box.decoration.border.radii
```

```diff
-    } else if let block = obj as? BlockLayout,
-        block.node.style["overflow"] == "hidden" || block.node.style["overflow"] == "clip"
+    } else if let block = obj as? BlockLayout,
+        block.node.style.computed.layout.overflow == .hidden
+            || block.node.style.computed.layout.overflow == .clip
     {
-        let radii: CornerRadii = CSSValueParser.cornerRadii(block.node.style) ?? .zero
+        let radii: CornerRadii = block.node.style.computed.box.decoration.border.radii
```

```diff
 func effectiveZIndex(_ node: any DOMNode) -> Int {
-    guard (node.style["position"] ?? "static") != "static" else { return 0 }
-    return Int(node.style["z-index"] ?? "0") ?? 0
+    let layout: LayoutStyle = node.style.computed.layout
+    guard layout.position.kind != .staticFlow else { return 0 }
+    return layout.zIndex
 }
 
 func inPaintOrder(_ children: [any LayoutObject]) -> [any LayoutObject] {
-    guard children.contains(where: { ($0.node.style["position"] ?? "static") != "static" })
+    guard children.contains(where: { $0.node.style.computed.layout.position.kind != .staticFlow })
         else { return children }
```

### `Frame.swift` remaining reads

```diff
-                if block.node.style["overflow"] == "scroll",
+                if block.node.style.computed.layout.overflow == .scroll,
```

```diff
-                el.style["overflow"] == "scroll"
+                el.style.computed.layout.overflow == .scroll
```

`Frame.loadBackgroundImages`:

```diff
-                let value = el.style["background-image"],
-                    value != "none" {
+                if let value: String = el.style.computed.visual.background.image {
```

`ForcedColor.swift`:

```diff
 func usesForcedColors(_ node: any DOMNode) -> Bool {
-    node.style[forcedColorsAppliedKey] == "active"
+    node.style.unknownValue(forcedColorsAppliedKey) == "active"
 }
```

Keep `applyForcedColors(to: inout [String: String], node:)` unchanged: it runs before the parser, at the boundary.

### `CSSValueParser` and `StyleFields` cleanup

- Change `CSSValueParser.cornerRadii(_ style: StyleFields)` to `cornerRadii(_ css: [String: String])`.
- Delete `StyleFields.read(_ key: String, notify:)` and `StyleFieldRef.read`.
- Keep `StyleFields.subscript` only until A4.
- Keep `StyleFields.snapshot()` raw only until A4.

### Tests in this step

`StyleFieldsTests` must switch from string keys to typed keys before `read` disappears:

```diff
-        _ = style.read("width", notify: target)
+        style.field(.width).touch(target)
```

```diff
-        #expect(style.read("width", notify: target) == nil)
+        style.field(.width).touch(target)
+        #expect(style.computed.box.size.width == nil)
```

`removeDependency(.style("width"), target.ref)` -> `.style(.width)`.
`dependentCount(for: "width")` -> `dependentCount(for: .width)`.

`LayoutInvalidationTests` animation constructors:

```diff
         fixture.frame.addAnimation(NumericAnimation(
-            animatedProperty: "opacity",
+            animatedProperty: .opacity,
```

```diff
         fixture.frame.addAnimation(TransformAnimation(
-            animatedProperty: "transform",
+            animatedProperty: .transform,
```

```diff
-        #expect(fixture.narrow.style["opacity"] != nil)
+        #expect(fixture.narrow.style.computed.visual.effects.opacity < 1)
```

```diff
-        #expect(fixture.narrow.style["transform"] != nil)
+        #expect(fixture.narrow.style.computed.visual.effects.translation != nil)
```

`affectsLayout` test:

```diff
-        #expect(Frame.affectsLayout("width"))
+        #expect(StyleProperty.width.affectsLayout)
...
-        #expect(Frame.affectsLayout("future-property"))
```

Remove the unknown-property assertion; typed animations cannot target an unmodeled property.

`HoverTests`, `StyleInvalidationTests`, and `DOMNodeTests` must stop writing style strings before typed reads become the only source of truth:

```diff
-        #expect(a.style["color"] == "black")
+        #expect(a.style.computed.text.color == BrowserColor(cssName: "black"))
```

```diff
-        p.style["font-size"] = "32px"
+        p.style.mutate { $0.text.font.size = 32 }
```

```diff
-        clean.style["color"] = "red"
+        clean.style.mutate { $0.text.color = BrowserColor(cssName: "red") }
```

```diff
-        el.style["color"] = "red"
-        #expect(el.style["color"] == "red")
+        el.style.mutate { $0.text.color = BrowserColor(cssName: "red") }
+        #expect(el.style.computed.text.color == BrowserColor(cssName: "red"))
```

`StyleInvalidationTests` also writes `opacity` and `transform` directly; use `mutate` on `visual.effects`:

```swift
style.mutate { $0.visual.effects.opacity = 0.5 }
style.mutate { $0.visual.effects.translation = CGPoint(x: 20, y: 0) }
```

**Stop signal:** 189 tests pass and both screenshots are unchanged. If a layout test fails, check that every migrated `read(notify:)` got a matching `field(...).touch(notify)`; that is the one behavior the mechanical rewrite can drop.

---

## Step A4 — Delete the raw style mirror

**Commit subject:** `refactor: drop the raw style dictionary`

After A3 nothing reads `storage.raw` except tests and the old subscript.

### `StyleFields.swift`

```diff
 private struct StyleStorage {
     var computed: ComputedStyle = .initial
     var unknown: [String: String] = [:]
-    var raw: [String: String] = [:] // temporary; deleted in A4
 }
```

Delete:

- the string `subscript`
- `isEmpty`
- `snapshot() -> [String: String]`
- `StyleProperty.cssString(_:)`
- the `raw` assignment in `apply`
- the string inheritance seed and `inheritedPropertyDefaults` from `ApplyStyle.swift`
- the raw parent font-size lookup in `ApplyStyle.swift`

`StyleFields.set` loses the mirror write:
```diff
 func set(_ value: AnimatedValue, for property: StyleProperty) {
     guard storage.computed.set(value, for: property) else { return }
-    storage.raw[property.cssName] = property.cssString(value)
     invalidation.dirtyKeys.remove(property)
     revision += 1
     notifyDependents(property)
 }
```

`apply` also loses the mirror and the raw count:

```diff
-        let oldRaw: [String: String] = storage.raw
...
-        storage.raw = newValues
...
-        if !changed.isEmpty || parsed.unknown != oldUnknown || newValues != oldRaw {
+        if !changed.isEmpty || parsed.unknown != oldUnknown {
...
-        profiler.count("style.fields.set", by: storage.raw.count)
+        profiler.count("style.fields.set", by: StyleProperty.allCases.count)
```

Change `snapshot` if any caller still needs it:

```swift
@MainActor
func snapshot() -> ComputedStyle {
    return storage.computed
}
```

`StyleCascade.oldRawStyles` / `oldRawStyle` are already gone after B1.

`ApplyStyle` drops the seed and resolves the percentage against typed parent:

```diff
-    let parentStyle: StyleFields? = node.parent?.style
     var newStyle: [String: String] = [:]
-    profiler.measure("style.apply.reset") {
-        newStyle.reserveCapacity(inheritedPropertyDefaults.count)
-        for (property, defaultValue) in inheritedPropertyDefaults {
-            newStyle[property] = parentStyle?[property] ?? defaultValue
-        }
-    }
```

```diff
-            let parentFontSize: String = node.parent?.style["font-size"] ?? inheritedPropertyDefaults["font-size"]!
             let percentage: Double = Double(fontSize.dropLast()) ?? 100.0
-            let parentPx: Double = Double(parentFontSize.dropLast(2)) ?? 16.0
-            newStyle["font-size"] = "\(percentage / 100.0 * parentPx)px"
+            let parentPx: CGFloat = node.parent?.style.computed.text.font.size ?? 16
+            newStyle["font-size"] = "\(percentage / 100.0 * Double(parentPx))px"
```

Delete `inheritedPropertyDefaults`.

### Test updates

`DOMNodeTests`:

```diff
-        #expect(el.style.isEmpty)
+        #expect(el.style.computed == .initial)
```

`StyleFieldsTests`:

```diff
-    #expect(style.isEmpty)
+    #expect(style.computed == .initial)
 
     style.apply(["width": "10px", "height": "5px"])
-    #expect(!style.isEmpty)
-    #expect(style.snapshot() == ["width": "10px", "height": "5px"])
+    #expect(style.computed.box.size.width == 10)
+    #expect(style.computed.box.size.height == 5)
 
     style.apply(["width": "10px"])
-    #expect(style.snapshot() == ["width": "10px"])
+    #expect(style.computed.box.size.height == nil)
```

`subscriptBumpsRevisionOnlyWhenValueChanges` becomes a typed-write test:

```swift
@Test func typedWriteBumpsRevisionOnlyWhenValueChanges() {
    let style = StyleFields()
    let before = style.revision

    style.set(.length(10), for: .width)
    #expect(style.revision == before + 1)

    let afterFirstWrite = style.revision
    style.set(.length(10), for: .width)
    #expect(style.revision == afterFirstWrite)

    style.set(.length(20), for: .width)
    #expect(style.revision == afterFirstWrite + 1)
}
```

`HoverTests`, `StyleInvalidationTests`, and `DOMNodeTests` were already migrated to typed reads and writes in A3. A4 only removes the now-unused `isEmpty` and raw snapshot assertions. Any remaining `style["..."] = ...` in `StyleFieldsTests` becomes `style.set(...)` for animatable fields or `style.mutate { ... }` for the rest.

**Stop signal:** 189 tests pass with no string `style[...]` access left under `Sources/Engine` or `Tests`.

---

## Step B2 — Remove the string animation helpers

**Commit subject:** `refactor: remove string animation helpers`

The keyframe conformance and call-site edits below land with B1. This step only removes dead helpers (`rgbToHex`), updates the README, and runs the final visual check.

### `KeyframeAnimation.swift`

```diff
 extension KeyframeAnimation {
     static func make(
         frames: [Keyframe],
         playback: KeyframePlayback
     ) -> KeyframeAnimation? {
@@
         let differing: [String : String] = from.body.filter { to.body[$0.key] != $0.value }
-        guard let (property, oldVal) = differing.first, let newVal = to.body[property]
+        guard let (propertyName, oldVal) = differing.first,
+            let newVal = to.body[propertyName],
+            let property = StyleProperty(cssName: propertyName)
         else { return nil }
 
         guard let oldValue = AnimatedValue(css: oldVal, property: property),
             let newValue = AnimatedValue(css: newVal, property: property)
         else { return nil }
```

The factory stays the same shape, now over typed values. `.transform` is still rejected by `AnimatedValue(css:)`, so keyframe transform behavior is unchanged.

`nextValue`:

```diff
-    func nextValue() -> String? {
+    func nextValue() -> AnimatedValue? {
```

### `Frame.swift` keyframes

```diff
-                    guard let animDecl = node.style["animation"],
+                    guard let animDecl = node.style.unknownValue("animation"),
                         let playback = KeyframePlayback.parse(animDecl),
                         let frames = keyframes[playback.name]
                     else { continue }
-                    let key: String = "animation/\(playback.name)"
+                    let key: AnimationKey = .keyframes(playback.name)
                     guard node.animations[key] == nil else { continue }
                     if let anim = KeyframeAnimation.make(frames: frames, playback: playback)
                     {
                         node.animations[key] = anim
                     }
```

### Remove the string path

Delete:

- `rgbToHex` in `BrowserColor.swift` (no callers after `ColorAnimation` is typed).
- `CSSValueParser.transform` if `PaintEffectStyle`, `hitTest`, `absoluteBounds`, and `StyleTransitions` no longer call it. The parser still needs it in `ComputedStyleParser`, so keep it.
- Any `nextValue() -> String?` override left by grep.

### Docs

`README.md:35` currently says "Cascade + compute style". Update the style/display bullets to name `ComputedStyle` and `AnimatedValue`; keep the existing `DisplayOp` sentence. No metric names change in `profiling.md`, so leave it alone unless the implementation renames `style.fields.set` / `style.fields.changed`.

**Stop signal:** keyframe screenshot identical; no `String` in any `Animation.nextValue` signature; `swift test` 189 passing.

---

## Verification

Run after each step:

```sh
swift build
swift test
```

Run after A2, B1, A3, and B2:

```sh
swift run ToyStackHeadless "file://$PWD/www/ch13/exercise-13-2.html" \
  --frame-limit 5 --screenshot /tmp/after-style.png
swift run ToyStackHeadless "file://$PWD/www/ch13/exercise-13-6.html" \
  --frame-limit 30 --screenshot /tmp/after-anim.png
cmp /tmp/before-style.png /tmp/after-style.png
cmp /tmp/before-anim.png /tmp/after-anim.png
```

Manual checks:

- `www/ch13/exercise-13-2.html`: the transition runs at the same speed and lands on the same final color/size.
- `www/ch13/exercise-13-6.html`: keyframes repeat/alternate exactly as before.
- `www/ch16/granular-style.html`: changing one field does not mark unrelated layout fields.
- `www/ch11/exercise-11-3.html`: scroll clipping and scrollbar colors are unchanged.

If a screenshot differs after A3, diff the affected read in this order: `BlockStyle` -> `BlockLayout.paint` -> `PaintTree` -> `DisplayOp`. A3 is the only step that changes which value a paint pass reads.

## Risks

| Risk | Detection | Fix |
|---|---|---|
| A migrated read loses its `touch` call | A layout invalidation test fails, or `assertionFailure("Undeclared dependency")` fires in debug | Add `field(.property).touch(notify)` next to the typed read |
| `ComputedStyle` defaults differ from the old string defaults | A screenshot changes after A2 | Compare `ComputedStyle.initial` with the defaults at `ApplyStyle.swift:2-10` |
| Inherited text properties stop propagating | `StyleInvalidationTests.fontResolutionReadsTheParentElement` fails | `ComputedStyle.inheriting(from:)` must copy the whole `TextStyle` |
| `background-color: transparent` starts painting an op | Paint counts or screenshots change | Keep `Background.color` optional; parser returns nil for transparent |
| `border-radius` dependency no longer fires | Rounded rects go stale after a radius change | All five radius keys must map to `.borderRadius`; parser diff notifies once |
| Transition writes the new value instead of the old one | Transition jumps to the end | `StyleTransitions.diff` must `set(oldValue, for:)` after creating the animation |
| Keyframe synthetic key collides | A keyframe and a transition animate the same property | `AnimationKey` separates `.property` from `.keyframes` |
| Raw mirror left behind | `grep -R 'style\\[' Sources Tests` finds reads | A4 is not done |

## Commit order

```
A1  refactor: give computed style a typed shape
A2  refactor: compute style as typed values
B1  refactor: animate values, not style strings   (includes keyframes)
A3  refactor: read style fields directly
A4  refactor: drop the raw style dictionary
B2  refactor: remove string animation helpers
```

Do not put B1 before A2: B1 needs `StyleFields.set` and `ComputedStyle.value(for:)`. Do not run A3 before B1: animation still writes strings, so typed reads would go stale. Do not park between A3 and A4: the raw mirror is a temporary bridge, not a second API.
