struct DisplaySnapshot: Sendable {
    let ops: [DisplayOp]
    let updates: [NodeID: EffectUpdate]?
    let revision: UInt
}
