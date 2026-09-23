import Foundation

class NetworkTask {
    let name: String
    let enqueuedAt: Date
    private let work: () async -> Void

    init(name: String, _ work: @escaping () async -> Void) {
        self.name = name
        self.enqueuedAt = Date()
        self.work = work
    }

    func run() async {
        await work()
    }
}
