import CoreGraphics

public struct ContentPresentationState {
    public enum Decision: Equatable {
        case bind
        case preview(from: CGSize)
    }

    public private(set) var baseViewSize: CGSize?
    public private(set) var shownContentWidth: CGFloat?
    public private(set) var shownPage: CGFloat?
    private var lastRevision: PresentedRevision?

    public init() {}

    public mutating func decide(
        revision: PresentedRevision,
        viewSize: CGSize,
        layoutSize: CGSize,
        stagingLayers: Bool
    ) -> Decision {
        if !Self.fitsView(layoutSize: layoutSize, viewSize: viewSize) {
            let contentWidth: CGFloat = Self.contentWidth(layoutSize: layoutSize, viewSize: viewSize)
            lastRevision = revision
            let shownWidth: CGFloat = shownContentWidth ?? contentWidth
            return .preview(
                from: CGSize(width: shownWidth, height: viewSize.height)
            )
        }
        if stagingLayers, let shownWidth: CGFloat = shownContentWidth, !Self.sameWidth(shownWidth, viewSize.width) {
            lastRevision = revision
            return .preview(
                from: CGSize(width: shownWidth, height: viewSize.height)
            )
        }
        lastRevision = revision
        baseViewSize = viewSize
        return .bind
    }

    public mutating func didShow(layoutSize: CGSize, viewSize: CGSize, page: CGFloat) {
        shownContentWidth = Self.contentWidth(layoutSize: layoutSize, viewSize: viewSize)
        shownPage = page
    }

    public func layerPage(framePage: CGFloat, showsOlderLayers: Bool) -> CGFloat {
        guard showsOlderLayers, let shownPage else { return framePage }
        return shownPage
    }

    public static func fitsView(layoutSize: CGSize, viewSize: CGSize) -> Bool {
        return sameWidth(contentWidth(layoutSize: layoutSize, viewSize: viewSize), viewSize.width)
    }

    public static func stages(generation: UInt64, shown: UInt64?) -> Bool {
        guard let shown else { return false }
        return generation != shown
    }

    private static func sameWidth(_ a: CGFloat, _ b: CGFloat) -> Bool {
        return abs(a - b) < 0.5
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
