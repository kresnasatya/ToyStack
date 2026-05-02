import Foundation

class RasterThread: @unchecked Sendable {
    private let queue = DispatchQueue(label: "browser.raster", qos: .userInitiated)

    private let lock = NSLock()
    private var pending: (@Sendable () -> Void)?
    private var draining = false

    func submit<T: Sendable>(
        _ work: @Sendable @escaping () -> T,
        then completion: @MainActor @escaping (T) -> Void
    ) {
        let job: @Sendable () -> Void = {
            let result = work()
            Task { @MainActor in completion(result) }
        }

        lock.lock()
        pending = job  // newest wins; any older pending is dropped
        let kick = !draining
        if kick { draining = true }
        lock.unlock()

        if kick {
            queue.async {
                self.drain()
            }
        }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let next = pending else {
                draining = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            next()
        }
    }
}
