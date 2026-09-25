import CoreGraphics

// MARK: - DrawCompositedLayer
struct DrawCompositedLayer: DisplayCommand {
    var rect: Rect
    var parentEffect: BrowserVisualEffect?
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
