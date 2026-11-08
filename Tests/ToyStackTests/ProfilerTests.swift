import Foundation
import Testing

@testable import Engine

/// Each thread records into its own window. Background layout used to write
/// into whatever window the main thread had open, so a main-thread
/// `profile.paint` carried stray `layout.*` counts.
@Suite
struct ProfilerTests {
    @Test func countsFromAnotherThreadStayOutOfThisWindow() {
        let profiler: Profiler = Profiler(enabled: true)
        profiler.reset()
        profiler.count("test.here")

        Self.onOtherThread {
            profiler.count("test.elsewhere")
        }

        let here: [String: ProfileMetric] = profiler.snapshot()
        #expect(here["test.here"]?.count == 1)
        #expect(here["test.elsewhere"] == nil, "another thread's count reached this window")
    }

    @Test func otherThreadSeesOnlyItsOwnCounts() {
        let profiler: Profiler = Profiler(enabled: true)
        profiler.reset()
        profiler.count("test.here", by: 3)

        var elsewhere: [String: ProfileMetric] = [:]
        Self.onOtherThread {
            profiler.reset()
            profiler.count("test.elsewhere", by: 2)
            profiler.measure("test.timed", { () -> Void in })
            elsewhere = profiler.snapshot()
        }

        #expect(elsewhere["test.elsewhere"]?.count == 2)
        #expect(elsewhere["test.timed"]?.count == 1)
        #expect(elsewhere["test.here"] == nil)
        // Resetting the other thread's window leaves this one alone.
        #expect(profiler.snapshot()["test.here"]?.count == 3)
    }

    /// A name counted as a literal and as a runtime string is one metric.
    @Test func literalAndRuntimeNamesMergeInTheSnapshot() {
        let profiler: Profiler = Profiler(enabled: true)
        profiler.reset()
        profiler.count("test.merged", by: 2)
        let suffix: String = "merged"
        profiler.count(named: "test.\(suffix)", by: 5)

        #expect(profiler.snapshot()["test.merged"]?.count == 7)
    }

    /// Runs `body` on a separate thread and waits for it.
    private static func onOtherThread(_ body: @escaping () -> Void) {
        let done: DispatchSemaphore = DispatchSemaphore(value: 0)
        let thread: Thread = Thread {
            body()
            done.signal()
        }
        thread.start()
        done.wait()
    }
}
