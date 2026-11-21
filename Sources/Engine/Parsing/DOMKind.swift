import Foundation

enum DOMKind {
    case element(ElementData)
    case text(DOMTextData)
    case comment(DOMCommentData)
}
