import Foundation
import Testing

@testable import Engine

@Suite
struct ResizeSettleTests {
    @Test func widthIsNotSettledRightAfterItChanges() {
        var settle: ResizeSettle = ResizeSettle()
        settle.note(width: 1000, at: 10.0)
        settle.note(width: 1020, at: 10.016)
        #expect(!settle.isSettled(at: 10.016 + ResizeSettle.delay / 2))
    }

    /// Repeated presents at the same width do not restart the wait; only a
    /// width change does.
    @Test func sameWidthKeepsTheTimeOfTheLastChange() {
        var settle: ResizeSettle = ResizeSettle()
        settle.note(width: 1000, at: 10.0)
        settle.note(width: 1000, at: 10.0 + ResizeSettle.delay / 2)
        #expect(settle.isSettled(at: 10.0 + ResizeSettle.delay * 1.5))
    }

    /// A drag sends a width change every display frame, so it never settles.
    @Test func dragAtDisplayRateNeverSettles() {
        var settle: ResizeSettle = ResizeSettle()
        var now: TimeInterval = 10.0
        for step in 0..<20 {
            settle.note(width: CGFloat(1000 + step * 20), at: now)
            #expect(!settle.isSettled(at: now))
            now += 1.0 / 60.0
        }
    }
}
