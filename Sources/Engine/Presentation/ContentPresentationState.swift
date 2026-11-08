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
    /// Width, in view pixels, of the layout whose layers are on screen. A
    /// bound frame can still be staging behind older layers, so this can lag
    /// the last bind.
    public private(set) var shownContentWidth: CGFloat?
    private var lastRevision: PresentedRevision?

    public init() {}

    /// `stagingLayers` is true while a new layer generation uploads behind
    /// the layers on screen; those layers stay visible until it completes.
    public mutating func decide(
        revision: PresentedRevision,
        viewSize: CGSize,
        layoutSize: CGSize,
        stagingLayers: Bool
    ) -> Decision {
        if !Self.fitsView(layoutSize: layoutSize, viewSize: viewSize) {
            let contentWidth: CGFloat = Self.contentWidth(layoutSize: layoutSize, viewSize: viewSize)
            lastRevision = revision
            // The preview scales the layers on screen, not this unbound
            // layout, so it must start from the width those layers were laid
            // out at.
            let shownWidth: CGFloat = shownContentWidth ?? contentWidth
            return .preview(
                from: CGSize(width: shownWidth, height: viewSize.height)
            )
        }
        // This layout fits, but until its layers finish staging the older
        // layers stay on screen. Scale them to the view instead of showing
        // them at their own width next to an empty strip. Without staging
        // nothing would replace them, so the frame binds.
        if stagingLayers, let shownWidth: CGFloat = shownContentWidth, shownWidth != viewSize.width {
            lastRevision = revision
            return .preview(
                from: CGSize(width: shownWidth, height: viewSize.height)
            )
        }
        lastRevision = revision
        baseViewSize = viewSize
        return .bind
    }

    /// Records that the layers laid out at `layoutSize` are now on screen.
    public mutating func didShow(layoutSize: CGSize, viewSize: CGSize) {
        shownContentWidth = Self.contentWidth(layoutSize: layoutSize, viewSize: viewSize)
    }

    /// True when content laid out at `layoutSize` fills the view at its own
    /// width, so it can be bound instead of previewed.
    public static func fitsView(layoutSize: CGSize, viewSize: CGSize) -> Bool {
        return contentWidth(layoutSize: layoutSize, viewSize: viewSize) == viewSize.width
    }

    private static func contentWidth(layoutSize: CGSize, viewSize: CGSize) -> CGFloat {
        return layoutSize.width > 0 ? layoutSize.width : viewSize.width
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
