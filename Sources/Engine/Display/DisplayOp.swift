import CoreGraphics

public enum DisplayOp {
    case rect(Rect, BrowserColor)
    case rrect(Rect, CornerRadii, BrowserColor)
    case line(Point, Point, BrowserColor, CGFloat)
    case outline(Rect, BrowserColor, CGFloat)
    case text(String, BrowserFont, BrowserColor, Rect)
    case image(CGImage, ImageRendering, Rect, UInt64)
    case clippedImage(CGImage, ImageRendering, Rect, Rect)
    case compositedLayer(CompositedLayer, Rect, CGFloat, CGFloat)
    case effect(BrowserVisualEffect)
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
        case .effect(let effect): return String(describing: type(of: effect))
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
            return .rect(rect.translated(dx: dx, dy: dy), color)
        case .rrect(let rect, let radii, let color):
            return .rrect(rect.translated(dx: dx, dy: dy), radii, color)
        case .line(let from, let to, let color, let width):
            return .line(
                Point(x: from.x + dx, y: from.y + dy),
                Point(x: to.x + dx, y: to.y + dy),
                color,
                width
            )
        case .outline(let rect, let color, let width):
            return .outline(rect.translated(dx: dx, dy: dy), color, width)
        case .text(let text, let font, let color, let rect):
            return .text(text, font, color, rect.translated(dx: dx, dy: dy))
        case .image(let image, let rendering, let rect, let version):
            return .image(image, rendering, rect.translated(dx: dx, dy: dy), version)
        case .clippedImage(let image, let rendering, let rect, let clip):
            return .clippedImage(image, rendering, rect.translated(dx: dx, dy: dy), clip.translated(dx: dx, dy: dy))
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
