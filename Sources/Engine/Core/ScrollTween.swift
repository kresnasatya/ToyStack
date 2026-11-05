import CoreGraphics
import Foundation

class ScrollTween {
    private var start: CGFloat
    private var target: CGFloat
    private let duration: TimeInterval
    private let easing: Easing
    private var startedAt: Date
    private var finished: Bool = false

    init(
        from start: CGFloat,
        to target: CGFloat,
        duration: TimeInterval = 0.2,
        easing: Easing = .easeOut,
        now: Date = Date()
    ) {
        self.start = start
        self.target = target
        self.duration = max(duration, 1.0 / 60.0)
        self.easing = easing
        self.startedAt = now
    }

    func aim(
        from current: CGFloat,
        by delta: CGFloat,
        within bounds: ClosedRange<CGFloat>,
        now: Date = Date()
    ) {
        start = current
        target = min(max(target + delta, bounds.lowerBound), bounds.upperBound)
        startedAt = now
        finished = false
    }

    func nextValue(now: Date = Date()) -> CGFloat? {
        if finished { return nil }
        let elapsed: TimeInterval = now.timeIntervalSince(startedAt)
        let t: Double = min(max(elapsed / duration, 0), 1)
        if t >= 1 {
            finished = true
        }
        let eased: Double = easing.apply(t)
        return start + (target - start) * CGFloat(eased)
    }
}
