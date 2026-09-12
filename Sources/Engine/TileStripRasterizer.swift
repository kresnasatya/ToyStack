import CoreGraphics

enum TileStripRasterizer {
    static func render(_ strips: [TileStrip], scale: CGFloat) -> [CGImage?] {
        guard !strips.isEmpty else { return [] }
        var images = [CGImage?](repeating: nil, count: strips.count)
        images.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: strips.count, execute: { i in
                let s = strips[i]
                let size = CGSize(width: s.bounds.right - s.bounds.left, height: s.bounds.bottom - s.bounds.top)
                buffer[i] = CGRenderer.renderBitmap(size: size, scale: scale) { r in
                    r.translateBy(x: -s.bounds.left, y: -s.bounds.top)
                    for item in s.items {
                        item.execute(scroll: 0, renderer: r)
                    }
                }
            })
        }
        return images
    }
}
