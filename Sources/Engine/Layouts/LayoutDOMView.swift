import CoreGraphics
import Foundation

// MARK: - LayoutDOMView

/// Value view of one DOM node for layout.
///
/// Mirrors the small part of `DOMRef` layout reads, backed by `LayoutInputs`.
/// Mutating DOM (canvas context, iframe viewport) stays a main-actor call.
struct LayoutDOMView {
    let inputs: LayoutInputs
    let id: NodeID

    var style: LayoutStyleView { return LayoutStyleView(inputs: inputs, id: id) }
    var children: [LayoutDOMView] {
        return inputs.children(id).map({ LayoutDOMView(inputs: inputs, id: $0) })
    }

    var parent: LayoutDOMView? {
        guard let parent: NodeID = inputs.parent(id) else { return nil }
        return LayoutDOMView(inputs: inputs, id: parent)
    }

    var element: LayoutElementView? {
        guard inputs.tag(id) != nil else { return nil }
        return LayoutElementView(view: self)
    }

    var text: LayoutTextView? {
        guard let value: String = inputs.text(id) else { return nil }
        return LayoutTextView(view: self, text: value)
    }

    var ref: LayoutDOMView { return self }

    var inheritedStyleOwner: LayoutDOMView {
        return LayoutDOMView(inputs: inputs, id: inputs.inheritedStyleOwner(id))
    }

    var isFocused: Bool { return inputs.isFocused(id) }
    var isFocusVisible: Bool { return inputs.isFocusVisible(id) }
}

// MARK: - LayoutStyleView

struct LayoutStyleView {
    let inputs: LayoutInputs
    let id: NodeID

    var computed: ComputedStyle { return inputs.style(id) }
    var revision: UInt64 { return inputs.revision(id) }
}

// MARK: - LayoutElementView

struct LayoutElementView {
    let view: LayoutDOMView

    var id: NodeID { return view.id }
    var ref: LayoutDOMView { return view }
    var tag: String { return view.inputs.tag(view.id) ?? "" }
    var attributes: [String: String] { return view.inputs.attributes(view.id) }
    var isChecked: Bool { return view.inputs.isChecked(view.id) }
    var image: CGImage? { return view.inputs.image(view.id) }
    var children: [LayoutDOMView] { return view.children }
    var style: LayoutStyleView { return view.style }
    var isFocused: Bool { return view.inputs.isFocused(view.id) }
    var isFocusVisible: Bool { return view.inputs.isFocusVisible(view.id) }
}

// MARK: - LayoutTextView

struct LayoutTextView {
    let view: LayoutDOMView
    let text: String

    var ref: LayoutDOMView { return view }
}
