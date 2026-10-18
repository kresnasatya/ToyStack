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
        let radii: CornerRadii = CSSValueParser.cornerRadii(block.node.style) ?? .zero
        let effect: ScrollEffect = ScrollEffect(
            shape: ClipShape(rect: block.selfRect(), radii: radii),
            scrollOffset: block.scrollOffset,
            node: block.node,
            children: childItems
        )
        displayList.append(effect)
        displayList.append(contentsOf: block.paintScrollbar())
    } else if let block = obj as? BlockLayout, block.node.style["overflow"] == "hidden" || block.node.style["overflow"] == "clip" {
        let radii: CornerRadii = CSSValueParser.cornerRadii(block.node.style) ?? .zero
        let clip: Clip = Clip(
            rect: block.selfRect(),
            shape: ClipShape(rect: block.selfRect(), radii: radii),
            node: block.node,
            children: clippedChildren(of: obj, into: &displayList)
        )
        displayList.append(clip)
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
private func clippedChildren(of obj: any LayoutObject, into displayList: inout [any DisplayItem]) -> [any DisplayItem] {
    let start: Int = displayList.count
    for child in inPaintOrder(obj.children) {
        paintTree(child, into: &displayList)
    }
    let items: [any DisplayItem] = Array(displayList[start...])
    displayList.removeSubrange(start..<displayList.count)
    return items
}

@MainActor
func effectiveZIndex(_ node: any DOMNode) -> Int {
    guard (node.style["position"] ?? "static") != "static" else { return 0 }
    return Int(node.style["z-index"] ?? "0") ?? 0
}

@MainActor
func inPaintOrder(_ children: [any LayoutObject]) -> [any LayoutObject] {
    guard children.contains(where: { ($0.node.style["position"] ?? "static") != "static" })
        else { return children }
    return children.enumerated()
        .sorted { a, b in
            let za: Int = effectiveZIndex(a.element.node)
            let zb: Int = effectiveZIndex(b.element.node)
            return za == zb ? a.offset < b.offset : za < zb
        }
        .map { $0.element }
}
