/// Grouped frame state, owned by one `Frame`.
struct FrameState {
    var document: FrameDocumentState
    var layout: FrameLayoutState
}
