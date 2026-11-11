import Foundation

struct DOMNode {
    var kind: DOMKind
    var base: DOMBase
}

extension DOMNode {
    var element: ElementData? {
        guard case .element(let data) = kind else { return nil }
        return data
    }

    var text: DOMTextData? {
        guard case .text(let data) = kind else { return nil }
        return data
    }

    var tag: String? { element?.tag }
}
