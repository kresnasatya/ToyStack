import CoreGraphics

public struct RenderedSource: Equatable, Sendable {
    public var generation: UInt64 = 0
    public var layoutSize: CGSize = .zero

    public init(generation: UInt64 = 0, layoutSize: CGSize = .zero) {
        self.generation = generation
        self.layoutSize = layoutSize
    }
}
