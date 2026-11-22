final class LayoutBox {
    var tree: LayoutTree
    private var recordedEdits: [LayoutEdit]?

    init(_ tree: LayoutTree) {
        self.tree = tree
        self.recordedEdits = nil
    }

    func startRecordingEdits() {
        recordedEdits = []
    }

    func record(_ edit: LayoutEdit) {
        recordedEdits?.append(edit)
    }

    func takeRecordedEdits() -> [LayoutEdit] {
        let edits: [LayoutEdit] = recordedEdits ?? []
        recordedEdits = nil
        return edits
    }
}
