struct FrameDisplay {
    var displayList: [DisplayOp] = []
    var compositedUpdates: [ObjectIdentifier: BrowserVisualEffect] = [:]
    var paintRevision: UInt = 0
    var effectRevision: UInt = 0
}
