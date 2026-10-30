import CoreGraphics

// MARK: - LayoutObject
@MainActor
protocol LayoutObject: AnyObject, FieldOwner {
    var node: any DOMNode { get }
    var parent: (any LayoutObject)? { get }
    var fields: LayoutFieldStore { get set }
    var hasDirtyDescendants: Bool { get set }

    func layout()
    func layoutNeeded() -> Bool
    func selfRect() -> Rect
    func paint(into items: inout [any DisplayItem])
    func shouldPaint() -> Bool
    func paintEffects(into items: inout [any DisplayItem], from start: Int)

}

extension LayoutObject {
    var children: [any LayoutObject] {
        get { childrenField.get() }
        set { childrenField.set(newValue) }
    }

    var x: CGFloat {
        get { xField.get() }
        set { xField.set(newValue) }
    }

    var y: CGFloat {
        get { yField.get() }
        set { yField.set(newValue) }
    }

    var width: CGFloat {
        get { widthField.get() }
        set { widthField.set(newValue) }
    }

    var height: CGFloat {
        get { heightField.get() }
        set { heightField.set(newValue) }
    }

    var zoom: CGFloat {
        get { zoomField.get() }
        set { zoomField.set(newValue) }
    }

    var xField: LayoutFieldHandle<CGFloat> {
        layoutField(.x, \.x, equals: { $0 == $1 })
    }

    var yField: LayoutFieldHandle<CGFloat> {
        layoutField(.y, \.y, equals: { $0 == $1 })
    }

    var widthField: LayoutFieldHandle<CGFloat> {
        layoutField(.width, \.width, equals: { $0 == $1 })
    }

    var heightField: LayoutFieldHandle<CGFloat> {
        layoutField(.height, \.height, equals: { $0 == $1 })
    }

    var zoomField: LayoutFieldHandle<CGFloat> {
        layoutField(.zoom, \.zoom, equals: { $0 == $1 })
    }

    var childrenField: LayoutFieldHandle<[any LayoutObject]> {
        layoutField(.children, \.children, equals: { lhs, rhs in
            guard lhs.count == rhs.count else { return false }
            return zip(lhs, rhs).allSatisfy({ $0 === $1 })
        })
    }

    var fontField: LayoutFieldHandle<BrowserFont> {
        layoutField(.font, \.font, equals: { lhs, rhs in
            CFEqual(lhs.ctFont, rhs.ctFont)
        })
    }

    var ascentField: LayoutFieldHandle<CGFloat> {
        layoutField(.ascent, \.ascent, equals: { $0 == $1 })
    }

    var descentField: LayoutFieldHandle<CGFloat> {
        layoutField(.descent, \.descent, equals: { $0 == $1 })
    }

    func layoutField<Value>(
        _ field: LayoutField,
        _ valuePath: WritableKeyPath<LayoutFieldStore, Value>,
        equals: @escaping (Value, Value) -> Bool
    ) -> LayoutFieldHandle<Value> {
        return LayoutFieldHandle(
            owner: self,
            field: field,
            valuePath: valuePath,
            equals: equals
        )
    }

    func fieldRef(_ field: LayoutField) -> FieldRef {
        return FieldRef(owner: self, name: .layout(field))
    }

    func markField(_ name: FieldName) {
        guard case .layout(let field) = name else { return }
        guard !fields.isDirty(field) else { return }
        profiler.count("layout.field.mark")
        fields.markDirty(field)
        markAncestorsDirty()
    }

    func markAncestorsDirty() {
        var current: (any LayoutObject)? = parent
        while let object = current, !object.hasDirtyDescendants {
            object.hasDirtyDescendants = true
            current = object.parent
        }
    }

    func addDependency(_ name: FieldName, _ field: FieldRef) {
        guard case .layout(let layoutField) = name else { return }
        fields.addDependent(layoutField, field)
    }

    func containsDependency(_ name: FieldName, _ field: FieldRef) -> Bool {
        guard case .layout(let layoutField) = name else { return false }
        return fields.containsDependent(layoutField, field)
    }

    func fieldIsDirty(_ name: FieldName) -> Bool {
        guard case .layout(let field) = name else { return false }
        return fields.isDirty(field)
    }

    func fieldIsFrozen(_ name: FieldName) -> Bool {
        guard case .layout(let field) = name else { return false }
        return fields.isFrozen(field)
    }

    func dependencyNames(_ name: FieldName) -> [String] {
        guard case .layout(let field) = name else { return [] }
        return fields.dependencyNames(field)
    }

    func paintEffects(into items: inout [any DisplayItem], from start: Int) {
        applyPaintEffects(into: &items, from: start)
    }

    func applyPaintEffects(into items: inout [any DisplayItem], from start: Int) {
        if self is LineLayout { return }
        let style: PaintEffectStyle? = profiler.measure("paint.effect.check", {
            paintEffectStyle(node: node)
        })
        guard let style else { return }
        let produced: [any DisplayItem] = Array(items[start...])
        let wrapped: [any DisplayItem] = profiler.measure("paint.effect.wrap", {
            paintBrowserVisualEffects(style: style, node: node, items: produced, rect: selfRect())
        })
        items.replaceSubrange(start..<items.count, with: wrapped)
    }

    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }

    func hitTest(x: CGFloat, y: CGFloat) -> (any LayoutObject)? {
        var x: CGFloat = x
        var y: CGFloat = y

        if let t = CSSValueParser.transform(node.style["transform"] ?? "") {
            x -= t.x
            y -= t.y
        }

        for child in inPaintOrder(children).reversed() {
            if let hit = child.hitTest(x: x, y: y) {
                return hit
            }
        }

        if selfRect().containsPoint(x, y) {
            return self
        }

        return nil
    }

    func linkElement(at x: CGFloat, y: CGFloat) -> Element? {
        var node: (any DOMNode)? = hitTest(x: x, y: y)?.node
        while let current = node {
            if let el = current as? Element, el.tag == "a", el.attributes["href"] != nil {
                return el
            }
            node = current.parent
        }
        return nil
    }

    func absoluteBounds() -> Rect {
        var rect: Rect = selfRect()
        var node: (any DOMNode)? = self.node
        while let current = node {
            if let t = CSSValueParser.transform(current.style["transform"] ?? "") {
                rect = Rect(
                    left: rect.left + t.x,
                    top: rect.top + t.y,
                    right: rect.right + t.x,
                    bottom: rect.bottom + t.y
                )
            }
            node = current.parent
        }
        return rect
    }

    func resolvedZoom() -> CGFloat {
        let parentZoom: CGFloat = parent?.zoomField.read(notify: zoomField) ?? 1.0
        guard let zoomStr = node.style.read("zoom", notify: zoomField) else {
            return parentZoom
        }
        let trimmed: String = zoomStr.trimmingCharacters(in: .whitespaces)
        let factor: CGFloat
        if trimmed.hasSuffix("%"), let pct = Double(trimmed.dropLast()) {
            factor = CGFloat(pct / 100.0)
        } else if let val = Double(trimmed) {
            factor = CGFloat(val)
        } else {
            return parentZoom
        }
        return parentZoom * factor
    }

    func scaled(_ cssPx: CGFloat) -> CGFloat {
        return cssPx * zoom
    }

    var pageZoom: CGFloat {
        return parent?.pageZoom ?? 1.0
    }
}
