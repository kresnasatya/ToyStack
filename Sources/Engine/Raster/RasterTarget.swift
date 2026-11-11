import CoreGraphics

/// Core Animation converts a bitmap in another colour space one pixel at a
/// time while it commits, on the presenter's thread: ~0.42 ms per 256 × 256
/// tile. Drawing in the screen's colour space moves that work to raster time,
/// where fills and text are converted once per drawing command.
public struct RasterTarget: Sendable {
    public static let sRGB: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public let scale: CGFloat
    public let colorSpace: CGColorSpace

    public init(scale: CGFloat, colorSpace: CGColorSpace = RasterTarget.sRGB) {
        self.scale = scale
        self.colorSpace = colorSpace
    }
}
