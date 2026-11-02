struct PaintSession {
    let paint: UInt
    let epoch: UInt
    let window: PaintWindow
    private var nextScope: Int = 0

    init(paint: UInt, epoch: UInt, window: PaintWindow) {
        self.paint = paint
        self.epoch = epoch
        self.window = window
    }

    mutating func makeScope(_ kind: EffectKind, node: NodeKey?, animatedTransform: Bool) -> EffectScope {
        defer { nextScope += 1 }
        return EffectScope(
            id: EffectScopeID(paint: paint, ordinal: nextScope),
            kind: kind,
            placement: EffectPlacement(
                rect: Rect(left: 0, top: 0, right: 0, bottom: 0),
                node: node,
                animatedTransform: animatedTransform
            )
        )
    }
}
