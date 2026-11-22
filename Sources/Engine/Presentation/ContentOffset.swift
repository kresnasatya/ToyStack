import CoreGraphics

public struct ContentOffset: Equatable, Sendable {
    public let scroll: CGFloat

    public init(scroll: CGFloat) {
        self.scroll = scroll
    }

    public var origin: CGFloat { -scroll }

    public func origin(previewScale scale: CGFloat) -> CGFloat {
        return -scroll * scale
    }

    public func devicePixelOrigin(previewScale scale: CGFloat, displayScale: CGFloat) -> CGFloat {
        let raw: CGFloat = origin(previewScale: scale)
        guard displayScale > 0, displayScale.isFinite else { return raw }
        return (raw * displayScale).rounded() / displayScale
    }
}
