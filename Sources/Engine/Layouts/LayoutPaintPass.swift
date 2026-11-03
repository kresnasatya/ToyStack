import CoreGraphics

// MARK: - LayoutPaintPass

extension LayoutTree {
    func hitTest(_ id: LayoutID, x: CGFloat, y: CGFloat) -> LayoutID? {
        var x: CGFloat = x
        var y: CGFloat = y

        if let t: CGPoint = domRef(id).style.computed.visual.effects.translation {
            x -= t.x
            y -= t.y
        }

        for child in paintOrder(childrenIDs(of: id)).reversed() {
            if let hit: LayoutID = hitTest(child, x: x, y: y) {
                return hit
            }
        }

        if selfRect(id).containsPoint(x, y) {
            return id
        }

        return nil
    }

    func linkElement(_ id: LayoutID, x: CGFloat, y: CGFloat) -> ElementRef? {
        var current: DOMRef? = hitTest(id, x: x, y: y).map({ domRef($0) })
        while let dom = current {
            if let el = dom.element, el.tag == "a", el.attributes["href"] != nil {
                return el
            }
            current = dom.parent
        }
        return nil
    }

    func paintOrder(_ children: [LayoutID]) -> [LayoutID] {
        guard
            children.contains(where: {
                domRef($0).style.computed.layout.position.kind != .staticFlow
            })
        else { return children }
        return children.enumerated()
            .sorted { a, b in
                let za: Int = zIndex(a.element)
                let zb: Int = zIndex(b.element)
                return za == zb ? a.offset < b.offset : za < zb
            }
            .map { $0.element }
    }

    private func zIndex(_ id: LayoutID) -> Int {
        let layout: LayoutStyle = domRef(id).style.computed.layout
        guard layout.position.kind != .staticFlow else { return 0 }
        return layout.zIndex
    }
}
