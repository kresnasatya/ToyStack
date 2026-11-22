import CoreGraphics

public struct RasterTarget: Sendable {
    public static let sRGB: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public let scale: CGFloat
    public let colorSpace: CGColorSpace

    public init(scale: CGFloat, colorSpace: CGColorSpace = RasterTarget.sRGB) {
        self.scale = scale
        self.colorSpace = colorSpace
    }
}
