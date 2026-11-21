import CoreGraphics

enum TileStripRasterizer {
    static func render(_ strip: TileStrip, target: RasterTarget) -> CGImage? {
        let size: CGSize = CGSize(
            width: strip.bounds.right - strip.bounds.left,
            height: strip.bounds.bottom - strip.bounds.top
        )
        return CGRenderer.renderBitmap(size: size, target: target, { r in
            r.translateBy(x: -strip.bounds.left, y: -strip.bounds.top)
            for clip in strip.content.clips {
                r.clipRRect(clip.rect, radii: clip.radii)
            }
            for item in strip.content.items {
                item.execute(renderer: r)
            }
        })
    }
}
