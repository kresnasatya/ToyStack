import CoreGraphics

public struct RenderedContent {
    public var placements: [LayerPlacement] = []
    public var image: CGImage?
    public var regionTop: CGFloat = 0
    public var usesSublayers: Bool = false
}
