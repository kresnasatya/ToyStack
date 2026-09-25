import Foundation

enum TaskPriority {
    case high  // render, input handling
    case low  // setTimeout, setInterval
}

class BrowserTask {
    private let name: String
    let priority: TaskPriority
    let enqueuedAt: Date
    private weak var measure: MeasureTime?
    private let work: () -> Void

    init(
        name: String, priority: TaskPriority = .high, measure: MeasureTime? = nil,
        _ work: @escaping () -> Void
    ) {
        self.name = name
        self.priority = priority
        self.enqueuedAt = Date()
        self.measure = measure
        self.work = work
    }

    func run() {
        measure?.start(name)
        work()
        measure?.stop(name)
    }
}
