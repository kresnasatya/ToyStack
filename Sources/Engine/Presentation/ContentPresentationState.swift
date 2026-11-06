import CoreGraphics

/// Decides whether a presented frame binds new content or only previews the
/// view size the content was laid out at.
///
/// Content and presentation are separate revisions. A resize presents the same
/// content several times at different sizes; those presents must preview from
/// the size at which the content was last bound. Repeated previews are
/// idempotent, so a tile update cannot overwrite the preview with a bind.
public struct ContentPresentationState {
    public enum Decision: Equatable {
        case bind
        case preview(from: CGSize)
    }

    /// The view size at which the current content was last bound.
    public private(set) var baseViewSize: CGSize?
    private var lastRevision: PresentedRevision?

    public init() {}

    public mutating func decide(
        revision: PresentedRevision,
        viewSize: CGSize,
        layoutSize: CGSize
    ) -> Decision {
        let contentWidth: CGFloat = layoutSize.width > 0
            ? layoutSize.width
            : viewSize.width
        if contentWidth != viewSize.width {
            lastRevision = revision
            return .preview(
                from: CGSize(width: contentWidth, height: viewSize.height)
            )
        }
        lastRevision = revision
        baseViewSize = viewSize
        return .bind
    }

    public mutating func decide(revision: PresentedRevision, viewSize: CGSize) -> Decision {
        let sameContent: Bool = lastRevision?.content == revision.content
        if sameContent, let baseViewSize, baseViewSize != viewSize {
            lastRevision = revision
            return .preview(from: baseViewSize)
        }
        lastRevision = revision
        baseViewSize = viewSize
        return .bind
    }
}
