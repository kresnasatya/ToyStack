import CoreGraphics

public struct RenderedContent: Sendable {
    public var placements: [LayerPlacement] = []
    public var image: CGImage?
    public var usesSublayers: Bool = false
    /// Identifies the compositor generation that produced these layers.
    /// A new generation must be bound as one complete frame; tiles from one
    /// generation may still arrive in later presents.
    public var generation: UInt64 = 0
}
