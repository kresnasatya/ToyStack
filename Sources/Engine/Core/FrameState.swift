/// Grouped frame state, owned by one `Frame`.
///
/// `document` and `layout` hold main-actor arenas. `display` is a Sendable
/// value and is the only group that crosses to raster.
struct FrameState {
    var document: FrameDocumentState
    var layout: FrameLayoutState
    var display: FrameDisplayState
    var runtime: FrameRuntimeState
}
