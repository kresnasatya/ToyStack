import Foundation

class NetworkingThread: @unchecked Sendable {
    private var tasks: [NetworkTask] = []
    private let queue = DispatchQueue(
        label: "browser.networking",
        qos: .userInitiated
    )
    private var isRunning = false

    func schedule<T: Sendable>(name: String, _ work: @escaping () async -> T) async -> T {
        await withCheckedContinuation({ continuation in
            scheduleTask(
                NetworkTask(name: name) {
                    let result = await work()
                    continuation.resume(returning: result)
                })
        })
    }

    func scheduleTask(_ task: NetworkTask) {
        queue.async {
            self.tasks.append(task)
            if !self.isRunning {
                self.isRunning = true
                self.runNext()
            }
        }
    }

    private func runNext() {
        guard let task = tasks.first else {
            isRunning = false
            return
        }
        tasks.removeFirst()

        Task {
            await task.run()
            self.queue.async {
                self.runNext()
            }
        }
    }
}
