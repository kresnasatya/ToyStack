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

    func placed(rect: Rect) -> EffectScope {
        EffectScope(
            id: id,
            kind: kind,
            placement: EffectPlacement(
                rect: rect,
                node: placement.node,
                animatedTransform: placement.animatedTransform
            )
        )
    }
}

// MARK: - EffectPlacement

public struct EffectPlacement {
    let rect: Rect
    let node: NodeID?
    let animatedTransform: Bool

    init(rect: Rect, node: NodeID?, animatedTransform: Bool) {
        self.rect = rect
        self.node = node
        self.animatedTransform = animatedTransform
    }
}
