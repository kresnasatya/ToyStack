import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct StyleFieldsTests {

    @Test func sameValueDoesNotMark() {
        let style = StyleFields()
        style.apply(["width": "10px"])
        let target = ProtectedField<CGFloat>("target", cleanValue: 1)
        _ = style.read("width", notify: target)

        style["width"] = "10px"
        #expect(!target.dirty)
    }

    @Test func differentValueMarks() {
        let style = StyleFields()
        style.apply(["width": "10px"])
        let target = ProtectedField<CGFloat>("target", cleanValue: 1)
        _ = style.read("width", notify: target)

        style["width"] = "20px"
        #expect(target.dirty)
    }

    @Test func absentPropertyGetsALiveEdge() {
        let style = StyleFields()
        let target = ProtectedField<CGFloat>("target", cleanValue: 1)

        #expect(style.read("width", notify: target) == nil)
        style["width"] = "20px"

        #expect(target.dirty)
    }

    @Test func removingAPropertyMarksAndKeepsTheEdge() {
        let style = StyleFields()
        style.apply(["width": "10px"])
        let target = ProtectedField<CGFloat>("target", cleanValue: 1)
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
        let target = ProtectedField<CGFloat>("target", cleanValue: 1)
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
