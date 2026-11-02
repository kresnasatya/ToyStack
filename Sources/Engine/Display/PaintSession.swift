struct PaintSession {
    let paint: UInt
    let epoch: UInt
    let window: PaintWindow
    private let scopes: PaintScopeAllocator

    init(paint: UInt, epoch: UInt, window: PaintWindow) {
        self.paint = paint
        self.epoch = epoch
        self.window = window
        self.scopes = PaintScopeAllocator()
    }

    private init(paint: UInt, epoch: UInt, window: PaintWindow, scopes: PaintScopeAllocator) {
        self.paint = paint
        self.epoch = epoch
        self.window = window
        self.scopes = scopes
    }

    func with(epoch: UInt, window: PaintWindow) -> PaintSession {
        PaintSession(paint: paint, epoch: epoch, window: window, scopes: scopes)
    }

    mutating func makeScope(_ kind: EffectKind, node: NodeKey?, animatedTransform: Bool) -> EffectScope {
        let ordinal: Int = scopes.next
        scopes.next += 1
        return EffectScope(
            id: EffectScopeID(paint: paint, ordinal: ordinal),
            kind: kind,
            placement: EffectPlacement(
                rect: Rect(left: 0, top: 0, right: 0, bottom: 0),
                node: node,
                animatedTransform: animatedTransform
            )
        )
    }
}

private final class PaintScopeAllocator {
    var next: Int = 0
}
