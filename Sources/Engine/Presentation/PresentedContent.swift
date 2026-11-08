import CoreGraphics

public struct RenderedContent: Sendable {
    public var placements: [LayerPlacement] = []
    public var image: CGImage?
    public var usesSublayers: Bool = false
    public var source: RenderedSource = RenderedSource()
}
