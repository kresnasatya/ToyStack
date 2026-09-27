import CoreGraphics

public struct LayerPlacement {
    public let key: LayerPlacementKey
    public let image: CGImage
    public let frame: CGRect
    public let effect: LayerEffect?

    public init(key: LayerPlacementKey, image: CGImage, frame: CGRect, effect: LayerEffect? = nil) {
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
