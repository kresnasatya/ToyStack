import CoreGraphics

@MainActor
func paintTree(_ obj: any LayoutObject, into displayList: inout [any DisplayItem]) {
    let start: Int = displayList.count

    if obj.shouldPaint() {
        displayList.append(contentsOf: obj.paint())
    }

    if let block = obj as? BlockLayout, block.node.style["overflow"] == "scroll" {
        let childStart: Int = displayList.count
        let visibleTop: CGFloat = block.y + block.scrollOffset
        let visibleBottom: CGFloat = visibleTop + block.height
        var visibleChildren: [any LayoutObject] = []
        for child in obj.children {
            if child.y + child.height < visibleTop { continue }
            if child.y > visibleBottom { break }
            visibleChildren.append(child)
        }
        for child in inPaintOrder(visibleChildren) {
            paintTree(child, into: &displayList)
        }
        let childItems: [any DisplayItem] = Array(displayList[childStart...])
        displayList.removeSubrange(childStart..<displayList.count)
        let effect: ScrollEffect = ScrollEffect(
            rect: block.selfRect(),
            scrollOffset: block.scrollOffset,
            node: block.node,
            children: childItems
        )
        displayList.append(effect)
        displayList.append(contentsOf: block.paintScrollbar())
    } else if let iframe = obj as? IframeLayout,
        let childFrame = (iframe.node as? Element)?.frame, childFrame.loaded,
        let childDoc = childFrame.document {
        paintTree(childDoc, into: &displayList)
    } else {
        for child in inPaintOrder(obj.children) {
            paintTree(child, into: &displayList)
        }
    }

    obj.paintEffects(into: &displayList, from: start)
}

@MainActor
func effectiveZIndex(_ node: any DOMNode) -> Int {
    guard (node.style["position"] ?? "static") != "static" else { return 0 }
    return Int(node.style["z-index"] ?? "0") ?? 0
}

@MainActor
func inPaintOrder(_ children: [any LayoutObject]) -> [any LayoutObject] {
    return children.enumerated()
        .sorted { a, b in
            let za: Int = effectiveZIndex(a.element.node)
            let zb: Int = effectiveZIndex(b.element.node)
            return za == zb ? a.offset < b.offset : za < zb
        }
        .map { $0.element }
}
