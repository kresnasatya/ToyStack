import Foundation

/// Everything the document itself owns: metadata, the DOM arena, style sheets,
/// and loaded resources.
struct FrameDocumentState {
    var meta: DocumentMeta
    var dom: DOMTree
    var sheets: StylesheetState
    var resources: ResourceState

    init(dom: DOMTree) {
        self.meta = DocumentMeta()
        self.dom = dom
        self.sheets = StylesheetState()
        self.resources = ResourceState()
    }
}
