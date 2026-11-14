import Foundation
import Testing

@testable import Engine

/// Background layout used to write into whatever window the main thread had
/// open, so a main-thread `profile.paint` carried stray `layout.*` counts.
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

        let elsewhere: [String: ProfileMetric] = Self.onOtherThread {
            profiler.reset()
            profiler.count("test.elsewhere", by: 2)
            profiler.measure("test.timed", { () -> Void in })
            return profiler.snapshot()
        }

        #expect(elsewhere["test.elsewhere"]?.count == 2)
        #expect(elsewhere["test.timed"]?.count == 1)
        #expect(elsewhere["test.here"] == nil)
        #expect(profiler.snapshot()["test.here"]?.count == 3)
    }

    @Test func literalAndRuntimeNamesMergeInTheSnapshot() {
        let profiler: Profiler = Profiler(enabled: true)
        profiler.reset()
        profiler.count("test.merged", by: 2)
        let suffix: String = "merged"
        profiler.count(named: "test.\(suffix)", by: 5)

        #expect(profiler.snapshot()["test.merged"]?.count == 7)
    }

    @Test func spanRecordsTheTimeBetweenBeginAndEnd() {
        let profiler: Profiler = Profiler(enabled: true)
        profiler.reset()

        let span: ProfileSpan = profiler.begin("test.span")
        Thread.sleep(forTimeInterval: 0.002)
        profiler.end(span)

        let metric: ProfileMetric? = profiler.snapshot()["test.span"]
        #expect(metric?.count == 1)
        #expect((metric?.nanos ?? 0) >= 2_000_000, "the span lost the time it covered")
        #expect((metric?.nanos ?? .max) < 1_000_000_000, "the span recorded more than the time it covered")
    }

    @Test func disabledProfilerRecordsNoSpan() {
        let profiler: Profiler = Profiler(enabled: false)

        let span: ProfileSpan = profiler.begin("test.span")
        profiler.end(span)

        #expect(profiler.snapshot()["test.span"] == nil)
    }

    private static func onOtherThread<Result>(_ body: @escaping @Sendable () -> Result) -> Result {
        let box: ThreadResultBox<Result> = ThreadResultBox()
        let done: DispatchSemaphore = DispatchSemaphore(value: 0)
        let thread: Thread = Thread {
            box.value = body()
            done.signal()
        }
        thread.start()
        done.wait()
        guard let value: Result = box.value else {
            preconditionFailure("thread finished without a result")
        }
        return value
    }
}

// MARK: - ThreadResultBox

private final class ThreadResultBox<Value>: @unchecked Sendable {
    var value: Value?
}
