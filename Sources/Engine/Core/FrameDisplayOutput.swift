struct FrameDisplayOutput {
    let displayList: [DisplayOp]
    let compositedUpdates: [NodeKey: EffectUpdate]?
    let paintRevision: UInt
}
