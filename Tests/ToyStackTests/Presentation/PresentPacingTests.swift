import Foundation
import Testing

@testable import Engine

@Suite
struct PresentPacingTests {
    @Test func shortPresentWaitsOnlyTheRestOfTheFrame() {
        let delay: TimeInterval = PresentPacing.delay(lastStart: 10.0, now: 10.006)
        #expect(abs(delay - (PresentPacing.interval - 0.006)) < 1e-9)
    }

    @Test func presentLongerThanAFrameFollowsAtOnce() {
        let delay: TimeInterval = PresentPacing.delay(lastStart: 10.0, now: 10.020)
        #expect(delay == 0)
    }

    @Test func instantPresentWaitsAFullFrame() {
        let delay: TimeInterval = PresentPacing.delay(lastStart: 10.0, now: 10.0)
        #expect(abs(delay - PresentPacing.interval) < 1e-9)
    }
}
