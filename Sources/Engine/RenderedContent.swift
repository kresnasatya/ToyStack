import CoreGraphics

public struct RenderedContent {
    public var placements: [PlacedLayer] = []
    public var image: CGImage?
    public var regionTop: CGFloat = 0
    public var usesSublayers: Bool = false
}
