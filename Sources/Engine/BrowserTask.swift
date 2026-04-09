class BrowserTask {
    private let name: String
    private weak var measure: MeasureTime?
    private let work: () -> Void

    init(name: String, measure: MeasureTime? = nil, _ work: @escaping () -> Void) {
        self.name = name
        self.measure = measure
        self.work = work
    }

    func run() {
        measure?.start(name)
        work()
        measure?.stop(name)
    }
}
