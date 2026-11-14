import CoreGraphics

public struct ShownLayer {
    public let image: AnyObject?
    public let frame: CGRect
    public let scale: CGFloat
    public let isVisibleWithoutEffect: Bool

    public init(image: AnyObject?, frame: CGRect, scale: CGFloat, isVisibleWithoutEffect: Bool) {
        self.image = image
        self.frame = frame
        self.scale = scale
        self.isVisibleWithoutEffect = isVisibleWithoutEffect
    }

    public func canStay(for placed: LayerPlacement, scale stagedScale: CGFloat) -> Bool {
        guard isVisibleWithoutEffect, placed.effect == nil, let image else { return false }
        return image === placed.image && frame == placed.frame && scale == stagedScale
    }
}
