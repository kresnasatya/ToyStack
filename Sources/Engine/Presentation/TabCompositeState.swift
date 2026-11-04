/// Layers produced by the last composite and the paint revision they came from.
struct TabCompositeState {
    var layers: [RasterLayer] = []
    /// `.max` until the first composite.
    var paintRevision: UInt = .max
}
