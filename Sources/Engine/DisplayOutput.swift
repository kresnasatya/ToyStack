struct DisplayOutput {
    let displayList: [any DisplayItem]
    let compositedUpdates: [ObjectIdentifier: BrowserVisualEffect]?
    let paintEpoch: UInt
}
