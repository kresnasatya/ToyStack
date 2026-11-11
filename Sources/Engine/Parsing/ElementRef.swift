import CoreGraphics
import Foundation

@MainActor
struct ElementRef {
    let ref: DOMRef
}

extension ElementRef {
    var id: NodeID { ref.id }

    var dom: DOMTree { ref.dom }

    var tag: String {
        guard let element: ElementData = dom.element(id) else {
            preconditionFailure("ElementRef points at a text node")
        }
        return element.tag
    }

    var style: StyleFields { ref.style }

    var children: [DOMRef] { ref.children }

    var isFocused: Bool {
        get { ref.isFocused }
        nonmutating set { dom.setFlag(\.isFocused, newValue, of: id) }
    }

    var isFocusVisible: Bool {
        get { ref.isFocusVisible }
        nonmutating set { dom.setFlag(\.isFocusVisible, newValue, of: id) }
    }

    var isHovered: Bool {
        get { ref.isHovered }
        nonmutating set { dom.setFlag(\.isHovered, newValue, of: id) }
    }

    var attributes: [String: String] {
        get { dom.attributes(of: id) ?? [:] }
        nonmutating set { dom.setAttributes(newValue, of: id) }
    }

    var isChecked: Bool {
        get { dom.isChecked(id) }
        nonmutating set { dom.setChecked(newValue, of: id) }
    }

    var image: CGImage? {
        get { dom.side.images.images[id] }
        nonmutating set {
            dom.side.images.images[id] = newValue
            dom.side.images.revision &+= 1
        }
    }

    var backgroundImage: CGImage? {
        get { dom.side.images.backgrounds[id] }
        nonmutating set { dom.side.images.backgrounds[id] = newValue }
    }

    var backgroundImageSource: String? {
        get { dom.side.images.backgroundSources[id] }
        nonmutating set { dom.side.images.backgroundSources[id] = newValue }
    }

    var frame: Frame? {
        get { dom.links.tab?.frame(dom.side.embeds.frames[id]) }
        nonmutating set { dom.side.embeds.frames[id] = newValue?.links.id }
    }

    var frameSource: String? {
        get { dom.side.embeds.frameSources[id] }
        nonmutating set { dom.side.embeds.frameSources[id] = newValue }
    }

    var canvasContext: CanvasRenderingContext2D? {
        get { dom.side.canvases.contexts[id] }
        nonmutating set { dom.side.canvases.contexts[id] = newValue }
    }

    var scrollOffsetY: CGFloat {
        get { dom.side.scrollOffsets[id] ?? 0 }
        nonmutating set { dom.side.scrollOffsets[id] = newValue }
    }
}
