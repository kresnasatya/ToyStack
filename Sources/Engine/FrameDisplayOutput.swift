struct FrameDisplayOutput {
    let displayList: [any DisplayItem]
    let compositedUpdates: [ObjectIdentifier: BrowserVisualEffect]?
    let paintRevision: UInt
}
