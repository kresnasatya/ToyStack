public struct EffectScopeID: Hashable {
    let paint: UInt
    let ordinal: Int

    init(paint: UInt, ordinal: Int) {
        self.paint = paint
        self.ordinal = ordinal
    }
}
