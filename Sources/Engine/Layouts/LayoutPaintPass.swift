import CoreGraphics

// MARK: - LayoutPaintPass

extension LayoutRef {
    func resolvedZoom() -> CGFloat {
        let parentZoom: CGFloat = parent?.zoomField.read(notify: zoomField) ?? 1.0
        node.style.field(.zoom).touch(zoomField)
        guard let factor: CGFloat = node.style.computed.box.zoom else {
            return parentZoom
        }
        return parentZoom * factor
    }

    func scaled(_ cssPx: CGFloat) -> CGFloat {
        return cssPx * zoom
    }

    var pageZoom: CGFloat {
        if let parent { return parent.pageZoom }
        return tree.node(id).kind.documentPageZoom
    }

    func paintScopeKinds() -> [EffectKind] {
        if case .line = kind { return [] }
        let style: PaintEffectStyle? = profiler.measure("paint.effect.check", {
            paintEffectStyle(node: node)
        })
        guard let style else { return [] }
        var kinds: [EffectKind] = [.transform(style.translation)]
        kinds.append(.blend(opacity: style.opacity, mode: style.blendMode))
        if style.blurRadius > 0 {
            kinds.append(.blur(radius: style.blurRadius))
        }
        return kinds
    }

    func absoluteBounds() -> Rect {
        var rect: Rect = selfRect()
        var current: DOMRef? = node
        while let dom = current {
            if let t: CGPoint = dom.style.computed.visual.effects.translation {
                rect = Rect(
                    left: rect.left + t.x,
                    top: rect.top + t.y,
                    right: rect.right + t.x,
                    bottom: rect.bottom + t.y
                )
            }
            current = dom.parent
        }
        return rect
    }

    func hitTest(x: CGFloat, y: CGFloat) -> LayoutRef? {
        var x: CGFloat = x
        var y: CGFloat = y

        if let t: CGPoint = node.style.computed.visual.effects.translation {
            x -= t.x
            y -= t.y
        }

        for child in inPaintOrder(children).reversed() {
            if let hit: LayoutRef = child.hitTest(x: x, y: y) {
                return hit
            }
        }

        if selfRect().containsPoint(x, y) {
            return self
        }

        return nil
    }

    func linkElement(at x: CGFloat, y: CGFloat) -> ElementRef? {
        var current: DOMRef? = hitTest(x: x, y: y)?.node
        while let dom = current {
            if let el = dom.element, el.tag == "a", el.attributes["href"] != nil {
                return el
            }
            current = dom.parent
        }
        return nil
    }

    func paint(into items: inout [DisplayOp]) {
        switch kind {
        case .document:
            break
        case .block:
            tree.paintBlock(self, into: &items)
        case .line:
            tree.paintLine(self, into: &items)
        case .text:
            tree.paintText(self, into: &items)
        case .embed(let data):
            switch data {
            case .image:
                tree.paintImage(self, into: &items)
            case .input:
                tree.paintInput(self, into: &items)
            case .button:
                tree.paintButton(self, into: &items)
            case .iframe:
                tree.paintIframe(self, into: &items)
            case .canvas:
                tree.paintCanvas(self, into: &items)
            }
        }
    }

    func shouldPaint() -> Bool {
        switch kind {
        case .block:
            return tree.blockShouldPaint(self)
        default:
            return true
        }
    }
}

extension LayoutKind {
    var documentPageZoom: CGFloat {
        if case .document(let data) = self { return data.pageZoom }
        return 1
    }
}

@MainActor
func inPaintOrder(_ children: [LayoutRef]) -> [LayoutRef] {
    guard children.contains(where: { $0.node.style.computed.layout.position.kind != .staticFlow })
        else { return children }
    return children.enumerated()
        .sorted { a, b in
            let za: Int = effectiveZIndex(a.element.node)
            let zb: Int = effectiveZIndex(b.element.node)
            return za == zb ? a.offset < b.offset : za < zb
        }
        .map { $0.element }
}
