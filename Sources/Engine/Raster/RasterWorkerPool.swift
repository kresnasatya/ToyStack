import CoreGraphics
import Foundation

final class RasterWorkerPool: @unchecked Sendable {
    static let defaultWorkerCount: Int = min(ProcessInfo.processInfo.activeProcessorCount, 4)

    private final class Results: @unchecked Sendable {
        private let lock: NSLock = NSLock()
        private var images: [CGImage?]

        init(count: Int) { images = Array(repeating: nil, count: count) }

        func set(_ index: Int, _ image: CGImage?) {
            lock.lock()
            images[index] = image
            lock.unlock()
        }

        func snapshot() -> [CGImage?] {
            lock.lock()
            defer { lock.unlock() }
            return images
        }
    }

    private let queue: DispatchQueue = DispatchQueue(
        label: "browser.raster.workers",
        qos: .userInitiated,
        attributes: .concurrent
    )

    func render(
        _ strips: [TileStrip],
        scale: CGFloat,
        measure: MeasureTime?,
        completion: @escaping @Sendable ([CGImage?]) -> Void
    ) {
        guard !strips.isEmpty else {
            completion([])
            return
        }

        let results: Results = Results(count: strips.count)
        let group: DispatchGroup = DispatchGroup()
        for index in 0..<strips.count {
            group.enter()
            queue.async {
                measure?.start("raster.worker")
                let image: CGImage? = TileStripRasterizer.render(strips[index], scale: scale)
                measure?.stop("raster.worker")
                results.set(index, image)
                group.leave()
            }
        }
        group.notify(queue: queue) {
            measure?.counter("pool", [
                "workers": RasterWorkerPool.defaultWorkerCount,
                "strips": strips.count
            ])
            completion(results.snapshot())
        }
    }
}
