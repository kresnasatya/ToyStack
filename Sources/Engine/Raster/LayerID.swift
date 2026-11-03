import Foundation

struct LayerID: Hashable, Sendable {
    let effect: EffectScopeID?
    let ordinal: Int
}
