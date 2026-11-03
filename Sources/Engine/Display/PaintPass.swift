import CoreGraphics

// MARK: - PaintPass

/// Emits display ops from a frozen `PaintScene`.
///
/// Everything this pass needs is a value, so it does not touch a `Frame`,
/// a `LayoutTree`, or a `DOMTree`.
struct PaintPass {
    let scene: PaintScene
    var caches: [PaintCacheStore]

    mutating func paint(
        _ frame: Int,
        into ops: inout [DisplayOp],
        session: inout PaintSession
    ) {
        paintNode(0, frame: frame, into: &ops, session: &session)
    }

    // MARK: - Walk

    private mutating func paintNode(
        _ index: Int,
        frame: Int,
        into ops: inout [DisplayOp],
        session: inout PaintSession
    ) {
        let node: PaintNode = scene.frames[frame].nodes[index]
        let rect: Rect = node.geometry.rect
        let epoch: UInt = session.epoch

        switch node.content {
        case .line, .text:
            guard session.window.intersects(rect) else {
                profiler.count("paint.nodes.culled")
                return
            }
        default:
            break
        }

        let start: Int = ops.count
        profiler.count("paint.nodes", by: 1)

        if case .line(let line) = node.content, line.canCache {
            let cache: LinePaintCache = caches[frame].line(node.links.id)
            if cache.canReuse(epoch: epoch, generation: line.generation) {
                cache.append(
                    to: &ops,
                    currentX: node.geometry.frame.left,
                    currentY: node.geometry.frame.top
                )
                profiler.count("paint.cache.hit.lines", by: 1)
                return
            }
        }

        let opened: [OpenScope] = openScopes(node, into: &ops, session: &session)
        let ownStart: Int = ops.count

        if shouldPaint(node) {
            if case .block = node.content {
                let origin: Point = Point(x: node.geometry.frame.left, y: node.geometry.frame.top)
                let key: PaintKey = PaintKey(
                    width: node.geometry.frame.right - node.geometry.frame.left,
                    height: node.geometry.frame.bottom - node.geometry.frame.top,
                    epoch: epoch
                )
                let cache: PaintCache = caches[frame].block(node.links.id)
                if cache.canReuse(key: key) {
                    cache.append(to: &ops, origin: origin)
                    profiler.count("paint.cache.hit.blocks", by: 1)
                } else {
                    emit(node, into: &ops)
                    var stored: PaintCache = cache
                    stored.store(items: Array(ops[ownStart...]), key: key, origin: origin)
                    caches[frame].setBlock(stored, for: node.links.id)
                    profiler.count("paint.cache.store.blocks", by: 1)
                }
            } else {
                emit(node, into: &ops)
            }
        }
        profiler.count("paint.own.items", by: ops.count - ownStart)

        paintChildren(node, frame: frame, into: &ops, session: &session)

        if case .block(let block) = node.content, !block.extras.trailing.isEmpty {
            ops.append(contentsOf: block.extras.trailing)
        }

        closeScopes(opened, node: node, ops: &ops)

        if case .line(let line) = node.content, line.canCache {
            let key: LinePaintKey = LinePaintKey(
                x: node.geometry.frame.left,
                y: node.geometry.frame.top,
                epoch: epoch,
                generation: line.generation
            )
            var cache: LinePaintCache = caches[frame].line(node.links.id)
            cache.store(items: Array(ops[start...]), key: key)
            caches[frame].setLine(cache, for: node.links.id)
            profiler.count("paint.cache.store.lines", by: 1)
        }
    }

    private mutating func paintChildren(
        _ node: PaintNode,
        frame: Int,
        into ops: inout [DisplayOp],
        session: inout PaintSession
    ) {
        if case .embed(.iframe(let iframe)) = node.content {
            let scopes: IframeScopes = openIframeScopes(node, iframe: iframe, into: &ops, session: &session)
            if let child: Int = iframe.frame {
                var childSession: PaintSession = session.with(
                    epoch: scene.frames[child].epoch,
                    window: session.window
                )
                paintNode(0, frame: child, into: &ops, session: &childSession)
            }
            closeIframeScopes(node, iframe: iframe, scopes: scopes, into: &ops)
            return
        }

        if case .block(let block) = node.content, node.surface.style.layout.overflow == .scroll {
            profiler.count("paint.scroll", by: 1)
            let box: Rect = node.geometry.rect
            let visibleTop: CGFloat = box.top + block.scrollOffset
            let visibleBottom: CGFloat = visibleTop + (box.bottom - box.top)
            var visible: [Int] = []
            for child in node.links.children {
                let childBox: Rect = scene.frames[frame].nodes[child].geometry.rect
                if childBox.bottom < visibleTop { continue }
                if childBox.top > visibleBottom { break }
                visible.append(child)
            }
            let radii: CornerRadii = node.surface.style.box.decoration.border.radii
            let shape: ClipShape = ClipShape(rect: box, radii: radii)
            let scope: EffectScope = session.makeScope(
                .scroll(shape, offset: block.scrollOffset),
                node: node.links.dom,
                animatedTransform: false
            ).placed(rect: shape.rect)
            ops.append(.beginEffect(scope))
            for child in paintOrder(visible, frame: frame) {
                paintNode(child, frame: frame, into: &ops, session: &session)
            }
            ops.append(.endEffect)
            return
        }

        if case .block = node.content,
            node.surface.style.layout.overflow == .hidden
                || node.surface.style.layout.overflow == .clip
        {
            let box: Rect = node.geometry.rect
            let radii: CornerRadii = node.surface.style.box.decoration.border.radii
            let scope: EffectScope = session.makeScope(
                .clip(ClipShape(rect: box, radii: radii)),
                node: node.links.dom,
                animatedTransform: false
            ).placed(rect: box)
            ops.append(.beginEffect(scope))
            for child in paintOrder(node.links.children, frame: frame) {
                paintNode(child, frame: frame, into: &ops, session: &session)
            }
            ops.append(.endEffect)
            return
        }

        for child in paintOrder(node.links.children, frame: frame) {
            paintNode(child, frame: frame, into: &ops, session: &session)
        }
    }

    // MARK: - Order

    private func paintOrder(_ children: [Int], frame: Int) -> [Int] {
        let nodes: [PaintNode] = scene.frames[frame].nodes
        guard
            children.contains(where: {
                nodes[$0].surface.style.layout.position.kind != .staticFlow
            })
        else { return children }
        return children.enumerated()
            .sorted { a, b in
                let za: Int = zIndex(nodes[a.element])
                let zb: Int = zIndex(nodes[b.element])
                return za == zb ? a.offset < b.offset : za < zb
            }
            .map { $0.element }
    }

    private func zIndex(_ node: PaintNode) -> Int {
        let layout: LayoutStyle = node.surface.style.layout
        guard layout.position.kind != .staticFlow else { return 0 }
        return layout.zIndex
    }

    private func shouldPaint(_ node: PaintNode) -> Bool {
        if case .block(let block) = node.content { return block.shouldPaint }
        return true
    }
}

// MARK: - Scopes

struct OpenScope {
    let index: Int
    let scope: EffectScope
}

struct IframeScopes {
    let bar: DisplayOp?
    let rect: Rect
}
