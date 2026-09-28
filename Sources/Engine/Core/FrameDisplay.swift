struct FrameDisplay {
    var displayList: [any DisplayItem] = []
    var compositedUpdates: [ObjectIdentifier: BrowserVisualEffect] = [:]
    var paintRevision: UInt = 0
    var effectRevision: UInt = 0
}
