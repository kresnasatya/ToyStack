import Foundation

/// Tagged payload of one DOM node.
enum DOMKind {
    case element(ElementData)
    case text(DOMTextData)
}
