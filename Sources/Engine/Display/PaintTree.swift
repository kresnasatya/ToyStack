import CoreGraphics

@MainActor
func paintTree(_ obj: any LayoutObject, into ops: inout [DisplayOp], session: inout PaintSession) {
    let window: PaintWindow = session.window
    let epoch: UInt = session.epoch
    if let line = obj as? LineLayout, !window.intersects(line.selfRect()) {
        profiler.count("paint.nodes.culled")
        return
    }
    if obj is TextLayout, !window.intersects(obj.selfRect()) {
        profiler.count("paint.nodes.culled")
        return
    }

    let start: Int = ops.count
    profiler.count("paint.nodes", by: 1)

    let line: LineLayout? = obj as? LineLayout
    if let line, line.canCachePaint(), line.shouldPaint(),
        line.paintCache.canReuse(epoch: epoch, generation: line.paintGeneration)
    {
        line.paintCache.append(to: &ops, currentX: line.x, currentY: line.y)
        profiler.count("paint.cache.hit.lines", by: 1)
        return
    }

    let opened: [OpenScope] = openNodeScopes(obj, into: &ops, session: &session)
    let ownStart: Int = ops.count

    if obj.shouldPaint() {
        if let block = obj as? BlockLayout {
            let origin: Point = Point(x: block.x, y: block.y)
            let key: PaintKey = PaintKey(
                width: block.width,
                height: block.height,
                epoch: epoch
            )
            if block.paintCache.canReuse(key: key) {
                block.paintCache.append(to: &ops, origin: origin)
                profiler.count("paint.cache.hit.blocks", by: 1)
            } else {
                obj.paint(into: &ops)
                block.paintCache.store(
                    items: Array(ops[ownStart...]),
                    key: key,
                    origin: origin
                )
                profiler.count("paint.cache.store.blocks", by: 1)
            }
        } else {
            obj.paint(into: &ops)
        }
    }
    profiler.count("paint.own.items", by: ops.count - ownStart)

    if let iframe = obj as? IframeLayout {
        let scopes: IframeScopes = openIframeScopes(iframe, into: &ops, session: &session)
        if let childFrame = (iframe.node as? Element)?.frame, childFrame.loaded,
            let childDoc = childFrame.document
        {
            var childSession: PaintSession = session.with(epoch: childFrame.paintEpoch, window: window)
            paintTree(childDoc, into: &ops, session: &childSession)
        }
        closeIframeScopes(iframe, scopes: scopes, into: &ops)
    } else if let block = obj as? BlockLayout, block.node.style["overflow"] == "scroll" {
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
        let radii: CornerRadii = CSSValueParser.cornerRadii(block.node.style) ?? .zero
        let shape: ClipShape = ClipShape(rect: block.selfRect(), radii: radii)
        let scope: EffectScope = session.makeScope(
            .scroll(shape, offset: block.scrollOffset),
            node: NodeKey(block.node),
            animatedTransform: false
        ).placed(rect: shape.rect)
        ops.append(.beginEffect(scope))
        for child in inPaintOrder(visibleChildren) {
            paintTree(child, into: &ops, session: &session)
        }
        ops.append(.endEffect)
        ops.append(contentsOf: block.paintScrollbar())
    } else if let block = obj as? BlockLayout,
        block.node.style["overflow"] == "hidden" || block.node.style["overflow"] == "clip"
    {
        let radii: CornerRadii = CSSValueParser.cornerRadii(block.node.style) ?? .zero
        let shape: ClipShape = ClipShape(rect: block.selfRect(), radii: radii)
        let scope: EffectScope = session.makeScope(
            .clip(shape),
            node: NodeKey(block.node),
            animatedTransform: false
        ).placed(rect: block.selfRect())
        ops.append(.beginEffect(scope))
        for child in inPaintOrder(obj.children) {
            paintTree(child, into: &ops, session: &session)
        }
        ops.append(.endEffect)
    } else {
        for child in inPaintOrder(obj.children) {
            paintTree(child, into: &ops, session: &session)
        }
    }

    if let block = obj as? BlockLayout {
        block.paintCaret(into: &ops)
    }

    closeNodeScopes(opened, obj: obj, ops: &ops)

    if let line, line.canCachePaint() {
        let key: LinePaintKey = LinePaintKey(
            x: line.x,
            y: line.y,
            epoch: epoch,
            generation: line.paintGeneration
        )
        line.paintCache.store(
            items: Array(ops[start...]),
            key: key
        )
        profiler.count("paint.cache.store.lines", by: 1)
    }
}

// MARK: - Node scopes

private struct OpenScope {
    let index: Int
    let scope: EffectScope
}

@MainActor
private func openNodeScopes(
    _ obj: any LayoutObject,
    into ops: inout [DisplayOp],
    session: inout PaintSession
) -> [OpenScope] {
    var opened: [OpenScope] = []
    for kind in obj.paintScopeKinds() {
        let scope: EffectScope = session.makeScope(
            kind,
            node: NodeKey(obj.node),
            animatedTransform: obj.node.animations["transform"] != nil
        )
        opened.append(OpenScope(index: ops.count, scope: scope))
        ops.append(.beginEffect(scope))
    }
    return opened
}

@MainActor
private func closeNodeScopes(
    _ opened: [OpenScope],
    obj: any LayoutObject,
    ops: inout [DisplayOp]
) {
    for open in opened.reversed() {
        let rect: Rect = scopeRect(open.scope.kind, obj: obj, ops: ops, from: open.index + 1)
        ops[open.index] = .beginEffect(EffectScope(
            id: open.scope.id,
            kind: open.scope.kind,
            placement: EffectPlacement(
                rect: rect,
                node: open.scope.placement.node,
                animatedTransform: open.scope.placement.animatedTransform
            )
        ))
        ops.append(.endEffect)
    }
}

@MainActor
private func scopeRect(
    _ kind: EffectKind,
    obj: any LayoutObject,
    ops: [DisplayOp],
    from start: Int
) -> Rect {
    switch kind {
    case .transform:
        return obj.selfRect()
    case .clip(let shape), .scroll(let shape, _):
        return shape.rect
    case .blend, .blur:
        var rect: Rect = Rect(left: 0, top: 0, right: 0, bottom: 0)
        for index in start..<ops.count {
            switch ops[index] {
            case .beginEffect, .endEffect:
                continue
            default:
                rect = rect.union(ops[index].rect)
            }
        }
        return rect
    }
}

// MARK: - Iframe scopes

private struct IframeScopes {
    let bar: DisplayOp?
    let rect: Rect
}

@MainActor
private func openIframeScopes(
    _ iframe: IframeLayout,
    into ops: inout [DisplayOp],
    session: inout PaintSession
) -> IframeScopes {
    let rect: Rect = iframe.selfRect()
    let diff: CGFloat = iframe.scaled(1)
    let scroll: CGFloat = (iframe.frame?.loaded ?? false) ? (iframe.frame?.scroll ?? 0) : 0

    let innerRect: Rect = Rect(
        left: iframe.x + diff,
        top: iframe.y + diff,
        right: iframe.x + iframe.width - diff,
        bottom: iframe.y + iframe.height - diff
    )

    let clipRect: Rect = Rect(
        left: 0,
        top: scroll,
        right: innerRect.right - innerRect.left,
        bottom: scroll + (innerRect.bottom - innerRect.top)
    )

    let bar: DisplayOp? = iframeScrollbar(iframe, innerRect: innerRect)
    var blendRect: Rect = rect
    if let bar {
        blendRect = blendRect.union(bar.rect)
    }

    let blend: EffectScope = session.makeScope(
        .blend(opacity: 1.0, mode: .normal),
        node: NodeKey(iframe.node),
        animatedTransform: false
    ).placed(rect: blendRect)
    ops.append(.beginEffect(blend))

    let transform: EffectScope = session.makeScope(
        .transform(CGPoint(x: iframe.x + diff, y: iframe.y + diff - scroll)),
        node: NodeKey(iframe.node),
        animatedTransform: false
    ).placed(rect: rect)
    ops.append(.beginEffect(transform))

    let clip: EffectScope = session.makeScope(
        .clip(ClipShape(rect: clipRect, radii: .zero)),
        node: nil,
        animatedTransform: false
    ).placed(rect: innerRect)
    ops.append(.beginEffect(clip))

    return IframeScopes(bar: bar, rect: rect)
}

@MainActor
private func closeIframeScopes(
    _ iframe: IframeLayout,
    scopes: IframeScopes,
    into ops: inout [DisplayOp]
) {
    ops.append(.endEffect)
    ops.append(.endEffect)
    if let bar = scopes.bar {
        ops.append(bar)
    }
    ops.append(.endEffect)

    if let border: DisplayOp = DisplayOp.fromBorderStyle(iframe.node, rect: scopes.rect) {
        ops.append(border)
    }
    if let outline: DisplayOp = DisplayOp.fromStyle(iframe.node, rect: scopes.rect) {
        ops.append(outline)
    }
}

@MainActor
private func iframeScrollbar(_ iframe: IframeLayout, innerRect: Rect) -> DisplayOp? {
    guard let frame = iframe.frame, frame.loaded, let doc = frame.document else { return nil }
    let contentWidth: CGFloat = innerRect.right - innerRect.left
    let contentHeight: CGFloat = innerRect.bottom - innerRect.top
    guard let bar = scrollbarBarRect(
        ScrollbarGeometry(
            docHeight: doc.height + 2 * VSTEP,
            contentHeight: contentHeight,
            contentWidth: contentWidth,
            scroll: frame.scroll
        ),
        forcedColors: frame.tab?.forcedColors ?? false
    )
    else { return nil }
    guard case .rrect(let rect, let radii, let color) = bar else { return nil }
    return .rrect(
        rect: rect.translated(dx: innerRect.left, dy: innerRect.top),
        radii: radii,
        color: color
    )
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
