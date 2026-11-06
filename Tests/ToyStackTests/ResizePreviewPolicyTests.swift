import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite
struct ResizePreviewPolicyTests {

    private let start: Date = Date(timeIntervalSinceReferenceDate: 1000)
    private let initialSize: CGSize = CGSize(width: 800, height: 600)

    @Test func fastFrameLaysOutImmediately() {
        var policy: ResizePreviewPolicy = ResizePreviewPolicy()
        let now: Date = start

        policy.resize(now: now, requiresPreview: false)

        let presented: Bool = policy.presentPreview(size: initialSize, now: now)
        let allowed: Bool = policy.allowsLayout(now: now)
        #expect(presented == false)
        #expect(allowed)
    }

    @Test func slowFramePreviewsEachSizeOnlyOnce() {
        var policy: ResizePreviewPolicy = ResizePreviewPolicy()
        let now: Date = start
        policy.resize(now: now, requiresPreview: true)

        let first: Bool = policy.presentPreview(size: initialSize, now: now.addingTimeInterval(0.01))
        let repeated: Bool = policy.presentPreview(size: initialSize, now: now.addingTimeInterval(0.02))
        let resized: Bool = policy.presentPreview(
            size: CGSize(width: 820, height: 600),
            now: now.addingTimeInterval(0.03)
        )
        let allowed: Bool = policy.allowsLayout(now: now.addingTimeInterval(0.04))
        #expect(first)
        #expect(repeated == false)
        #expect(resized)
        #expect(allowed == false)
    }

    @Test func expiredPreviewAllowsLayoutOnce() {
        var policy: ResizePreviewPolicy = ResizePreviewPolicy(delay: 0.12)
        policy.resize(now: start, requiresPreview: true)

        let afterDeadline: Date = start.addingTimeInterval(0.12)
        let presented: Bool = policy.presentPreview(size: initialSize, now: afterDeadline)
        let firstLayout: Bool = policy.allowsLayout(now: afterDeadline)
        let secondLayout: Bool = policy.allowsLayout(now: afterDeadline.addingTimeInterval(1))
        #expect(presented == false)
        #expect(firstLayout)
        #expect(secondLayout)
    }

    @Test func continuingResizeExtendsThePreview() {
        var policy: ResizePreviewPolicy = ResizePreviewPolicy(delay: 0.12)
        policy.resize(now: start, requiresPreview: true)
        policy.resize(now: start.addingTimeInterval(0.10), requiresPreview: true)

        let beforeNewDeadline: Bool = policy.allowsLayout(now: start.addingTimeInterval(0.21))
        let afterNewDeadline: Bool = policy.allowsLayout(now: start.addingTimeInterval(0.22))
        #expect(beforeNewDeadline == false)
        #expect(afterNewDeadline)
    }

    @Test func fastFrameClearsAnActivePreview() {
        var policy: ResizePreviewPolicy = ResizePreviewPolicy()
        policy.resize(now: start, requiresPreview: true)

        policy.resize(now: start.addingTimeInterval(0.01), requiresPreview: false)

        let presented: Bool = policy.presentPreview(size: initialSize, now: start.addingTimeInterval(0.02))
        let allowed: Bool = policy.allowsLayout(now: start.addingTimeInterval(0.02))
        #expect(presented == false)
        #expect(allowed)
    }

    @Test func asyncLayoutRunsDuringPreview() {
        #expect(ResizePreviewPolicy.allowsLayoutDuringPreview(asyncLayout: true))
    }

    @Test func syncLayoutWaitsForPreviewDeadline() {
        #expect(!ResizePreviewPolicy.allowsLayoutDuringPreview(asyncLayout: false))
    }

    @Test func asyncLayoutAlwaysNeedsPreview() {
        #expect(
            ResizePreviewPolicy.shouldPreview(
                estimatedFrameTime: 0.001,
                frameBudget: 1.0 / 60.0,
                asyncLayout: true
            )
        )
    }

    @Test func fastSyncFrameDoesNotNeedPreview() {
        #expect(
            !ResizePreviewPolicy.shouldPreview(
                estimatedFrameTime: 0.001,
                frameBudget: 1.0 / 60.0,
                asyncLayout: false
            )
        )
    }

    @Test func cancelClearsPreviewAndPresentedSize() {
        var policy: ResizePreviewPolicy = ResizePreviewPolicy()
        policy.resize(now: start, requiresPreview: true)
        let presented: Bool = policy.presentPreview(size: initialSize, now: start.addingTimeInterval(0.01))
        #expect(presented)

        policy.cancel()

        let afterCancel: Bool = policy.presentPreview(size: initialSize, now: start.addingTimeInterval(0.02))
        let allowed: Bool = policy.allowsLayout(now: start.addingTimeInterval(0.02))
        #expect(afterCancel == false)
        #expect(allowed)
    }
}
