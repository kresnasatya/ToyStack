import CoreGraphics
import Foundation

/// The policy is frame-driven and owns no timer, so a queued resize event
/// cannot postpone the layout indefinitely.
struct ResizePreviewPolicy {
    static func allowsLayoutDuringPreview(asyncLayout: Bool) -> Bool {
        return asyncLayout
    }

    static func shouldPreview(
        estimatedFrameTime: TimeInterval,
        frameBudget: TimeInterval,
        asyncLayout: Bool
    ) -> Bool {
        return asyncLayout || estimatedFrameTime > frameBudget * 2.0
    }

    private let delay: TimeInterval
    private var deadline: Date?
    private var presentedSize: CGSize?

    init(delay: TimeInterval = 0.12) {
        self.delay = delay
    }

    mutating func resize(now: Date, requiresPreview: Bool) {
        guard requiresPreview else {
            cancel()
            return
        }
        deadline = now.addingTimeInterval(delay)
    }

    mutating func presentPreview(size: CGSize, now: Date) -> Bool {
        guard let deadline, now < deadline, presentedSize != size else {
            return false
        }
        presentedSize = size
        return true
    }

    mutating func allowsLayout(now: Date) -> Bool {
        guard let deadline else { return true }
        guard now >= deadline else { return false }
        self.deadline = nil
        presentedSize = nil
        return true
    }

    mutating func cancel() {
        deadline = nil
        presentedSize = nil
    }
}
