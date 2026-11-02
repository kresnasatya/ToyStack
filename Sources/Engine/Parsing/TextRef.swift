import Foundation

/// Text-only view over a `DOMRef`.
@MainActor
struct TextRef {
    let ref: DOMRef
}

extension TextRef {
    var text: String {
        guard let text: DOMTextData = ref.dom.text(ref.id) else {
            preconditionFailure("TextRef points at an element")
        }
        return text.text
    }

    func setText(_ text: String) {
        ref.dom.setText(text, of: ref.id)
        LayoutInvalidation.textChanged(ref)
    }

    func append(_ suffix: String) {
        ref.dom.appendText(suffix, to: ref.id)
        LayoutInvalidation.textChanged(ref)
    }
}
