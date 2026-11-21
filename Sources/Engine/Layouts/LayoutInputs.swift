import CoreGraphics
import Foundation

// MARK: - LayoutInputs

/// Layout passes run over these values instead of reaching into the document,
/// so they no longer need a DOM reference to look at a tag, style, or font.
struct LayoutInputs {
    var nodes: [LayoutInput?]
    var styleChanges: [NodeID: Set<StyleProperty>] = [:]
    /// The document state these inputs were built from. Reusing them later only
    /// needs to rebuild what changed since this, whatever was built in between.
    var key: LayoutInputsKey? = nil

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
        let all: [NodeID] = allChildren(id)
        guard all.contains(where: { isDisplayNone($0) }) else { return all }
        return all.filter({ !isDisplayNone($0) })
    }

    /// Includes `display: none` children, which get no box but must still be
    /// watched so that showing one relays out its parent.
    func allChildren(_ id: NodeID) -> [NodeID] {
        return input(id)?.node.children ?? []
    }

    func isDisplayNone(_ id: NodeID) -> Bool {
        return input(id)?.style.computed.layout.display == LayoutStyle.Display.none
    }

    func hasBlockChild(_ id: NodeID) -> Bool {
        for child in children(id) where isInFlowBlock(child) {
            return true
        }
        return false
    }

    /// A float is block-level but leaves the flow: next to inline content it
    /// is placed with the lines, so it does not split them into blocks.
    func isInFlowBlock(_ id: NodeID) -> Bool {
        let layout: LayoutStyle = style(id).layout
        return layout.display == .block && layout.position.floating.side == .none
    }

    func isFloat(_ id: NodeID) -> Bool {
        let layout: LayoutStyle = style(id).layout
        return layout.display != .none && layout.position.floating.side != .none
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

/// Immutable and shared: a build copies one reference per node, and a node
/// that did not change keeps the same entry from build to build.
final class LayoutInput {
    let node: LayoutInputNode
    let content: LayoutInputContent
    let style: LayoutInputStyle
    let media: LayoutInputMedia

    init(
        node: LayoutInputNode,
        content: LayoutInputContent,
        style: LayoutInputStyle,
        media: LayoutInputMedia
    ) {
        self.node = node
        self.content = content
        self.style = style
        self.media = media
    }

    func restyled(_ style: LayoutInputStyle, forcedColors: Bool) -> LayoutInput {
        var media: LayoutInputMedia = self.media
        media.forcedColors = forcedColors
        return LayoutInput(node: node, content: content, style: style, media: media)
    }
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
