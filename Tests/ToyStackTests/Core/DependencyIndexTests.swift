import Testing

@testable import Engine

@Suite
struct DependencyIndexTests {
    private static let parentY: FieldKey = .layout(LayoutID(raw: 0), .y)
    private static let lineY: FieldKey = .layout(LayoutID(raw: 1), .y)
    private static let previousHeight: FieldKey = .layout(LayoutID(raw: 2), .height)

    @Test func copyKeepsItsEdgesWhenTheOriginalIsWritten() {
        var original: DependencyIndex = DependencyIndex()
        original.add(Self.lineY, for: Self.parentY)
        let installed: DependencyIndex = original

        original.replaceDependent(Self.lineY, with: [Self.previousHeight])

        #expect(installed.fields(for: Self.parentY) == [Self.lineY], "a write reached the other copy")
        #expect(installed.fields(for: Self.previousHeight).isEmpty)
        #expect(original.fields(for: Self.parentY).isEmpty)
        #expect(original.fields(for: Self.previousHeight) == [Self.lineY])
    }

    @Test func writeGivesTheWritterItsOwnIndex() {
        var original: DependencyIndex = DependencyIndex()
        original.add(Self.lineY, for: Self.parentY)
        var copy: DependencyIndex = original
        let sharedBeforeWrite: Bool = !original.hasNoOtherOwner()
        #expect(sharedBeforeWrite)

        copy.removeDependent(Self.lineY)

        let copyOwnsItsIndex: Bool = copy.hasNoOtherOwner()
        let originalOwnsItsIndex: Bool = original.hasNoOtherOwner()
        #expect(copyOwnsItsIndex, "the writer still shares the index")
        #expect(originalOwnsItsIndex, "the original still shares the index")
    }
}
