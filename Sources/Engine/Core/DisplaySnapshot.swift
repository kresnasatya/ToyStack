/// Frozen paint output and the minimum updates that can avoid a recomposite.
struct DisplaySnapshot: Sendable {
    let ops: [DisplayOp]
    let updates: [NodeID: EffectUpdate]?
    let revision: UInt
}
