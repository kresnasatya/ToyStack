import CoreGraphics

func paintTree(_ obj: any LayoutObject, into displayList: inout [any DisplayItem]) {
    var items: [any DisplayItem] = []

    if obj.shouldPaint() {
        items.append(contentsOf: obj.paint())
    }

    if let block = obj as? BlockLayout, block.node.style["overflow"] == "scroll" {
        var childItems: [any DisplayItem] = []
        let visibleTop: CGFloat = block.y + block.scrollOffset
        let visibleBottom: CGFloat = visibleTop + block.height
        var visibleChildren: [any LayoutObject] = []
        for child in obj.children {
            if child.y + child.height < visibleTop { continue }
            if child.y > visibleBottom { break }
            visibleChildren.append(child)
        }
        for child in inPaintOrder(visibleChildren) {
            paintTree(child, into: &childItems)
        }
        let effect: ScrollEffect = ScrollEffect(
            rect: block.selfRect(),
            scrollOffset: block.scrollOffset,
            node: block.node,
            children: childItems
        )
        items.append(effect)
        items.append(contentsOf: block.paintScrollbar())
    } else {
        for child in inPaintOrder(obj.children) {
            paintTree(child, into: &items)
        }
    }

    items = paintBrowserVisualEffects(node: obj.node, items: items, rect: obj.selfRect())

    displayList.append(contentsOf: items)
}

func effectiveZIndex(_ node: any DOMNode) -> Int {
    guard (node.style["position"] ?? "static") != "static" else { return 0 }
    return Int(node.style["z-index"] ?? "0") ?? 0
}

func inPaintOrder(_ children: [any LayoutObject]) -> [any LayoutObject] {
    return children.enumerated()
        .sorted { a, b in
            let za: Int = effectiveZIndex(a.element.node)
            let zb: Int = effectiveZIndex(b.element.node)
            return za == zb ? a.offset < b.offset : za < zb
        }
        .map { $0.element }
}
