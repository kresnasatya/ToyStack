import CoreGraphics

enum TileStripRasterizer {
    static func render(_ strip: TileStrip, scale: CGFloat) -> CGImage? {
        let size: CGSize = CGSize(
            width: strip.bounds.right - strip.bounds.left,
            height: strip.bounds.bottom - strip.bounds.top
        )
        return CGRenderer.renderBitmap(size: size, scale: scale, { r in
            r.translateBy(x: -strip.bounds.left, y: -strip.bounds.top)
            for item in strip.items {
                item.execute(scroll: 0, renderer: r)
            }
        })
    }
}
