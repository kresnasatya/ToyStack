import Foundation

struct LayoutStats {
    var measureCalls: Int = 0
    var measureMisses: Int = 0
    var measureNanos: UInt64 = 0
    var fontRequests: Int = 0
    var words: Int = 0

    mutating func reset() {
        self = LayoutStats()
    }
}

nonisolated(unsafe) var layoutStats = LayoutStats()
