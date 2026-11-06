import CoreGraphics
import Foundation

/// Decides whether a resize tick may lay out or must keep presenting the old
/// content. The policy is frame-driven and owns no timer, so a queued resize
/// event cannot postpone the layout indefinitely.
struct ResizePreviewPolicy {
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

    /// Starts or clears the preview window. A fast frame clears it, so the
    /// next tick lays out immediately.
    mutating func resize(now: Date, requiresPreview: Bool) {
        guard requiresPreview else {
            cancel()
            return
        }
        deadline = now.addingTimeInterval(delay)
    }

    /// True when this tick must present the old content at `size`.
    mutating func presentPreview(size: CGSize, now: Date) -> Bool {
        guard let deadline, now < deadline, presentedSize != size else {
            return false
        }
        presentedSize = size
        return true
    }

    /// True when layout may run. An expired preview is cleared first.
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
