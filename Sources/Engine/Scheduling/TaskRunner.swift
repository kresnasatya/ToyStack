import Foundation

class TaskRunner {
    private var highQueue: [BrowserTask] = []
    private var lowQueue: [BrowserTask] = []
    private var needsQuit: Bool = false

    private static let lowPriorityMaxWait: TimeInterval = 0.1

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

        let lowPriorityWaitedTooLong: Bool =
            lowQueue.first.map {
                Self.hasWaitedTooLong(enqueuedAt: $0.enqueuedAt, now: Date())
            } ?? false

        let task: BrowserTask
        if lowPriorityWaitedTooLong, let t = lowQueue.first {
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

    static func hasWaitedTooLong(enqueuedAt: Date, now: Date) -> Bool {
        return now.timeIntervalSince(enqueuedAt) > lowPriorityMaxWait
    }
}
