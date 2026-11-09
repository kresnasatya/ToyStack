/// Single owner of a layout tree value.
///
/// The tree is a value, so something has to hold it. The frame owns the box;
/// the DOM keeps a weak reference so DOM-side code can resolve layout ids
/// without owning layout state.
final class LayoutBox {
    var tree: LayoutTree
    /// Edits marked on `tree` while a background pass lays out a copy of it.
    /// Nil when no pass runs.
    private var recordedEdits: [LayoutEdit]?

    init(_ tree: LayoutTree) {
        self.tree = tree
        self.recordedEdits = nil
    }

    /// Called when a background pass takes its copy of `tree`. Edits from an
    /// earlier pass that never installed are already in that copy.
    func startRecordingEdits() {
        recordedEdits = []
    }

    func record(_ edit: LayoutEdit) {
        recordedEdits?.append(edit)
    }

    /// Returns the edits made since the pass started and stops recording.
    func takeRecordedEdits() -> [LayoutEdit] {
        let edits: [LayoutEdit] = recordedEdits ?? []
        recordedEdits = nil
        return edits
    }
}
