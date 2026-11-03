import CoreGraphics

/// Rasterizes and caches the effect bitmap for one composited layer.
enum RasterEffectCache {
    static func update(_ layer: inout RasterLayer, scale: CGFloat, blur: CGFloat) {
        let key: EffectImageKey = EffectImageKey(
            scale: scale,
            blur: blur,
            bounds: layer.compositedBounds()
        )
        guard layer.effect.key != key else { return }
        layer.effect.image = bitmap(layer, scale: scale, blur: blur)
        layer.effect.key = key
    }

    private static func bitmap(_ layer: RasterLayer, scale: CGFloat, blur: CGFloat) -> CGImage? {
        let bounds: Rect = layer.compositedBounds()
        let size: CGSize = CGSize(width: bounds.right - bounds.left, height: bounds.bottom - bounds.top)
        guard size.width > 0, size.height > 0 else { return nil }
        return CGRenderer.renderBitmap(size: size, scale: scale, { renderer in
            if blur > 0 {
                renderer.drawLayer(LayerOptions(blur: blur), content: { inner in
                    layer.raster(renderer: inner)
                })
            } else {
                layer.raster(renderer: renderer)
            }
        })
    }
}
