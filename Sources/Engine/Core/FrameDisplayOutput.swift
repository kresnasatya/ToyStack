struct FrameDisplayOutput {
    let displayList: [DisplayOp]
    let compositedUpdates: [NodeID: EffectUpdate]?
    let paintRevision: UInt
}
