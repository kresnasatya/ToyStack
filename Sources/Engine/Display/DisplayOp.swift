import CoreGraphics

public enum DisplayOp {
    case rect(rect: Rect, color: BrowserColor)
    case rrect(rect: Rect, radii: CornerRadii, color: BrowserColor)
    case line(from: Point, to: Point, color: BrowserColor, width: CGFloat)
    case outline(rect: Rect, color: BrowserColor, width: CGFloat)
    case text(text: String, font: BrowserFont, color: BrowserColor, rect: Rect)
    case image(image: CGImage, rendering: ImageRendering, rect: Rect, version: UInt64)
    case clippedImage(image: CGImage, rendering: ImageRendering, rect: Rect, clip: Rect)
    case compositedLayer(layer: CompositedLayer, rect: Rect, visibleTop: CGFloat, visibleBottom: CGFloat)
    case effect(DisplayEffect)
}

extension DisplayOp {
    var rect: Rect {
        switch self {
        case .rect(let rect, _), .rrect(let rect, _, _), .outline(let rect, _, _),
            .text(_, _, _, let rect), .image(_, _, let rect, _),
            .clippedImage(_, _, let rect, _), .compositedLayer(_, let rect, _, _):
            return rect
        case .line(let from, let to, _, _):
            return Rect(left: from.x, top: from.y, right: to.x, bottom: to.y)
        case .effect(let effect):
            return effect.rect
        }
    }

    var name: String {
        switch self {
        case .rect: return "rect"
        case .rrect: return "rrect"
        case .line: return "line"
        case .outline: return "outline"
        case .text: return "text"
        case .image: return "image"
        case .clippedImage: return "clippedImage"
        case .compositedLayer: return "compositedLayer"
        case .effect(let effect): return effect.name
        }
    }

    public func execute(renderer: any Renderer) {
        switch self {
        case .rect(let rect, let color):
            renderer.fillRect(rect, color: color)
        case .rrect(let rect, let radii, let color):
            renderer.fillRRect(rect, radii: radii, color: color)
        case .line(let from, let to, let color, let width):
            renderer.strokeSegment(from: from, to: to, color: color, lineWidth: width)
        case .outline(let rect, let color, let width):
            renderer.strokeRect(rect, color: color, lineWidth: width)
        case .text(let text, let font, let color, let rect):
            renderer.drawText(text, font: font, color: color, at: Point(x: rect.left, y: rect.top))
        case .image(let image, let rendering, let rect, _):
            renderer.drawImage(image, in: rect, rendering: rendering)
        case .clippedImage(let image, let rendering, let rect, let clip):
            renderer.saveState()
            renderer.clip(to: clip)
            renderer.drawImage(image, in: rect, rendering: rendering)
            renderer.restoreState()
        case .compositedLayer(let layer, _, let visibleTop, let visibleBottom):
            executeCompositedLayer(layer, visibleTop: visibleTop, visibleBottom: visibleBottom, renderer: renderer)
        case .effect(let effect):
            effect.execute(renderer: renderer)
        }
    }

    func shifted(dx: CGFloat, dy: CGFloat) -> DisplayOp {
        switch self {
        case .rect(let rect, let color):
            return .rect(rect: rect.translated(dx: dx, dy: dy), color: color)
        case .rrect(let rect, let radii, let color):
            return .rrect(rect: rect.translated(dx: dx, dy: dy), radii: radii, color: color)
        case .line(let from, let to, let color, let width):
            return .line(
                from: Point(x: from.x + dx, y: from.y + dy),
                to: Point(x: to.x + dx, y: to.y + dy),
                color: color,
                width: width
            )
        case .outline(let rect, let color, let width):
            return .outline(rect: rect.translated(dx: dx, dy: dy), color: color, width: width)
        case .text(let text, let font, let color, let rect):
            return .text(text: text, font: font, color: color, rect: rect.translated(dx: dx, dy: dy))
        case .image(let image, let rendering, let rect, let version):
            return .image(image: image, rendering: rendering, rect: rect.translated(dx: dx, dy: dy), version: version)
        case .clippedImage(let image, let rendering, let rect, let clip):
            return .clippedImage(image: image, rendering: rendering, rect: rect.translated(dx: dx, dy: dy), clip: clip.translated(dx: dx, dy: dy))
        case .compositedLayer, .effect:
            preconditionFailure("\(name) cannot be shifted")
        }
    }

    var contentHash: Int {
        var hasher: Hasher = Hasher()
        hasher.combine(name)
        hasher.combine(rect.left)
        hasher.combine(rect.top)
        hasher.combine(rect.right)
        hasher.combine(rect.bottom)
        switch self {
        case .rect(_, let color), .outline(_, let color, _):
            hasher.combine(color)
        case .rrect(_, let radii, let color):
            hasher.combine(color)
            hasher.combine(radii)
        case .line(_, _, let color, let width):
            hasher.combine(color)
            hasher.combine(width)
        case .text(let text, let font, let color, _):
            hasher.combine(text)
            hasher.combine(color)
            hasher.combine(ObjectIdentifier(font.ctFont))
        case .image(let image, let rendering, _, let version):
            hasher.combine(ObjectIdentifier(image))
            hasher.combine(rendering.rawValue)
            hasher.combine(version)
        case .clippedImage(let image, let rendering, _, let clip):
            hasher.combine(ObjectIdentifier(image))
            hasher.combine(rendering.rawValue)
            hasher.combine(clip.left)
            hasher.combine(clip.top)
            hasher.combine(clip.right)
            hasher.combine(clip.bottom)
        case .compositedLayer, .effect:
            break
        }
        return hasher.finalize()
    }

    // MARK: - Outline factories

    @MainActor
    static func fromStyle(_ node: any DOMNode, rect: Rect) -> DisplayOp? {
        let style: String = node.style["outline-style"] ?? "none"
        guard style != "none", style != "hidden" else { return nil }
        guard let thickness: CGFloat = CSSValueParser.outlineWidth(node.style["outline-width"] ?? "medium"),
            thickness > 0
        else { return nil }
        let color: String = node.style["outline-color"] ?? node.style["color"] ?? "black"
        return .outline(rect: rect, color: BrowserColor(cssName: color), width: thickness)
    }

    @MainActor
    static func fromBorderStyle(_ node: any DOMNode, rect: Rect) -> DisplayOp? {
        let style: String = node.style["border-style"] ?? "none"
        guard style != "none", style != "hidden" else { return nil }
        guard let thickness: CGFloat = CSSValueParser.outlineWidth(node.style["border-width"] ?? "medium"),
            thickness > 0
        else { return nil }
        let color: String = node.style["border-color"] ?? "black"
        return .outline(rect: rect, color: BrowserColor(cssName: color), width: thickness)
    }
}

func walkDisplayItems(
    _ items: [DisplayOp],
    scopes: [EffectScope] = [],
    visit: (DisplayOp, [EffectScope]) -> Void
) {
    for item in items {
        if case .effect(let effect) = item {
            walkDisplayItems(effect.children, scopes: scopes + [effect.scope], visit: visit)
        } else {
            visit(item, scopes)
        }
    }
}

private func executeCompositedLayer(
    _ layer: CompositedLayer,
    visibleTop: CGFloat,
    visibleBottom: CGFloat,
    renderer: any Renderer
) {
    let bounds: Rect = layer.compositedBounds()
    if !layer.tiles.isEmpty {
        let t: CGFloat = CompositedLayer.tileSize
        for index in layer.orderedTileIndices {
            guard let image: CGImage = layer.tiles[index] else { continue }
            let tileLeft: CGFloat = CGFloat(index.col) * t
            let tileTop: CGFloat = CGFloat(index.row) * t
            if tileTop + t <= visibleTop || tileTop >= visibleBottom { continue }
            renderer.drawImage(image, in: Rect(left: tileLeft, top: tileTop, right: tileLeft + t, bottom: tileTop + t))
        }
    } else {
        renderer.saveState()
        renderer.translateBy(x: bounds.left, y: bounds.top)
        layer.raster(renderer: renderer)
        renderer.restoreState()
    }
}
