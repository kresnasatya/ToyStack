import CoreGraphics

// MARK: - LayoutPaintPass

extension LayoutTree {
    func hitTest(_ id: LayoutID, x: CGFloat, y: CGFloat) -> LayoutID? {
        var x: CGFloat = x
        var y: CGFloat = y

        if let t: CGPoint = inputs.style(domID(of: id)).visual.effects.translation {
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

    func linkHref(_ id: LayoutID, x: CGFloat, y: CGFloat) -> String? {
        var current: NodeID? = hitTest(id, x: x, y: y).map({ domID(of: $0) })
        while let node = current {
            if inputs.tag(node) == "a", let href = inputs.attributes(node)["href"] {
                return href
            }
            current = inputs.parent(node)
        }
        return nil
    }

    func paintOrder(_ children: [LayoutID]) -> [LayoutID] {
        guard
            children.contains(where: {
                inputs.style(domID(of: $0)).layout.position.kind != .staticFlow
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
        let layout: LayoutStyle = inputs.style(domID(of: id)).layout
        guard layout.position.kind != .staticFlow else { return 0 }
        return layout.zIndex
    }
}
