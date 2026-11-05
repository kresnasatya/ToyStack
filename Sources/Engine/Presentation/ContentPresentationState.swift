import CoreGraphics

/// Decides whether a presented frame binds new content or only previews the
/// previous view size.
///
/// The resize path presents the old content once to rebind it, then presents
/// again with the new view size. The second present must scale from the size
/// used by the first, so the last view size is updated on both bind and
/// preview. This mirrors the two-phase behavior that keeps text from being
/// scaled directly from the pre-drag size.
public struct ContentPresentationState {
    public enum Decision: Equatable {
        case bind
        case preview(from: CGSize)
    }

    public private(set) var lastViewSize: CGSize?
    private var lastRevision: Int?

    public init() {}

    public mutating func decide(revision: Int, viewSize: CGSize) -> Decision {
        let decision: Decision
        if let lastViewSize, lastRevision == revision, lastViewSize != viewSize {
            decision = .preview(from: lastViewSize)
        } else {
            decision = .bind
        }
        lastRevision = revision
        lastViewSize = viewSize
        return decision
    }
}
