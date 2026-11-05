import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutTreeTests {
    private func makeTree() -> LayoutTree {
        return LayoutTree(dom: DOMTree())
    }

    @Test func appendGivesUniqueMonotonicIDs() {
        var tree: LayoutTree = makeTree()
        let first: LayoutID = tree.append(
            kind: .block(BlockData()),
            dom: tree.dom.root,
            parent: nil,
            previous: nil
        )
        let second: LayoutID = tree.append(
            kind: .block(BlockData()),
            dom: tree.dom.root,
            parent: nil,
            previous: nil
        )

        #expect(first.raw == 1)
        #expect(second.raw == 2)
        #expect(first != second)
        #expect(tree.primaryLayout(for: tree.dom.root)?.raw == 0)
    }

    @Test func removeSubtreeLeavesAHoleThatIsNeverReused() {
        var tree: LayoutTree = makeTree()
        let parent: LayoutID = tree.append(
            kind: .block(BlockData()),
            dom: tree.dom.root,
            parent: nil,
            previous: nil
        )
        let child: LayoutID = tree.append(
            kind: .text(TextData(payload: TextPayload(word: "hello", display: nil, fontOverride: nil), fragment: nil, metrics: TextMetrics(width: 0, whiteSpace: .normal))),
            dom: tree.dom.root,
            parent: parent,
            previous: nil
        )
        tree.setChildren([child], of: parent)

        tree.removeSubtree(parent)

        #expect(tree.nodes[parent.raw] == nil)
        #expect(tree.nodes[child.raw] == nil)

        let next: LayoutID = tree.append(
            kind: .block(BlockData()),
            dom: tree.dom.root,
            parent: nil,
            previous: nil
        )
        #expect(next.raw > child.raw)
    }

    @Test func setChildrenUpdatesParentsAndBumpsTheLinkVersion() {
        var tree: LayoutTree = makeTree()
        let parent: LayoutID = tree.append(
            kind: .block(BlockData()),
            dom: tree.dom.root,
            parent: nil,
            previous: nil
        )
        let first: LayoutID = tree.append(
            kind: .line(LineData()),
            dom: tree.dom.root,
            parent: parent,
            previous: nil
        )
        let second: LayoutID = tree.append(
            kind: .line(LineData()),
            dom: tree.dom.root,
            parent: parent,
            previous: nil
        )

        tree.setChildren([first], of: parent)
        #expect(tree.node(first).links.parent == parent)
        #expect(tree.node(parent).links.versions.children == 1)

        tree.setChildren([first, second], of: parent)
        #expect(tree.node(second).links.parent == parent)
        #expect(tree.children(of: parent) == [first, second])
        #expect(tree.node(parent).links.versions.children == 2)
    }
}
