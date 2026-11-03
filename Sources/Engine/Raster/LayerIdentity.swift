import Foundation

/// Stable identity of a raster layer inside one composite.
public struct LayerIdentity: Sendable {
    var id: LayerID
    var firstCommandIndex: Int
    var ancestorChain: [EffectScope]
}
