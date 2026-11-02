# Outline ops: cutting `DrawOutline` over to `DisplayOp.outline`

Companion note to [oop-refactor-1-2-display-op.md](./oop-refactor-1-2-display-op.md), step A2, for `BlockLayout.swift:1080`.

## The misunderstanding

```swift
if let border = DrawOutline.fromBorderStyle(node, rect: borderPaintRect()) {
    items.append(border)
}
```

There is nothing here to rewrite into `.outline(...)` directly. Two separate types are in play:

| Expression | Type |
|---|---|
| `border` | `DrawOutline` (struct: `rect`, `color: String`, `thickness`) |
| `DisplayOp.outline` | enum case `(Rect, BrowserColor, CGFloat)` |
| `items` | `[DisplayOp]` |

`.outline(...)` is an enum case constructor. Leading-dot syntax only works where the expected type is already `DisplayOp`, e.g. `items.append(.outline(...))`. In `if let border = ...` the initializer must produce a `DisplayOp?`, and `DrawOutline.fromBorderStyle` produces `DrawOutline?`. So `if let border = .outline(...)` is not valid, and unpacking the struct at the call site

```swift
items.append(.outline(border.rect, BrowserColor(cssName: border.color), border.thickness))
```

would keep `DrawOutline`, its `String` color, and the old type alive — the exact things A2 removes.

## The fix

Move the conversion **into the factory**. The factory stops returning `DrawOutline?` and returns `DisplayOp?`; the call site then binds a `DisplayOp` and appends it unchanged.

`DrawOutline.swift` is deleted (plan file map, step 2g). Its two factories are small helpers that build one type, so they live in `DisplayOp.swift` under a `// MARK:` section, per the repo's file-layout rule. Names are kept as the plan specifies.

### File: `Sources/Engine/Display/DisplayOp.swift`

```diff
 }

+// MARK: - Outline factories
+
+extension DisplayOp {
+    @MainActor
+    static func fromStyle(_ node: any DOMNode, rect: Rect) -> DisplayOp? {
+        let style: String = node.style["outline-style"] ?? "none"
+        guard style != "none", style != "hidden" else { return nil }
+        guard let thickness: CGFloat = CSSValueParser.outlineWidth(node.style["outline-width"] ?? "medium"),
+            thickness > 0
+        else { return nil }
+        let color: String = node.style["outline-color"] ?? node.style["color"] ?? "black"
+        return .outline(rect, BrowserColor(cssName: color), thickness)
+    }
+
+    @MainActor
+    static func fromBorderStyle(_ node: any DOMNode, rect: Rect) -> DisplayOp? {
+        let style: String = node.style["border-style"] ?? "none"
+        guard style != "none", style != "hidden" else { return nil }
+        guard let thickness: CGFloat = CSSValueParser.outlineWidth(node.style["border-width"] ?? "medium"),
+            thickness > 0
+        else { return nil }
+        let color: String = node.style["border-color"] ?? "black"
+        return .outline(rect, BrowserColor(cssName: color), thickness)
+    }
+}
+
 private func executeCompositedLayer(
```

### File: `Sources/Engine/Display/DrawOutline.swift`

Delete the file. The struct, `execute(scroll:)`, and `shifted(dx:dy:)` are already covered by `.outline` in `DisplayOp.execute` / `.shifted`.

### File: `Sources/Engine/Layouts/BlockLayout.swift`

```diff
-        if let border = DrawOutline.fromBorderStyle(node, rect: borderPaintRect()) {
+        if let border = DisplayOp.fromBorderStyle(node, rect: borderPaintRect()) {
             items.append(border)
         }
 
-        let outline: DrawOutline? = DrawOutline.fromStyle(node, rect: selfRect())
+        let outline: DisplayOp? = DisplayOp.fromStyle(node, rect: selfRect())
         if node.isFocusVisible && outline == nil {
             let ring: (outer: String, inner: String) = focusRingColors(node)
-            items.append(DrawOutline(rect: selfRect(), color: ring.outer, thickness: 4))
-            items.append(DrawOutline(rect: selfRect(), color: ring.inner, thickness: 2))
+            items.append(.outline(selfRect(), BrowserColor(cssName: ring.outer), 4))
+            items.append(.outline(selfRect(), BrowserColor(cssName: ring.inner), 2))
         }
         if let outline = outline { items.append(outline) }
```

`outline == nil` still compiles: `Optional`'s `== nil` overload does not require `Wrapped: Equatable`, and `DisplayOp` is not `Equatable`.

## Ripple: the other `DrawOutline` users

Deleting the struct forces these in the same commit. Same transformation everywhere: factory receiver changes to `DisplayOp`, direct constructors become `.outline(rect, BrowserColor(cssName: color), thickness)`.

### File: `Sources/Engine/Layouts/ButtonLayout.swift`

```diff
-    override func paint(into items: inout [any DisplayItem]) {
+    override func paint(into items: inout [DisplayOp]) {
         guard let element = node as? Element else { return }
         let bgcolor: String = element.style["background-color"] ?? "transparent"
         let displayColor: String = bgcolor == "transparent" ? (usesForcedColors(node) ? ForcedColor.buttonFace : "white") : bgcolor
-        items.append(DrawRect(rect: selfRect(), color: displayColor))
-        items.append(DrawOutline(rect: selfRect(), color: usesForcedColors(node) ? ForcedColor.buttonBorder : "black", thickness: 1))
+        items.append(.rect(selfRect(), BrowserColor(cssName: displayColor)))
+        items.append(.outline(selfRect(), BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonBorder : "black"), 1))
 
-        let outline: DrawOutline? = DrawOutline.fromStyle(node, rect: selfRect())
+        let outline: DisplayOp? = DisplayOp.fromStyle(node, rect: selfRect())
         if element.isFocusVisible && outline == nil {
-            items.append(DrawOutline(rect: selfRect(), color: focusRingColors(node).outer, thickness: 4))
-            items.append(DrawOutline(rect: selfRect(), color: focusRingColors(node).inner, thickness: 2))
+            items.append(.outline(selfRect(), BrowserColor(cssName: focusRingColors(node).outer), 4))
+            items.append(.outline(selfRect(), BrowserColor(cssName: focusRingColors(node).inner), 2))
         }
         if let outline = outline { items.append(outline) }
     }
```

### File: `Sources/Engine/Layouts/InputLayout.swift`

```diff
-    override func paint(into items: inout [any DisplayItem]) {
+    override func paint(into items: inout [DisplayOp]) {
         guard let element = node as? Element else { return }
         let bgcolor: String = element.style["background-color"] ?? "transparent"
         if bgcolor != "transparent" {
             let radii: CornerRadii = CSSValueParser.cornerRadii(element.style) ?? .zero
             if !radii.isZero {
-                items.append(
-                    DrawRRect(
-                        rect: selfRect(),
-                        parentEffect: nil,
-                        radii: radii,
-                        color: bgcolor
-                    )
-                )
+                items.append(.rrect(selfRect(), radii, BrowserColor(cssName: bgcolor)))
             } else {
-                items.append(DrawRect(rect: selfRect(), color: bgcolor))
+                items.append(.rect(selfRect(), BrowserColor(cssName: bgcolor)))
             }
         }
 
         if element.attributes["type"] == "checkbox" {
-            items.append(DrawRect(rect: selfRect(), color: usesForcedColors(node) ? ForcedColor.buttonFace : "white"))
-            items.append(DrawOutline(rect: selfRect(), color: usesForcedColors(node) ? ForcedColor.buttonBorder : "black", thickness: 1))
+            items.append(.rect(selfRect(), BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonFace : "white")))
+            items.append(.outline(selfRect(), BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonBorder : "black"), 1))
             if element.isChecked {
-                items.append(
-                    DrawText(
-                        at: Point(x: x, y: y),
-                        text: "X",
-                        font: font,
-                        color: usesForcedColors(node) ? ForcedColor.buttonText : "black"
-                    )
-                )
+                items.append(
+                    .text(
+                        "X",
+                        font,
+                        BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonText : "black"),
+                        Rect(left: x, top: y, right: x + font.measure("X"), bottom: y + font.linespace)
+                    )
+                )
             }
-            let outline: DrawOutline? = DrawOutline.fromStyle(node, rect: selfRect())
+            let outline: DisplayOp? = DisplayOp.fromStyle(node, rect: selfRect())
             if element.isFocusVisible && outline == nil {
-                items.append(DrawOutline(rect: selfRect(), color: focusRingColors(node).outer, thickness: 2))
-                items.append(DrawOutline(rect: selfRect(), color: focusRingColors(node).inner, thickness: 4))
+                items.append(.outline(selfRect(), BrowserColor(cssName: focusRingColors(node).outer), 2))
+                items.append(.outline(selfRect(), BrowserColor(cssName: focusRingColors(node).inner), 4))
             }
             if let outline = outline { items.append(outline) }
         }
@@
-        items.append(DrawText(at: Point(x: x, y: y), text: text, font: font, color: color))
+        items.append(
+            .text(
+                text,
+                font,
+                BrowserColor(cssName: color),
+                Rect(left: x, top: y, right: x + font.measure(text), bottom: y + font.linespace)
+            )
+        )
 
         if element.isFocused {
             items.append(drawCursor(self, offset: font.measure(text)))
         }
-        let outline: DrawOutline? = DrawOutline.fromStyle(node, rect: selfRect())
+        let outline: DisplayOp? = DisplayOp.fromStyle(node, rect: selfRect())
         if element.isFocusVisible && outline == nil {
-            items.append(DrawOutline(rect: selfRect(), color: focusRingColors(node).outer, thickness: 4))
-            items.append(DrawOutline(rect: selfRect(), color: focusRingColors(node).inner, thickness: 2))
+            items.append(.outline(selfRect(), BrowserColor(cssName: focusRingColors(node).outer), 4))
+            items.append(.outline(selfRect(), BrowserColor(cssName: focusRingColors(node).inner), 2))
         }
         if let outline = outline { items.append(outline) }
     }
```

### File: `Sources/Engine/Layouts/IframeLayout.swift`

```diff
-    override func paintEffects(into items: inout [any DisplayItem], from start: Int) {
+    override func paintEffects(into items: inout [DisplayOp], from start: Int) {
         let rect: Rect = selfRect()
@@
-        var clipChildren: [any DisplayItem] = [transform]
+        var clipChildren: [DisplayOp] = [.effect(transform)]
         if let bar = childScrollbar(innerRect: innerRect) {
             clipChildren.append(bar)
         }
 
         let clipped: Blend = Blend(
             opacity: 1.0, blendMode: .normal, node: node, children: clipChildren
         )
 
-        var cmds: [any DisplayItem] = [clipped]
-        if let border: DrawOutline = DrawOutline.fromBorderStyle(node, rect: rect) {
+        var cmds: [DisplayOp] = [.effect(clipped)]
+        if let border: DisplayOp = DisplayOp.fromBorderStyle(node, rect: rect) {
             cmds.append(border)
         }
 
-        if let outline: DrawOutline = DrawOutline.fromStyle(node, rect: rect) {
+        if let outline: DisplayOp = DisplayOp.fromStyle(node, rect: rect) {
             cmds.append(outline)
         }
 
-        let wrapped: [any DisplayItem] = paintBrowserVisualEffects(node: node, items: cmds, rect: rect)
+        let wrapped: [DisplayOp] = paintBrowserVisualEffects(node: node, items: cmds, rect: rect)
         items.replaceSubrange(start..<items.count, with: wrapped)
     }
@@
-    private func childScrollbar(innerRect: Rect) -> ScrollbarBar? {
+    private func childScrollbar(innerRect: Rect) -> DisplayOp? {
@@
-        return ScrollbarBar(
-            rect: Rect(
-                left: innerRect.left + bar.rect.left,
-                top: innerRect.top + bar.rect.top,
-                right: innerRect.left + bar.rect.right,
-                bottom: innerRect.top + bar.rect.bottom
-            ),
-            color: bar.color,
-            radius: ScrollbarStyle.thumbRadius
-        )
+        return .rrect(
+            Rect(
+                left: innerRect.left + bar.rect.left,
+                top: innerRect.top + bar.rect.top,
+                right: innerRect.left + bar.rect.right,
+                bottom: innerRect.top + bar.rect.bottom
+            ),
+            .uniform(.px(ScrollbarStyle.thumbRadius)),
+            BrowserColor(cssName: bar.color)
+        )
     }
```

### File: `Sources/Engine/Layouts/LineLayout.swift`

```diff
-    func paint(into items: inout [any DisplayItem]) {
+    func paint(into items: inout [DisplayOp]) {
         var outlineRect: Rect? = nil
         var focused: (any DOMNode)? = nil
@@
         }
         if let rect = outlineRect, let focused = focused {
-            if let outline = DrawOutline.fromStyle(focused, rect: rect) {
+            if let outline = DisplayOp.fromStyle(focused, rect: rect) {
                 items.append(outline)
             } else {
-                items.append(DrawOutline(rect: rect, color: focusRingColors(node).outer, thickness: 4))
-                items.append(DrawOutline(rect: rect, color: focusRingColors(node).inner, thickness: 2))
+                items.append(.outline(rect, BrowserColor(cssName: focusRingColors(node).outer), 4))
+                items.append(.outline(rect, BrowserColor(cssName: focusRingColors(node).inner), 2))
             }
         }
     }
```

## Gotcha: `if let` annotation

```swift
if let border: DisplayOp? = DisplayOp.fromBorderStyle(node, rect: borderPaintRect()) {
```

fails with "Value of optional type 'DisplayOp?' must be unwrapped to a value of type 'DisplayOp'". The annotation in a conditional binding names the **unwrapped** type; adding `?` makes `border` a `DisplayOp?` and the check always succeeds. Annotate `DisplayOp`, or omit the annotation:

```swift
if let border: DisplayOp = DisplayOp.fromBorderStyle(node, rect: borderPaintRect()) {
    items.append(border)
}
```

A plain `let outline: DisplayOp? = DisplayOp.fromStyle(...)` is different: there the `?` is correct, because nothing unwraps it yet.

## Scope note

The other `Draw*` constructors in the same functions (e.g. `BlockLayout.swift:1099,1104,1107`) are separate A2 conversions; the build only goes green once every `Draw*` file is gone. This note covers only the outline family, which is what `BlockLayout.swift:1080` needs.

## Verification

```sh
swift build
swift test
swift run ToyStackHeadless "file://$PWD/www/ch11/index.html" \
  --trace /tmp/a2-outline.trace --frame-limit 5 --screenshot /tmp/a2-outline.png
```

Compare with the pre-refactor screenshot; the border/outline pixels must not move.
