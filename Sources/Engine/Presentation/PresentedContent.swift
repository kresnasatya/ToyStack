import CoreGraphics

public struct RenderedContent: Sendable {
    public var placements: [LayerPlacement] = []
    public var image: CGImage?
    public var regionTop: CGFloat = 0
    public var usesSublayers: Bool = false
}
