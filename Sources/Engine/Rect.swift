import CoreGraphics

// MARK: - Rect
public struct Rect {
    public var left: CGFloat
    public var top: CGFloat
    public var right: CGFloat
    public var bottom: CGFloat

    public init(left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public func containsPoint(_ x: CGFloat, _ y: CGFloat) -> Bool {
        return x >= left && x < right && y >= top && y < bottom
    }

    var cgRect: CGRect {
        CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    init(cgRect: CGRect) {
        self.init(
            left: cgRect.minX,
            top: cgRect.minY,
            right: cgRect.maxX,
            bottom: cgRect.maxY
        )
    }

    func union(_ other: Rect) -> Rect {
        return Rect(
            left: min(self.left, other.left), top: min(self.top, other.top),
            right: max(self.right, other.right), bottom: max(self.bottom, other.bottom))
    }

    func intersects(_ other: Rect) -> Bool {
        return left < other.right && right > other.left
            && top < other.bottom && bottom > other.top
    }
}
