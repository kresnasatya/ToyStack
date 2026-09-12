import CoreGraphics

enum TileRasterizer {
    static func render(_ jobs: [TileJob], scale: CGFloat) -> [CGImage?] {
        guard !jobs.isEmpty else { return [] }
        var images = [CGImage?](repeating: nil, count: jobs.count)
        images.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: jobs.count, execute: { i in
                let job = jobs[i]
                buffer[i] = CGRenderer.renderBitmap(
                    size: CGSize(width: CompositedLayer.tileSize, height: CompositedLayer.tileSize),
                    scale: scale
                ) { r in
                    r.translateBy(x: -job.origin.x, y: -job.origin.y)
                    for item in job.inside {
                        item.execute(scroll: 0, renderer: r)
                    }
                }
            })
        }
        return images
    }
}
