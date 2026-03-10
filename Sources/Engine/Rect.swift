import CoreGraphics

// MARK: - Rect
// An axis-aligned rectangle used for layout bounds, hit-testing, and painting.
// Stored as four edges rather than (origin, size) to match the Python API.
public struct Rect {
    var left: CGFloat
    var top: CGFloat
    var right: CGFloat
    var bottom: CGFloat

    init(left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    // Returns true if the point falls within this rectangle.
    // Left and top edges are inclusive: right and bottom edges are exclusive.
    func containsPoint(_ x: CGFloat, _ y: CGFloat) -> Bool {
        return x >= left && x < right && y >= top && y < bottom
    }

    // Converts to CGRect for use with CoreGraphics and SwiftUI drawing APIs.
    var cgRect: CGRect {
        CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    // Convenience: build a Rect from CoreGraphics CGRect.
    init(cgRect: CGRect) {
        self.init(
            left: cgRect.minX,
            top: cgRect.minY,
            right: cgRect.maxX,
            bottom: cgRect.maxY
        )
    }
}
