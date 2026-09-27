struct FrameDisplay {
    var displayList: [any DisplayItem] = []
    var compositedUpdates: [ObjectIdentifier: BrowserVisualEffect] = [:]
    var paintEpoch: UInt = 0
    var effectUpdateEpoch: UInt = 0
}
