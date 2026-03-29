import Foundation

class TaskRunner {
    private var tasks: [BrowserTask] = []
    private let queue = DispatchQueue(label: "browser.tab.taskrunner")
    private var needsQuit = false

    func scheduleTask(_ task: BrowserTask) {
        queue.async {
            self.tasks.append(task)
            self.runNext()
        }
    }

    func clearPendingTasks() {
        queue.async {
            self.tasks.removeAll()
        }
    }

    func setNeedsQuit() {
        queue.async {
            self.needsQuit = true
            self.tasks.removeAll()
        }
    }

    private func runNext() {
        guard !needsQuit, !tasks.isEmpty else { return }
        let task = tasks.removeFirst()
        task.run()
    }
}
