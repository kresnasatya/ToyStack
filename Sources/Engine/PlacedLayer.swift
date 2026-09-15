import CoreGraphics

public struct PlacedLayer {
    public let key: PlacedLayerKey
    public let image: CGImage
    public let frame: CGRect
    public let effect: LayerEffect?

    public init(key: PlacedLayerKey, image: CGImage, frame: CGRect, effect: LayerEffect? = nil) {
        self.key = key
        self.image = image
        self.frame = frame
        self.effect = effect
    }

    public var zIndex: Int {
        switch key {
            case .tile(let zIndex, _, _): return zIndex
            case .composited(let zIndex): return zIndex
        }
    }
}
