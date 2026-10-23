import CoreGraphics

@MainActor
func paintTree(_ obj: any LayoutObject, into displayList: inout [any DisplayItem], epoch: UInt) {
    let start: Int = displayList.count
    profiler.count("paint.nodes", by: 1)

    let line: LineLayout? = obj as? LineLayout
    if let line, line.canCachePaint(), line.shouldPaint(),
        line.paintCache.canReuse(epoch: epoch, generation: line.paintGeneration)
    {
        line.paintCache.append(to: &displayList, currentX: line.x, currentY: line.y)
        profiler.count("paint.cache.hit.lines", by: 1)
        return
    }

    if obj.shouldPaint() {
        if let block = obj as? BlockLayout {
            let origin: Point = Point(x: block.x, y: block.y)
            let key: PaintKey = PaintKey(
                width: block.width,
                height: block.height,
                epoch: epoch
            )
            if block.paintCache.canReuse(key: key) {
                block.paintCache.append(to: &displayList, origin: origin)
                profiler.count("paint.cache.hit.blocks", by: 1)
            } else {
                let ownStart: Int = displayList.count
                obj.paint(into: &displayList)
                block.paintCache.store(
                    items: Array(displayList[ownStart...]),
                    key: key,
                    origin: origin
                )
                profiler.count("paint.cache.store.blocks", by: 1)
            }
        } else {
            obj.paint(into: &displayList)
        }
    }
    profiler.count("paint.own.items", by: displayList.count - start)

    if let block = obj as? BlockLayout, block.node.style["overflow"] == "scroll" {
        let childStart: Int = displayList.count
        profiler.count("paint.scroll", by: 1)
        let visibleTop: CGFloat = block.y + block.scrollOffset
        let visibleBottom: CGFloat = visibleTop + block.height
        var visibleChildren: [any LayoutObject] = []
        for child in obj.children {
            if child.y + child.height < visibleTop { continue }
            if child.y > visibleBottom { break }
            visibleChildren.append(child)
        }
        for child in inPaintOrder(visibleChildren) {
            paintTree(child, into: &displayList, epoch: epoch)
        }
        let childItems: [any DisplayItem] = profiler.measure("paint.range.copy", {
            Array(displayList[childStart...])
        })
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
            children: clippedChildren(of: obj, into: &displayList, epoch: epoch)
        )
        displayList.append(clip)
    } else if let iframe = obj as? IframeLayout,
        let childFrame = (iframe.node as? Element)?.frame, childFrame.loaded,
        let childDoc = childFrame.document {
        paintTree(childDoc, into: &displayList, epoch: childFrame.paintEpoch)
    } else {
        for child in inPaintOrder(obj.children) {
            paintTree(child, into: &displayList, epoch: epoch)
        }
    }

    obj.paintEffects(into: &displayList, from: start)

    if let line, line.canCachePaint() {
        let key: LinePaintKey = LinePaintKey(
            x: line.x,
            y: line.y,
            epoch: epoch,
            generation: line.paintGeneration
        )
        line.paintCache.store(
            items: Array(displayList[start...]),
            key: key
        )
        profiler.count("paint.cache.store.lines", by: 1)
    }
}

@MainActor
private func clippedChildren(of obj: any LayoutObject, into displayList: inout [any DisplayItem], epoch: UInt) -> [any DisplayItem] {
    let start: Int = displayList.count
    for child in inPaintOrder(obj.children) {
        paintTree(child, into: &displayList, epoch: epoch)
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
