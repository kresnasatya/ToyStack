import CoreGraphics

struct Viewport: Sendable {
    let windowSize: CGSize
    let topInset: CGFloat
    let scale: ContentScale
    /// Colour space of the screen; bitmaps for the presenter are drawn in it.
    let colorSpace: CGColorSpace

    /// Target for bitmaps drawn at `scale` device pixels per point.
    func target(scale: CGFloat) -> RasterTarget {
        return RasterTarget(scale: scale, colorSpace: colorSpace)
    }
}
