import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct StyleFieldsTests {

    @Test func sameValueDoesNotMark() {
        let (style, target) = makeStyleFixture()
        style.apply(["width": "10px"])
        style.field(.width).touch(target.fontField)

        style.set(.length(10), for: .width)
        #expect(!target.fontField.isDirty)
    }

    @Test func differentValueMarks() {
        let (style, target) = makeStyleFixture()
        style.apply(["width": "10px"])
        style.field(.width).touch(target.fontField)

        style.set(.length(20), for: .width)
        #expect(target.fontField.isDirty)
    }

    @Test func absentPropertyGetsALiveEdge() {
        let (style, target) = makeStyleFixture()

        style.field(.width).touch(target.fontField)
        #expect(style.computed.box.size.width == nil)
        style.set(.length(20), for: .width)

        #expect(target.fontField.isDirty)
    }

    @Test func removingAPropertyMarksAndKeepsTheEdge() {
        let (style, target) = makeStyleFixture()
        style.apply(["width": "10px"])
        style.field(.width).touch(target.fontField)

        style.apply(["height": "5px"])
        #expect(target.fontField.isDirty)

        target.fontField.setClean(inlineDefaultFont)
        style.set(.length(30), for: .width)
        #expect(target.fontField.isDirty)
    }

    @Test func identicalApplyDoesNotMark() {
        let (style, target) = makeStyleFixture()
        style.apply(["width": "10px"])
        style.field(.width).touch(target.fontField)

        profiler.reset()
        style.apply(["width": "10px"])

        #expect(!target.fontField.isDirty)
        #expect((profiler.snapshot()["style.fields.changed"]?.count ?? 0) == 0)
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

    @Test func deadDependentsDoNotAccumulate() {
        let (style, target) = makeStyleFixture()
        style.apply(["width": "10px"])

        for _ in 0..<50 {
            style.field(.width).touch(target.fontField)
        }

        #expect(style.dependentCount(for: .width) == 1)
    }

    @Test func removingAPropertyEdgeStopsMarking() {
        let (style, target) = makeStyleFixture()
        style.apply(["width": "10px"])
        style.field(.width).touch(target.fontField)

        style.removeDependency(.width, target.fontField.ref)
        style.set(.length(20), for: .width)

        #expect(!target.fontField.isDirty)
        #expect(style.dependentCount(for: .width) == 0)
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
private func makeStyleFixture() -> (StyleFields, LayoutRef) {
    let root: Element = Element(tag: "html", attributes: [:], parent: nil)
    let dom: DOMTree = DOMTree(root: root)
    let tree: LayoutTree = LayoutTree(dom: dom)
    let target: LayoutRef = tree.root
    target.fontField.setClean(inlineDefaultFont)
    return (root.style, target)
}
