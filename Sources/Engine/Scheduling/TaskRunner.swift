import Foundation

class TaskRunner {
    private var highQueue: [BrowserTask] = []
    private var lowQueue: [BrowserTask] = []
    private var needsQuit: Bool = false

    private let starvationThreshold: TimeInterval = 0.1

    func scheduleTask(_ task: BrowserTask) {
        DispatchQueue.main.async {
            if task.priority == .high {
                self.highQueue.append(task)
            } else {
                self.lowQueue.append(task)
            }
            self.runNext()
        }
    }

    private func runNext() {
        guard !needsQuit else { return }

        let starved: Bool =
            lowQueue.first.map {
                Date().timeIntervalSince($0.enqueuedAt) > starvationThreshold
            } ?? false

        let task: BrowserTask
        if starved, let t = lowQueue.first {
            lowQueue.removeFirst()
            task = t
        } else if let t = highQueue.first {
            highQueue.removeFirst()
            task = t
        } else if let t = lowQueue.first {
            lowQueue.removeFirst()
            task = t
        } else {
            return
        }

        task.run()
    }
}
