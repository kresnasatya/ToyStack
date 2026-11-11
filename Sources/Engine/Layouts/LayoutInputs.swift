import CoreGraphics
import Foundation

// MARK: - LayoutInputs

/// Layout passes run over these values instead of reaching into the document,
/// so they no longer need a DOM reference to look at a tag, style, or font.
struct LayoutInputs {
    var nodes: [LayoutInput?]
    var styleChanges: [NodeID: Set<StyleProperty>] = [:]

    func input(_ id: NodeID) -> LayoutInput? {
        guard id.raw < nodes.count else { return nil }
        return nodes[Int(id.raw)]
    }

    func style(_ id: NodeID) -> ComputedStyle {
        guard let input = input(id) else {
            preconditionFailure("layout inputs missing node \(id.raw)")
        }
        return input.style.computed
    }

    func font(_ id: NodeID) -> TextStyle.Font {
        guard let input = input(id) else {
            preconditionFailure("layout inputs missing node \(id.raw)")
        }
        return input.style.font
    }

    func tag(_ id: NodeID) -> String? {
        return input(id)?.content.tag
    }

    func attributes(_ id: NodeID) -> [String: String] {
        return input(id)?.content.attributes ?? [:]
    }

    func text(_ id: NodeID) -> String? {
        return input(id)?.content.text
    }

    func children(_ id: NodeID) -> [NodeID] {
        return input(id)?.node.children ?? []
    }

    func parent(_ id: NodeID) -> NodeID? {
        return input(id)?.node.parent
    }

    func styleChanges(_ id: NodeID) -> Set<StyleProperty> {
        return styleChanges[id] ?? []
    }

    func isChecked(_ id: NodeID) -> Bool {
        return input(id)?.content.isChecked ?? false
    }

    func revision(_ id: NodeID) -> UInt64 {
        return input(id)?.style.revision ?? 0
    }

    func isFocused(_ id: NodeID) -> Bool {
        return input(id)?.node.isFocused ?? false
    }

    func isFocusVisible(_ id: NodeID) -> Bool {
        return input(id)?.node.isFocusVisible ?? false
    }

    func forcedColors(_ id: NodeID) -> Bool {
        return input(id)?.media.forcedColors ?? false
    }

    func image(_ id: NodeID) -> CGImage? {
        return input(id)?.media.image
    }

    func inheritedStyleOwner(_ id: NodeID) -> NodeID {
        if input(id)?.content.text != nil, let parent = parent(id) {
            return parent
        }
        return id
    }
}

// MARK: - LayoutInput

struct LayoutInput {
    var node: LayoutInputNode
    var content: LayoutInputContent
    var style: LayoutInputStyle
    var media: LayoutInputMedia
}

struct LayoutInputStyle {
    var computed: ComputedStyle
    var font: TextStyle.Font
    var revision: UInt64
}

struct LayoutInputMedia {
    var image: CGImage?
    var isIframe: Bool
    var isCanvas: Bool
    var forcedColors: Bool
}

struct LayoutInputNode {
    var parent: NodeID?
    var children: [NodeID]
    var isFocused: Bool
    var isFocusVisible: Bool
}

struct LayoutInputContent {
    var tag: String?
    var attributes: [String: String]
    var text: String?
    var isChecked: Bool
}
