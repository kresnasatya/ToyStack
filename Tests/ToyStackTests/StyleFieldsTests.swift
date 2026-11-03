import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct StyleFieldsTests {

    @Test func sameValueDoesNotMark() {
        var (style, tree, block) = makeStyleFixture()
        style.apply(["width": "10px"])
        consumeStyle(&tree)
        tree.setFieldClean(.width, 10, for: block)

        style.set(.length(10), for: .width)
        consumeStyle(&tree)
        #expect(!tree.isDirty(.width, at: block))
    }

    @Test func differentValueMarks() {
        var (style, tree, block) = makeStyleFixture()
        style.apply(["width": "10px"])
        consumeStyle(&tree)
        tree.setFieldClean(.width, 10, for: block)

        style.set(.length(20), for: .width)
        consumeStyle(&tree)
        #expect(tree.isDirty(.width, at: block))
    }

    @Test func absentPropertyStillMarks() {
        var (style, tree, block) = makeStyleFixture()
        tree.setFieldClean(.width, 0, for: block)
        #expect(style.computed.box.size.width == nil)

        style.set(.length(20), for: .width)
        consumeStyle(&tree)

        #expect(tree.isDirty(.width, at: block))
    }

    @Test func removingAPropertyMarksTheLayoutField() {
        var (style, tree, block) = makeStyleFixture()
        style.apply(["width": "10px"])
        consumeStyle(&tree)
        tree.setFieldClean(.width, 10, for: block)

        style.apply(["height": "5px"])
        consumeStyle(&tree)
        #expect(tree.isDirty(.width, at: block))
    }

    @Test func paintOnlyChangeDoesNotMark() {
        var (style, tree, block) = makeStyleFixture()
        tree.setFieldClean(.width, 10, for: block)

        style.apply(["color": "red"])
        consumeStyle(&tree)

        #expect(!tree.isDirty(.width, at: block))
    }

    @Test func identicalApplyDoesNotMark() {
        var (style, tree, block) = makeStyleFixture()
        style.apply(["width": "10px"])
        consumeStyle(&tree)
        tree.setFieldClean(.width, 10, for: block)

        profiler.reset()
        style.apply(["width": "10px"])
        consumeStyle(&tree)

        #expect(!tree.isDirty(.width, at: block))
        #expect((profiler.snapshot()["style.fields.changed"]?.count ?? 0) == 0)
    }

    @Test func mutateMarksTheLayoutField() {
        var (style, tree, block) = makeStyleFixture()
        tree.setFieldClean(.width, 10, for: block)

        style.mutate { $0.box.size.width = 30 }
        consumeStyle(&tree)

        #expect(tree.isDirty(.width, at: block))
    }

    @Test func aRevisionIsAppliedOnce() {
        var (style, tree, block) = makeStyleFixture()
        style.set(.length(20), for: .width)
        consumeStyle(&tree)
        tree.setFieldClean(.width, 20, for: block)

        consumeStyle(&tree)

        #expect(!tree.isDirty(.width, at: block))
    }

    @Test func applyStoresTypedValues() {
        let style = StyleFields()
        #expect(style.computed == .initial)

        style.apply(["width": "10px", "height": "5px"])
        #expect(style.computed.box.size.width == 10)
        #expect(style.computed.box.size.height == 5)

        style.apply(["width": "10px"])
        #expect(style.computed.box.size.height == nil)
    }

    @Test func rebuildDoesNotDuplicateDependents() {
        var (_, tree, _) = makeStyleFixture()
        let key: FieldKey = .style(tree.dom.root, .width)

        tree.dependencies.rebuild(from: tree)
        let first: Int = tree.dependencies.count(of: key)
        tree.dependencies.rebuild(from: tree)

        #expect(first == 1)
        #expect(tree.dependencies.count(of: key) == 1)
    }

    @Test func applyBumpsRevisionOnceWhenValuesChange() {
        let style: StyleFields = StyleFields()
        let before: UInt64 = style.revision

        style.apply(["width": "10px", "height": "5px"])

        #expect(style.revision == before + 1)
    }

    @Test func identicalApplyDoesNotBumpRevision() {
        let style: StyleFields = StyleFields()
        style.apply(["width": "10px"])
        let before: UInt64 = style.revision

        style.apply(["width": "10px"])

        #expect(style.revision == before)
    }

    @Test func typedWriteBumpsRevisionOnlyWhenValueChanges() {
        let style: StyleFields = StyleFields()
        let before: UInt64 = style.revision

        style.set(.length(10), for: .width)
        #expect(style.revision == before + 1)

        let afterFirstWrite: UInt64 = style.revision
        style.set(.length(10), for: .width)
        #expect(style.revision == afterFirstWrite)

        style.set(.length(20), for: .width)
        #expect(style.revision == afterFirstWrite + 1)
    }

    @Test func removingAValueBumpsRevision() {
        let style: StyleFields = StyleFields()
        style.apply(["width": "10px", "height": "5px"])
        let before: UInt64 = style.revision

        style.apply(["width": "10px"])

        #expect(style.revision == before + 1)
    }
}

@MainActor
private func makeStyleFixture() -> (StyleFields, LayoutTree, LayoutID) {
    let dom: DOMTree = DOMTree()
    var tree: LayoutTree = LayoutTree(dom: dom)
    let blockID: LayoutID = tree.append(
        kind: .block(BlockData()),
        dom: dom.root,
        parent: tree.rootID,
        previous: nil
    )
    for field in [LayoutField.zoom, .x, .y, .width, .inlineContent, .children] {
        tree.markUsed(field, at: blockID)
    }
    tree.dependencies.rebuild(from: tree)
    return (dom.style(of: dom.root), tree, blockID)
}

@MainActor
private func consumeStyle(_ tree: inout LayoutTree) {
    tree.refreshInputs(LayoutInputsBuilder.build(dom: tree.dom))
    tree.consumeStyleChanges()
}
