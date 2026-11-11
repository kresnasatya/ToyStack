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
struct ThreadSafetyTests {
    @Test func fontCacheHandlesConcurrentLookups() {
        let missing: [String] = (0..<8).map { "missing-\($0)" }
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            let family: String = index.isMultiple(of: 2) ? "serif" : "monospace"
            let font: BrowserFont = getFont(
                size: 16 + index % 4,
                weight: index.isMultiple(of: 3) ? "bold" : "normal",
                style: index.isMultiple(of: 5) ? "italic" : "roman",
                family: family
            )
            _ = font.measure("thread-safe font cache")
            _ = missing[index % missing.count]
        }
        let first: BrowserFont = getFont(size: 16, weight: "normal", style: "roman")
        let second: BrowserFont = getFont(size: 16, weight: "normal", style: "roman")
        #expect(first.size == second.size)
    }

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
