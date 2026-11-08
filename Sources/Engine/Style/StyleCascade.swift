import Foundation

// MARK: - StyleScope

struct StyleScope {
    let direct: Set<NodeID>

    var isEmpty: Bool { direct.isEmpty }

    func matches(_ node: DOMRef) -> Bool {
        direct.contains(node.id)
    }
}

// MARK: - StyleCascade

@MainActor
final class StyleCascade {
    let index: RuleIndex
    let media: MediaFeatures
    let scope: StyleScope?
    let ancestorKeys: AncestorSelectorKeys = AncestorSelectorKeys()
    private var prePass: PrePassStyles = PrePassStyles()
    private(set) var appliedNodes: [DOMRef] = []

    init(
        index: RuleIndex,
        media: MediaFeatures,
        scope: StyleScope?
    ) {
        self.index = index
        self.media = media
        self.scope = scope
    }

    func record(_ node: DOMRef, old: ComputedStyle) {
        appliedNodes.append(node)
        prePass.append(old)
    }

    func recordInherited(_ node: DOMRef, oldText: TextStyle) {
        appliedNodes.append(node)
        prePass.append(text: oldText)
    }

    func oldStyle(at index: Int) -> ComputedStyle {
        switch prePass[index] {
        case .full(let style):
            return style
        case .text(let text):
            var style: ComputedStyle = appliedNodes[index].style.computed
            style.text = text
            return style
        }
    }
}
