import CoreGraphics

@MainActor
func paintTree(
    _ obj: LayoutRef,
    into ops: inout [DisplayOp],
    session: inout PaintSession,
    caches: inout PaintCacheStore
) {
    let window: PaintWindow = session.window
    let epoch: UInt = session.epoch
    if obj.isLine, !window.intersects(obj.selfRect()) {
        profiler.count("paint.nodes.culled")
        return
    }
    if obj.isText, !window.intersects(obj.selfRect()) {
        profiler.count("paint.nodes.culled")
        return
    }

    let start: Int = ops.count
    profiler.count("paint.nodes", by: 1)

    if obj.isLine, obj.tree.lineCanCachePaint(obj), obj.shouldPaint() {
        let cache: LinePaintCache = caches.line(obj.id)
        if cache.canReuse(epoch: epoch, generation: obj.linePaintGeneration) {
            cache.append(to: &ops, currentX: obj.x, currentY: obj.y)
            profiler.count("paint.cache.hit.lines", by: 1)
            return
        }
    }

    let opened: [OpenScope] = openNodeScopes(obj, into: &ops, session: &session)
    let ownStart: Int = ops.count

    if obj.shouldPaint() {
        if obj.isBlock {
            let origin: Point = Point(x: obj.x, y: obj.y)
            let key: PaintKey = PaintKey(
                width: obj.width,
                height: obj.height,
                epoch: epoch
            )
            let cache: PaintCache = caches.block(obj.id)
            if cache.canReuse(key: key) {
                cache.append(to: &ops, origin: origin)
                profiler.count("paint.cache.hit.blocks", by: 1)
            } else {
                obj.paint(into: &ops)
                var stored: PaintCache = cache
                stored.store(
                    items: Array(ops[ownStart...]),
                    key: key,
                    origin: origin
                )
                caches.setBlock(stored, for: obj.id)
                profiler.count("paint.cache.store.blocks", by: 1)
            }
        } else {
            obj.paint(into: &ops)
        }
    }
    profiler.count("paint.own.items", by: ops.count - ownStart)

    if obj.isIframe {
        let scopes: IframeScopes = openIframeScopes(obj, into: &ops, session: &session)
        if let childFrame = obj.node.element?.frame, childFrame.loaded,
            let childDoc = childFrame.document
        {
            var childSession: PaintSession = session.with(epoch: childFrame.paintEpoch, window: window)
            paintTree(
                childDoc.root,
                into: &ops,
                session: &childSession,
                caches: &childFrame.paintCaches
            )
        }
        closeIframeScopes(obj, scopes: scopes, into: &ops)
    } else if obj.isBlock,
        obj.node.style.computed.layout.overflow == .scroll
    {
        profiler.count("paint.scroll", by: 1)
        let box: Rect = obj.selfRect()
        let scrollOffset: CGFloat = obj.tree.blockScrollOffset(obj)
        let visibleTop: CGFloat = box.top + scrollOffset
        let visibleBottom: CGFloat = visibleTop + (box.bottom - box.top)
        var visibleChildren: [LayoutRef] = []
        for child in obj.children {
            let childBox: Rect = child.selfRect()
            if childBox.bottom < visibleTop { continue }
            if childBox.top > visibleBottom { break }
            visibleChildren.append(child)
        }
        let radii: CornerRadii = obj.node.style.computed.box.decoration.border.radii
        let shape: ClipShape = ClipShape(rect: obj.selfRect(), radii: radii)
        let scope: EffectScope = session.makeScope(
            .scroll(shape, offset: scrollOffset),
            node: obj.node.id,
            animatedTransform: false
        ).placed(rect: shape.rect)
        ops.append(.beginEffect(scope))
        for child in inPaintOrder(visibleChildren) {
            paintTree(child, into: &ops, session: &session, caches: &caches)
        }
        ops.append(.endEffect)
        ops.append(contentsOf: obj.tree.blockPaintScrollbar(obj))
    } else if obj.isBlock,
        obj.node.style.computed.layout.overflow == .hidden
            || obj.node.style.computed.layout.overflow == .clip
    {
        let radii: CornerRadii = obj.node.style.computed.box.decoration.border.radii
        let shape: ClipShape = ClipShape(rect: obj.selfRect(), radii: radii)
        let scope: EffectScope = session.makeScope(
            .clip(shape),
            node: obj.node.id,
            animatedTransform: false
        ).placed(rect: obj.selfRect())
        ops.append(.beginEffect(scope))
        for child in inPaintOrder(obj.children) {
            paintTree(child, into: &ops, session: &session, caches: &caches)
        }
        ops.append(.endEffect)
    } else {
        for child in inPaintOrder(obj.children) {
            paintTree(child, into: &ops, session: &session, caches: &caches)
        }
    }

    if obj.isBlock {
        obj.tree.blockPaintCaret(obj, into: &ops)
    }

    closeNodeScopes(opened, obj: obj, ops: &ops)

    if obj.isLine, obj.tree.lineCanCachePaint(obj) {
        let key: LinePaintKey = LinePaintKey(
            x: obj.x,
            y: obj.y,
            epoch: epoch,
            generation: obj.linePaintGeneration
        )
        var cache: LinePaintCache = caches.line(obj.id)
        cache.store(
            items: Array(ops[start...]),
            key: key
        )
        caches.setLine(cache, for: obj.id)
        profiler.count("paint.cache.store.lines", by: 1)
    }
}

// MARK: - Cache generation

extension LayoutRef {
    var linePaintGeneration: UInt {
        return lineData.paint.generation
    }
}

// MARK: - Node scopes

private struct OpenScope {
    let index: Int
    let scope: EffectScope
}

@MainActor
private func openNodeScopes(
    _ obj: LayoutRef,
    into ops: inout [DisplayOp],
    session: inout PaintSession
) -> [OpenScope] {
    var opened: [OpenScope] = []
    for kind in obj.paintScopeKinds() {
        let scope: EffectScope = session.makeScope(
            kind,
            node: obj.node.id,
            animatedTransform: obj.node.animations[.property(.transform)] != nil
        )
        opened.append(OpenScope(index: ops.count, scope: scope))
        ops.append(.beginEffect(scope))
    }
    return opened
}

@MainActor
private func closeNodeScopes(
    _ opened: [OpenScope],
    obj: LayoutRef,
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
    obj: LayoutRef,
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
    _ iframe: LayoutRef,
    into ops: inout [DisplayOp],
    session: inout PaintSession
) -> IframeScopes {
    let rect: Rect = iframe.selfRect()
    let diff: CGFloat = iframe.scaled(1)
    let frame: Frame? = iframe.node.element?.frame
    let scroll: CGFloat = (frame?.loaded ?? false) ? (frame?.scroll ?? 0) : 0

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
        node: iframe.node.id,
        animatedTransform: false
    ).placed(rect: blendRect)
    ops.append(.beginEffect(blend))

    let transform: EffectScope = session.makeScope(
        .transform(CGPoint(x: iframe.x + diff, y: iframe.y + diff - scroll)),
        node: iframe.node.id,
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
    _ iframe: LayoutRef,
    scopes: IframeScopes,
    into ops: inout [DisplayOp]
) {
    ops.append(.endEffect)
    ops.append(.endEffect)
    if let bar = scopes.bar {
        ops.append(bar)
    }
    ops.append(.endEffect)

    if let border: DisplayOp = DisplayOp.fromBorderStyle(iframe.node.style.computed, rect: scopes.rect) {
        ops.append(border)
    }
    if let outline: DisplayOp = DisplayOp.fromStyle(iframe.node.style.computed, rect: scopes.rect) {
        ops.append(outline)
    }
}

@MainActor
private func iframeScrollbar(_ iframe: LayoutRef, innerRect: Rect) -> DisplayOp? {
    guard let frame = iframe.node.element?.frame, frame.loaded, let doc = frame.document else { return nil }
    let contentWidth: CGFloat = innerRect.right - innerRect.left
    let contentHeight: CGFloat = innerRect.bottom - innerRect.top
    guard let bar = scrollbarBarRect(
        ScrollbarGeometry(
            docHeight: doc.root.height + 2 * VSTEP,
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
func effectiveZIndex(_ node: DOMRef) -> Int {
    let layout: LayoutStyle = node.style.computed.layout
    guard layout.position.kind != .staticFlow else { return 0 }
    return layout.zIndex
}
