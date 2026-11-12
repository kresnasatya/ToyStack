import Foundation
import Testing

@testable import Engine

@Suite
struct TaskRunnerTests {
    private let now: Date = Date(timeIntervalSinceReferenceDate: 0)

    @Test func lowPriorityTaskUnderTheLimitKeepsWaiting() {
        let enqueuedAt: Date = now.addingTimeInterval(-0.099)
        #expect(!TaskRunner.hasWaitedTooLong(enqueuedAt: enqueuedAt, now: now))
    }

    @Test func lowPriorityTaskExactlyAtTheLimitKeepsWaiting() {
        let enqueuedAt: Date = now.addingTimeInterval(-0.1)
        #expect(!TaskRunner.hasWaitedTooLong(enqueuedAt: enqueuedAt, now: now))
    }

    @Test func lowPriorityTaskPastTheLimitRunsFirst() {
        let enqueuedAt: Date = now.addingTimeInterval(-0.101)
        #expect(TaskRunner.hasWaitedTooLong(enqueuedAt: enqueuedAt, now: now))
    }

    @Test func clockMovingBackwardsDoesNotForceALowPriorityTask() {
        let enqueuedAt: Date = now.addingTimeInterval(5)
        #expect(!TaskRunner.hasWaitedTooLong(enqueuedAt: enqueuedAt, now: now))
    }
}
