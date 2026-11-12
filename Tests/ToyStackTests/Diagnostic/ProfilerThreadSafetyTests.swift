import Foundation
import Testing

@testable import Engine

private final class ProfilerBox: @unchecked Sendable {
    let profiler: Profiler = Profiler()
    private let lock: NSLock = NSLock()
    private var seen: [Int] = []

    func note(_ count: Int) {
        lock.lock()
        seen.append(count)
        lock.unlock()
    }

    var counts: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }
}

@Suite(.serialized)
struct ProfilerThreadSafetyTests {
    @Test func concurrentRecordsStayInTheirOwnThreadsWindow() {
        let box: ProfilerBox = ProfilerBox()
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            box.profiler.reset()
            for _ in 0..<100 {
                box.profiler.count("concurrent")
            }
            box.note(box.profiler.snapshot()["concurrent"]?.count ?? 0)
        }
        #expect(box.counts.count == 32)
        #expect(box.counts.allSatisfy({ $0 == 100 }))
    }
}
