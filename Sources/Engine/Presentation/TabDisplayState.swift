struct TabDisplayState {
    var displayList: [DisplayOp] = []
    var compositedUpdates: [NodeID: EffectUpdate] = [:]
    var paintRevision: UInt = 0
    var effectRevision: UInt = 0
}
