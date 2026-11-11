import Foundation

public struct LayerIdentity: Sendable {
    var id: LayerID
    var firstCommandIndex: Int
    var ancestorChain: [EffectScope]
}
