import Foundation

/// Stable identity of a raster layer inside one composite.
public struct LayerIdentity {
    var id: LayerID
    var firstCommandIndex: Int
    var ancestorChain: [EffectScope]
}
