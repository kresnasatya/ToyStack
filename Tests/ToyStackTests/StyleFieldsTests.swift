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
        _ = style.read("width", notify: target)

        style["width"] = "10px"
        #expect(!target.dirty)
    }

    @Test func differentValueMarks() {
        let style = StyleFields()
        style.apply(["width": "10px"])
        let target = StyleTestTarget()
        _ = style.read("width", notify: target)

        style["width"] = "20px"
        #expect(target.dirty)
    }

    @Test func absentPropertyGetsALiveEdge() {
        let style = StyleFields()
        let target = StyleTestTarget()

        #expect(style.read("width", notify: target) == nil)
        style["width"] = "20px"

        #expect(target.dirty)
    }

    @Test func removingAPropertyMarksAndKeepsTheEdge() {
        let style = StyleFields()
        style.apply(["width": "10px"])
        let target = StyleTestTarget()
        _ = style.read("width", notify: target)

        style.apply(["height": "5px"])
        #expect(target.dirty)

        target.set(1)
        style["width"] = "30px"
        #expect(target.dirty)
    }

    @Test func identicalApplyDoesNotMark() {
        let style = StyleFields()
        style.apply(["width": "10px"])
        let target = StyleTestTarget()
        _ = style.read("width", notify: target)

        profiler.reset()
        style.apply(["width": "10px"])

        #expect(!target.dirty)
        #expect((profiler.snapshot()["style.fields.changed"]?.count ?? 0) == 0)
    }

    @Test func snapshotAndEmpty() {
        let style = StyleFields()
        #expect(style.isEmpty)

        style.apply(["width": "10px", "height": "5px"])
        #expect(!style.isEmpty)
        #expect(style.snapshot() == ["width": "10px", "height": "5px"])

        style.apply(["width": "10px"])
        #expect(style.snapshot() == ["width": "10px"])
    }
}

@MainActor
private final class StyleTestTarget: FieldOwner, InvalidatableField {
    var dirty: Bool = false
    var fieldName: String { "target" }
    var isDirty: Bool { dirty }
    var frozenDependencies: Bool { false }
    var invalidationNames: [String] { [] }
    var ref: FieldRef { FieldRef(owner: self, name: .style("target")) }

    func mark() { dirty = true }
    func set(_ value: CGFloat) { dirty = false }
    func addInvalidation(_ field: any InvalidatableField) {}
    func containsInvalidation(_ field: any InvalidatableField) -> Bool { false }

    func markField(_ name: FieldName) { dirty = true }
    func addDependency(_ name: FieldName, _ field: FieldRef) {}
    func containsDependency(_ name: FieldName, _ field: FieldRef) -> Bool { false }
    func fieldIsDirty(_ name: FieldName) -> Bool { dirty }
    func fieldIsFrozen(_ name: FieldName) -> Bool { false }
    func dependencyNames(_ name: FieldName) -> [String] { [] }
}
