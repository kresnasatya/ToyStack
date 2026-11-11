import CoreGraphics

struct Viewport: Sendable {
    let windowSize: CGSize
    let topInset: CGFloat
    let scale: ContentScale
    let colorSpace: CGColorSpace

    func target(scale: CGFloat) -> RasterTarget {
        return RasterTarget(scale: scale, colorSpace: colorSpace)
    }
}
