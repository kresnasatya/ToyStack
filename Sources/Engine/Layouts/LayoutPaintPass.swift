import CoreGraphics

// MARK: - LayoutPaintPass

extension LayoutRef {
    func resolvedZoom() -> CGFloat {
        return tree.resolvedZoom(id)
    }

    func scaled(_ cssPx: CGFloat) -> CGFloat {
        return cssPx * zoom
    }

    var pageZoom: CGFloat {
        if let parent { return parent.pageZoom }
        return tree.node(id).kind.documentPageZoom
    }

    func absoluteBounds() -> Rect {
        var rect: Rect = selfRect()
        var current: DOMRef? = node
        while let dom = current {
            if let t: CGPoint = dom.style.computed.visual.effects.translation {
                rect = Rect(
                    left: rect.left + t.x,
                    top: rect.top + t.y,
                    right: rect.right + t.x,
                    bottom: rect.bottom + t.y
                )
            }
            current = dom.parent
        }
        return rect
    }

    func hitTest(x: CGFloat, y: CGFloat) -> LayoutRef? {
        var x: CGFloat = x
        var y: CGFloat = y

        if let t: CGPoint = node.style.computed.visual.effects.translation {
            x -= t.x
            y -= t.y
        }

        for child in inPaintOrder(children).reversed() {
            if let hit: LayoutRef = child.hitTest(x: x, y: y) {
                return hit
            }
        }

        if selfRect().containsPoint(x, y) {
            return self
        }

        return nil
    }

    func linkElement(at x: CGFloat, y: CGFloat) -> ElementRef? {
        var current: DOMRef? = hitTest(x: x, y: y)?.node
        while let dom = current {
            if let el = dom.element, el.tag == "a", el.attributes["href"] != nil {
                return el
            }
            current = dom.parent
        }
        return nil
    }
}

extension LayoutKind {
    var documentPageZoom: CGFloat {
        if case .document(let data) = self { return data.pageZoom }
        return 1
    }
}

@MainActor
func inPaintOrder(_ children: [LayoutRef]) -> [LayoutRef] {
    guard children.contains(where: { $0.node.style.computed.layout.position.kind != .staticFlow })
        else { return children }
    return children.enumerated()
        .sorted { a, b in
            let za: Int = effectiveZIndex(a.element.node)
            let zb: Int = effectiveZIndex(b.element.node)
            return za == zb ? a.offset < b.offset : za < zb
        }
        .map { $0.element }
}

@MainActor
func effectiveZIndex(_ node: DOMRef) -> Int {
    let layout: LayoutStyle = node.style.computed.layout
    guard layout.position.kind != .staticFlow else { return 0 }
    return layout.zIndex
}
