public struct EffectScopeID: Hashable, Sendable {
    let paint: UInt
    let ordinal: Int

    init(paint: UInt, ordinal: Int) {
        self.paint = paint
        self.ordinal = ordinal
    }
}
