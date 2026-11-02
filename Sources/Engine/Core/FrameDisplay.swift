struct FrameDisplay {
    var displayList: [DisplayOp] = []
    var compositedUpdates: [NodeKey: EffectUpdate] = [:]
    var paintRevision: UInt = 0
    var effectRevision: UInt = 0
}
