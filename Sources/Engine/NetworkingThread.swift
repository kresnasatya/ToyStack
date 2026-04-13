import Foundation

class NetworkingThread: @unchecked Sendable {
    private var tasks: [NetworkTask] = []
    private let queue = DispatchQueue(
        label: "browser.networking",
        qos: .userInitiated
    )
    private var isRunning = false

    // Schedule a task on the networking thread.
    // Thread-safe: all mutations of `tasks` go through `queue`.
    func scheduleTask(_ task: NetworkTask) {
        queue.async {
            self.tasks.append(task)
            if !self.isRunning {
                self.isRunning = true
                self.runNext()
            }
        }
    }

    // Pick the next task and run it. Always called on `queue`.
    private func runNext() {
        guard let task = tasks.first else {
            isRunning = false
            return
        }
        tasks.removeFirst()

        // Spawn an async Task to run the (async) network work.
        // When done, hop back onto `queue` to start the next one.
        Task {
            await task.run()
            self.queue.async {
                self.runNext()
            }
        }
    }
}
