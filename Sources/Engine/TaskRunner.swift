import Foundation

class TaskRunner {
    private var highQueue: [BrowserTask] = []
    private var lowQueue: [BrowserTask] = []
    private var needsQuit = false

    // Low-priority task waits at most 100ms before being force-run
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

    func clearPendingTasks() {
        DispatchQueue.main.async {
            self.highQueue.removeAll()
            self.lowQueue.removeAll()
        }
    }

    func setNeedsQuit() {
        DispatchQueue.main.async {
            self.needsQuit = true
            self.highQueue.removeAll()
            self.lowQueue.removeAll()
        }
    }

    private func runNext() {
        guard !needsQuit else { return }

        // Promote a low-priority task if it has waited too long.
        let starved =
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
