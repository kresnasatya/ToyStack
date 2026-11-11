import CoreGraphics

/// The composite that produced a set of rendered layers. Both values are
/// captured when the composite starts, so a present that runs before the
/// composite returns still describes the layers it carries, not the newest
/// paint.
public struct RenderedSource: Equatable, Sendable {
    /// Identifies the compositor generation that produced these layers.
    /// A new generation must be bound as one complete frame; tiles from one
    /// generation may still arrive in later presents.
    public var generation: UInt64 = 0
    public var layoutSize: CGSize = .zero

    public init(generation: UInt64 = 0, layoutSize: CGSize = .zero) {
        self.generation = generation
        self.layoutSize = layoutSize
    }
}
