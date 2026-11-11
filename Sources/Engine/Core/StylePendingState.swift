import Foundation

struct StylePendingState {
    var needsHasPrecompute: Bool
    var counters: [String: Int]
    var byViewport: Bool
    var byOther: Bool

    init() {
        self.needsHasPrecompute = true
        self.counters = [:]
        self.byViewport = false
        self.byOther = false
    }
}
