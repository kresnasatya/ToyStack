import CoreGraphics
import Foundation

class RasterScheduler: @unchecked Sendable {
    struct Job {
        let scale: CGFloat
        let plan: @Sendable (TileStore) -> RasterPlan
        let install: @Sendable (TileStore, RasterPlan, [CGImage?]) -> RasterOutput
        let then: @MainActor (RasterOutput) -> Void
    }

    private let queue: DispatchQueue = DispatchQueue(label: "browser.compositor", qos: .userInitiated)
    private let workers: RasterWorkerPool = RasterWorkerPool()
    let tileStore: TileStore = TileStore(tileSize: CompositedLayer.tileSize)
    var measure: MeasureTime?
    private let lock: NSLock = NSLock()
    private var pending: Job?
    private var draining: Bool = false

    func schedule(_ job: Job) {
        lock.lock()
        pending = job
        let kick: Bool = !draining
        if kick { draining = true }
        lock.unlock()
        if kick { queue.async { self.drain() } }
    }

    private func drain() {
        lock.lock()
        guard let job = pending else {
            draining = false
            lock.unlock()
            return
        }
        pending = nil
        lock.unlock()

        let plan: RasterPlan = job.plan(tileStore)
        guard !plan.batch.strips.isEmpty else {
            finish(job: job, plan: plan, images: [])
            return
        }
        workers.render(plan.batch.strips, scale: job.scale, measure: measure) { images in
            self.queue.async {
                self.finish(job: job, plan: plan, images: images)
            }
        }
    }

    private func finish(job: Job, plan: RasterPlan, images: [CGImage?]) {
        let output: RasterOutput = job.install(tileStore, plan, images)
        Task { @MainActor in job.then(output) }
        drain()
    }
}
