import CoreGraphics

public struct EffectScope {
    let id: EffectScopeID
    let kind: EffectKind
    let placement: EffectPlacement

    init(id: EffectScopeID, kind: EffectKind, placement: EffectPlacement) {
        self.id = id
        self.kind = kind
        self.placement = placement
    }
}

// MARK: - EffectPlacement

public struct EffectPlacement {
    let rect: Rect
    let node: NodeKey?
    let animatedTransform: Bool

    init(rect: Rect, node: NodeKey?, animatedTransform: Bool) {
        self.rect = rect
        self.node = node
        self.animatedTransform = animatedTransform
    }
}
