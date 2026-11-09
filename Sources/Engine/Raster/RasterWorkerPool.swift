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
        target: RasterTarget,
        trace: TraceContext,
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
                let lane: TraceLane? = trace.measure?.beginThreadLane("browser.raster.workers")
                defer { lane?.end() }
                trace.measure?.start("raster.strip", category: .raster, frame: trace.frame)
                let image: CGImage? = TileStripRasterizer.render(strips[index], target: target)
                trace.measure?.stop("raster.strip")
                results.set(index, image)
                group.leave()
            }
        }
        group.notify(queue: queue) {
            let lane: TraceLane? = trace.measure?.beginThreadLane("browser.raster.workers")
            defer { lane?.end() }
            trace.measure?.counter("pool", [
                "workers": RasterWorkerPool.defaultWorkerCount,
                "strips": strips.count
            ], frame: trace.frame)
            completion(results.snapshot())
        }
    }
}
