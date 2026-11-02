import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct StyleFieldsTests {

    @Test func sameValueDoesNotMark() {
        let style = StyleFields()
        style.apply(["width": "10px"])
        let target = StyleTestTarget()
        style.field(.width).touch(target)

        style.set(.length(10), for: .width)
        #expect(!target.dirty)
    }

    @Test func differentValueMarks() {
        let style = StyleFields()
        style.apply(["width": "10px"])
        let target = StyleTestTarget()
        style.field(.width).touch(target)

        style.set(.length(20), for: .width)
        #expect(target.dirty)
    }

    @Test func absentPropertyGetsALiveEdge() {
        let style = StyleFields()
        let target = StyleTestTarget()

        style.field(.width).touch(target)
        #expect(style.computed.box.size.width == nil)
        style.set(.length(20), for: .width)

        #expect(target.dirty)
    }

    @Test func removingAPropertyMarksAndKeepsTheEdge() {
        let style = StyleFields()
        style.apply(["width": "10px"])
        let target = StyleTestTarget()
        style.field(.width).touch(target)

        style.apply(["height": "5px"])
        #expect(target.dirty)

        target.set(1)
        style.set(.length(30), for: .width)
        #expect(target.dirty)
    }

    @Test func identicalApplyDoesNotMark() {
        let style = StyleFields()
        style.apply(["width": "10px"])
        let target = StyleTestTarget()
        style.field(.width).touch(target)

        profiler.reset()
        style.apply(["width": "10px"])

        #expect(!target.dirty)
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
        let style = StyleFields()
        style.apply(["width": "10px"])

        for _ in 0..<50 {
            registerDeadDependency(style)
        }

        let live = StyleTestTarget()
        style.field(.width).touch(live)

        withExtendedLifetime(live) {
            #expect(style.dependentCount(for: .width) == 1)
        }
    }

    @Test func removingAPropertyEdgeStopsMarking() {
        let style = StyleFields()
        style.apply(["width": "10px"])
        let target = StyleTestTarget()
        style.field(.width).touch(target)

        style.removeDependency(.style(.width), target.ref)
        style.set(.length(20), for: .width)

        #expect(!target.dirty)
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
private final class StyleTestTarget: FieldOwner, InvalidatableField {
    var dirty: Bool = false
    var fieldName: String { "target" }
    var isDirty: Bool { dirty }
    var frozenDependencies: Bool { false }
    var invalidationNames: [String] { [] }
    var ref: FieldRef { FieldRef(owner: self, name: .style(.width)) }

    func mark() { dirty = true }
    func set(_ value: CGFloat) { dirty = false }
    func addInvalidation(_ field: any InvalidatableField) {}
    func removeInvalidation(_ field: any InvalidatableField) {}
    func containsInvalidation(_ field: any InvalidatableField) -> Bool { false }

    func markField(_ name: FieldName) { dirty = true }
    func addDependency(_ name: FieldName, _ field: FieldRef) {}
    func removeDependency(_ name: FieldName, _ field: FieldRef) {}
    func containsDependency(_ name: FieldName, _ field: FieldRef) -> Bool { false }
    func fieldIsDirty(_ name: FieldName) -> Bool { dirty }
    func fieldIsFrozen(_ name: FieldName) -> Bool { false }
    func dependencyNames(_ name: FieldName) -> [String] { [] }
}

@MainActor
private func registerDeadDependency(_ style: StyleFields) {
    let dead = StyleTestTarget()
    style.field(.width).touch(dead)
}
