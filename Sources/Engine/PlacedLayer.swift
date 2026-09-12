import CoreGraphics

public struct PlacedLayer {
    public let image: CGImage
    public let frame: CGRect
    public let zIndex: Int
    public let effect: LayerEffect?

    public init(image: CGImage, frame: CGRect, zIndex: Int, effect: LayerEffect? = nil) {
        self.image = image
        self.frame = frame
        self.zIndex = zIndex
        self.effect = effect
    }
}
