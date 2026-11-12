import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite
struct ScrollTweenTests {

    private let startDate: Date = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func progressesByElapsedTime() {
        let tween: ScrollTween = ScrollTween(
            from: 0,
            to: 100,
            duration: 0.2,
            now: startDate
        )

        let halfway: CGFloat = tween.nextValue(now: startDate.addingTimeInterval(0.1)) ?? -1
        let finished: CGFloat = tween.nextValue(now: startDate.addingTimeInterval(0.2)) ?? -1

        #expect(halfway > 50)
        #expect(halfway < 100)
        #expect(abs(finished - 100) < 0.001)
        #expect(tween.nextValue(now: startDate.addingTimeInterval(0.3)) == nil)
    }

    @Test func slowTickStillFinishesAtTarget() {
        let tween: ScrollTween = ScrollTween(
            from: 10,
            to: 60,
            duration: 0.2,
            now: startDate
        )

        let value: CGFloat = tween.nextValue(now: startDate.addingTimeInterval(1.0)) ?? -1

        #expect(abs(value - 60) < 0.001)
    }

    @Test func aimExtendsTargetAndRestartsTheClock() {
        let tween: ScrollTween = ScrollTween(
            from: 0,
            to: 100,
            duration: 0.2,
            now: startDate
        )
        _ = tween.nextValue(now: startDate.addingTimeInterval(0.1))

        tween.aim(
            from: 50,
            by: 100,
            within: 0...300,
            now: startDate.addingTimeInterval(0.1)
        )
        let value: CGFloat = tween.nextValue(now: startDate.addingTimeInterval(0.3)) ?? -1

        #expect(abs(value - 200) < 0.001)
    }

    @Test func aimClampsToBounds() {
        let tween: ScrollTween = ScrollTween(
            from: 0,
            to: 0,
            duration: 0.2,
            now: startDate
        )

        tween.aim(from: 0, by: 50, within: 0...30, now: startDate)
        let value: CGFloat = tween.nextValue(now: startDate.addingTimeInterval(0.2)) ?? -1

        #expect(abs(value - 30) < 0.001)
    }
}
