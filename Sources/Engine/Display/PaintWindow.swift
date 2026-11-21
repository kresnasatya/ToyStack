import CoreGraphics

// MARK: - PaintWindow

struct PaintWindow: Equatable, Sendable {
    let top: CGFloat
    let bottom: CGFloat

    static let full: PaintWindow = PaintWindow(
        top: -.infinity,
        bottom: .infinity
    )

    func intersects(_ rect: Rect) -> Bool {
        return rect.bottom >= top && rect.top <= bottom
    }

    func intersects(_ ink: InkExtent) -> Bool {
        return ink.bottom >= top && ink.top <= bottom
    }
}
