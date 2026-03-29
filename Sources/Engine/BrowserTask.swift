class BrowserTask {
    private let work: () -> Void

    init(_ work: @escaping () -> Void) {
        self.work = work
    }

    func run() {
        work()
    }
}
