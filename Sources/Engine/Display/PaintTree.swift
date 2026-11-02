import CoreGraphics

@MainActor
func paintTree(_ obj: any LayoutObject, into displayList: inout [DisplayOp], epoch: UInt, window: PaintWindow, session: inout PaintSession) {
    if let line = obj as? LineLayout, !window.intersects(line.selfRect()) {
        profiler.count("paint.nodes.culled")
        return
    }
    if obj is TextLayout, !window.intersects(obj.selfRect()) {
        profiler.count("paint.nodes.culled")
        return
    }

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
        let box: Rect = block.selfRect()
        let visibleTop: CGFloat = box.top + block.scrollOffset
        let visibleBottom: CGFloat = visibleTop + (box.bottom - box.top)
        var visibleChildren: [any LayoutObject] = []
        for child in obj.children {
            let childBox: Rect = child.selfRect()
            if childBox.bottom < visibleTop { continue }
            if childBox.top > visibleBottom { break }
            visibleChildren.append(child)
        }
        for child in inPaintOrder(visibleChildren) {
            paintTree(child, into: &displayList, epoch: epoch, window: window, session: &session)
        }
        let childItems: [DisplayOp] = Array(displayList[childStart...])
        displayList.removeSubrange(childStart..<displayList.count)
        let radii: CornerRadii = CSSValueParser.cornerRadii(block.node.style) ?? .zero
        let shape: ClipShape = ClipShape(rect: block.selfRect(), radii: radii)
        let scope: EffectScope = session.makeScope(
            .scroll(shape, offset: block.scrollOffset),
            node: NodeKey(block.node),
            animatedTransform: false
        ).placed(rect: shape.rect)
        displayList.append(.effect(DisplayEffect(scope: scope, children: childItems)))
        displayList.append(contentsOf: block.paintScrollbar())
    } else if let block = obj as? BlockLayout, block.node.style["overflow"] == "hidden" || block.node.style["overflow"] == "clip" {
        let radii: CornerRadii = CSSValueParser.cornerRadii(block.node.style) ?? .zero
        let shape: ClipShape = ClipShape(rect: block.selfRect(), radii: radii)
        let scope: EffectScope = session.makeScope(
            .clip(shape),
            node: NodeKey(block.node),
            animatedTransform: false
        ).placed(rect: block.selfRect())
        let children: [DisplayOp] = clippedChildren(
            of: obj,
            into: &displayList,
            epoch: epoch,
            window: window,
            session: &session
        )
        displayList.append(.effect(DisplayEffect(scope: scope, children: children)))
    } else if let iframe = obj as? IframeLayout,
        let childFrame = (iframe.node as? Element)?.frame, childFrame.loaded,
        let childDoc = childFrame.document {
        paintTree(childDoc, into: &displayList, epoch: childFrame.paintEpoch, window: window, session: &session)
    } else {
        for child in inPaintOrder(obj.children) {
            paintTree(child, into: &displayList, epoch: epoch, window: window, session: &session)
        }
    }

    obj.paintEffects(into: &displayList, from: start, session: &session)

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
private func clippedChildren(of obj: any LayoutObject, into displayList: inout [DisplayOp], epoch: UInt, window: PaintWindow, session: inout PaintSession) -> [DisplayOp] {
    let start: Int = displayList.count
    for child in inPaintOrder(obj.children) {
        paintTree(child, into: &displayList, epoch: epoch, window: window, session: &session)
    }
    let items: [DisplayOp] = Array(displayList[start...])
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
