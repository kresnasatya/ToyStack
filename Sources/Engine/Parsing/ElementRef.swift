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

    var attributes: [String: String] {
        get { element.attributes }
        set { element.attributes = newValue }
    }

    var isChecked: Bool {
        get { element.isChecked }
        set { element.isChecked = newValue }
    }

    var image: CGImage? {
        get { element.image }
        set { element.image = newValue }
    }

    var backgroundImage: CGImage? {
        get { element.backgroundImage }
        set { element.backgroundImage = newValue }
    }

    var backgroundImageSource: String? {
        get { element.backgroundImageSource }
        set { element.backgroundImageSource = newValue }
    }

    var frame: Frame? {
        get { element.frame }
        set { element.frame = newValue }
    }

    var frameSource: String? {
        get { element.frameSource }
        set { element.frameSource = newValue }
    }

    var canvasContext: CanvasRenderingContext2D? {
        get { element.canvasContext }
        set { element.canvasContext = newValue }
    }

    var scrollOffsetY: CGFloat {
        get { element.scrollOffsetY }
        set { element.scrollOffsetY = newValue }
    }
}
