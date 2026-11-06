import CoreGraphics

// MARK: - LayoutPaintPass

extension LayoutTree {
    func hitTest(_ id: LayoutID, x: CGFloat, y: CGFloat) -> LayoutHit? {
        var x: CGFloat = x
        var y: CGFloat = y

        if let t: CGPoint = inputs.style(domID(of: id)).visual.effects.translation {
            x -= t.x
            y -= t.y
        }

        let boxes: [InlineBox]? = isLine(id) ? currentInlineBoxes(id) : nil
        let childIDs: [LayoutID] = boxes == nil
            ? childrenIDs(of: id)
            : childrenIDs(of: id).filter({ !isText($0) })
        for child in paintOrder(childIDs).reversed() {
            if let hit: LayoutHit = hitTest(child, x: x, y: y) {
                return hit
            }
        }

        if let boxes {
            for box in boxes.reversed() {
                let rect: Rect = Rect(
                    left: box.geometry.x,
                    top: self.y(id) + box.geometry.y,
                    right: box.geometry.x + box.geometry.width,
                    bottom: self.y(id) + box.geometry.y + box.text.font.linespace
                )
                if rect.containsPoint(x, y) {
                    return LayoutHit(layout: id, dom: box.dom)
                }
            }
        }

        if selfRect(id).containsPoint(x, y) {
            return LayoutHit(layout: id, dom: domID(of: id))
        }

        return nil
    }

    func linkHref(_ id: LayoutID, x: CGFloat, y: CGFloat) -> String? {
        var current: NodeID? = hitTest(id, x: x, y: y)?.dom
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
