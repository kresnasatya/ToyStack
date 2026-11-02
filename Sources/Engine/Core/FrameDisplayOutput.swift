struct FrameDisplayOutput {
    let displayList: [DisplayOp]
    let compositedUpdates: [ObjectIdentifier: BrowserVisualEffect]?
    let paintRevision: UInt
}
