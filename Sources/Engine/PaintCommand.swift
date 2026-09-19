import CoreGraphics

// MARK: - PaintCommand
public protocol PaintCommand {
    var rect: Rect { get }
    var parentEffect: VisualEffect? { get set }
    func execute(scroll: CGFloat, renderer: any Renderer)
}

// MARK: - DrawRect
public struct DrawRect: PaintCommand {
    public let rect: Rect
    public let color: String
    public var parentEffect: VisualEffect? = nil

    public init(rect: Rect, color: String) {
        self.rect = rect
        self.color = color
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        let r: CGRect = CGRect(
            x: rect.left,
            y: rect.top - scroll,
            width: rect.right - rect.left,
            height: rect.bottom - rect.top
        )
        renderer.fillRect(r, color: EngineColor(cssName: color))
    }
}

// MARK: - DrawLine
public struct DrawLine: PaintCommand {
    public let rect: Rect
    public let color: String
    public let thickness: CGFloat
    public var parentEffect: VisualEffect? = nil

    public init(
        from: CGPoint,
        to: CGPoint,
        color: String,
        thickness: CGFloat
    ) {
        self.rect = Rect(left: from.x, top: from.y, right: to.x, bottom: to.y)
        self.color = color
        self.thickness = thickness
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.strokeSegment(
            from: CGPoint(x: rect.left, y: rect.top - scroll),
            to: CGPoint(x: rect.right, y: rect.bottom - scroll),
            color: EngineColor(cssName: color),
            lineWidth: thickness
        )
    }
}

// MARK: - DrawText
public struct DrawText: PaintCommand {
    public let rect: Rect
    public let text: String
    public let font: BrowserFont
    public let color: String
    public var parentEffect: VisualEffect? = nil

    public init(
        at point: CGPoint, text: String, font: BrowserFont, color: String
    ) {
        self.rect = Rect(
            left: point.x,
            top: point.y,
            right: point.x + font.measure(text),
            bottom: point.y + font.linespace
        )
        self.text = text
        self.font = font
        self.color = color
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.drawText(text, font: font.ctFont, color: EngineColor(cssName: color), at: CGPoint(x: rect.left, y: rect.top - scroll))
    }
}

// MARK: - DrawOutline
public struct DrawOutline: PaintCommand {
    public let rect: Rect
    public let color: String
    public let thickness: CGFloat
    public var parentEffect: VisualEffect? = nil

    public init(rect: Rect, color: String, thickness: CGFloat) {
        self.rect = rect
        self.color = color
        self.thickness = thickness
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        let r: CGRect = CGRect(
            x: rect.left, y: rect.top - scroll, width: rect.right - rect.left,
            height: rect.bottom - rect.top)
        renderer.strokeRect(r, color: EngineColor(cssName: color), lineWidth: thickness)
    }
}

// MARK: - DrawCompositedLayer
struct DrawCompositedLayer: PaintCommand {
    var rect: Rect
    var parentEffect: VisualEffect?
    let layer: CompositedLayer
    var visibleTop: CGFloat = -.infinity
    var visibleBottom: CGFloat = .infinity

    init(layer: CompositedLayer, visibleTop: CGFloat, visibleBottom: CGFloat) {
        self.layer = layer
        self.visibleTop = visibleTop
        self.visibleBottom = visibleBottom
        self.rect = layer.absoluteBounds()
    }

    func execute(scroll: CGFloat, renderer: any Renderer) {
        let bounds: Rect = layer.compositedBounds()
        if !layer.tiles.isEmpty {
            let t: CGFloat = CompositedLayer.tileSize
            for (index, image) in layer.tiles {
                let tileLeft: CGFloat = CGFloat(index.col) * t
                let tileTop: CGFloat = CGFloat(index.row) * t
                if tileTop + t <= visibleTop || tileTop >= visibleBottom { continue }
                renderer.drawImage(image, in: CGRect(x: tileLeft, y: tileTop, width: t, height: t))
            }
        } else {
            renderer.saveState()
            renderer.translateBy(x: bounds.left, y: bounds.top)
            layer.raster(renderer: renderer)
            renderer.restoreState()
        }

    }
}

// MARK: - DrawRRect
struct DrawRRect: PaintCommand {
    var rect: Rect
    var parentEffect: VisualEffect?
    let radius: CGFloat
    let color: String

    func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.fillRRect(rect.cgRect, radius: radius, color: EngineColor(cssName: color))
    }
}
