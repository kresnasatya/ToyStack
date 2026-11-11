import Foundation

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
