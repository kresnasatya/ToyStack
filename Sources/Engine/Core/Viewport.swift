import CoreGraphics

struct Viewport: Sendable {
    let windowSize: CGSize
    let topInset: CGFloat
    let scale: ContentScale
}
