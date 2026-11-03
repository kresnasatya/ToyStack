import CoreGraphics
import Foundation

// MARK: - LayoutInputs

/// Frozen DOM facts layout reads, keyed by DOM node id.
///
/// Layout passes run over these values instead of reaching into the document,
/// so they no longer need a DOM reference to look at a tag, style, or font.
struct LayoutInputs {
    var nodes: [LayoutInput?]

    func input(_ id: NodeID) -> LayoutInput? {
        guard id.raw < nodes.count else { return nil }
        return nodes[Int(id.raw)]
    }

    func style(_ id: NodeID) -> ComputedStyle {
        guard let input = input(id) else {
            preconditionFailure("layout inputs missing node \(id.raw)")
        }
        return input.style
    }

    func font(_ id: NodeID) -> TextStyle.Font {
        guard let input = input(id) else {
            preconditionFailure("layout inputs missing node \(id.raw)")
        }
        return input.font
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
        return input(id)?.identity.children ?? []
    }

    func parent(_ id: NodeID) -> NodeID? {
        return input(id)?.identity.parent
    }

    func isChecked(_ id: NodeID) -> Bool {
        return input(id)?.isChecked ?? false
    }
}

// MARK: - LayoutInput

struct LayoutInput {
    var identity: LayoutInputIdentity
    var content: LayoutInputContent
    var style: ComputedStyle
    var font: TextStyle.Font
    var isChecked: Bool
}

struct LayoutInputIdentity {
    var parent: NodeID?
    var children: [NodeID]
}

struct LayoutInputContent {
    var tag: String?
    var attributes: [String: String]
    var text: String?
}
