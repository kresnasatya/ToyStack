import CoreGraphics
import Foundation

/// Element-only view over a `DOMRef`.
@MainActor
struct ElementRef {
    let ref: DOMRef
}

extension ElementRef {
    private var element: Element {
        guard let element: Element = ref.dom.node(ref.id) as? Element else {
            preconditionFailure("ElementRef points at a text node")
        }
        return element
    }

    var tag: String { element.tag }

    /// Temporary bridge to the class tree. Deleted in C3.
    var raw: Element { element }

    var style: StyleFields { element.style }

    var children: [DOMRef] { ref.children }

    var isFocused: Bool { element.isFocused }

    var isFocusVisible: Bool { element.isFocusVisible }

    var attributes: [String: String] {
        get { element.attributes }
        nonmutating set { element.attributes = newValue }
    }

    var isChecked: Bool {
        get { element.isChecked }
        nonmutating set { element.isChecked = newValue }
    }

    var image: CGImage? {
        get { element.image }
        nonmutating set { element.image = newValue }
    }

    var backgroundImage: CGImage? {
        get { element.backgroundImage }
        nonmutating set { element.backgroundImage = newValue }
    }

    var backgroundImageSource: String? {
        get { element.backgroundImageSource }
        nonmutating set { element.backgroundImageSource = newValue }
    }

    var frame: Frame? {
        get { element.frame }
        nonmutating set { element.frame = newValue }
    }

    var frameSource: String? {
        get { element.frameSource }
        nonmutating set { element.frameSource = newValue }
    }

    var canvasContext: CanvasRenderingContext2D? {
        get { element.canvasContext }
        nonmutating set { element.canvasContext = newValue }
    }

    var scrollOffsetY: CGFloat {
        get { element.scrollOffsetY }
        nonmutating set { element.scrollOffsetY = newValue }
    }
}
