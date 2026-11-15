import CoreGraphics

public struct ContentOffset: Equatable, Sendable {
    public let scroll: CGFloat

    public init(scroll: CGFloat) {
        self.scroll = scroll
    }

    public var origin: CGFloat { -scroll }

    /// The preview shrinks the content around the document origin, so the
    /// scroll shrinks too; the line at the top of the page area stays there.
    public func origin(previewScale scale: CGFloat) -> CGFloat {
        return -scroll * scale
    }

    public func devicePixelOrigin(previewScale scale: CGFloat, displayScale: CGFloat) -> CGFloat {
        let raw: CGFloat = origin(previewScale: scale)
        guard displayScale > 0, displayScale.isFinite else { return raw }
        return (raw * displayScale).rounded() / displayScale
    }
}
