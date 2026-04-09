import Foundation

class TaskRunner {
    private var tasks: [BrowserTask] = []
    private var needsQuit = false

    func scheduleTask(_ task: BrowserTask) {
        DispatchQueue.main.async {
            self.tasks.append(task)
            self.runNext()
        }
    }

    func clearPendingTasks() {
        DispatchQueue.main.async {
            self.tasks.removeAll()
        }
    }

    func setNeedsQuit() {
        DispatchQueue.main.async {
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
