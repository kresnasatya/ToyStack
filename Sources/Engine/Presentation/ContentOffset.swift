import CoreGraphics

public struct ContentOffset: Equatable, Sendable {
    public let top: CGFloat
    public let scroll: CGFloat

    public init(top: CGFloat, scroll: CGFloat) {
        self.top = top
        self.scroll = scroll
    }

    public var origin: CGFloat { top - scroll }

    /// The preview shrinks the content around the document origin, so the
    /// scroll shrinks too; the line at the top of the page area stays there.
    public func origin(previewScale scale: CGFloat) -> CGFloat {
        return top - scroll * scale
    }
}
